extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_verify")

func _verify() -> void:
    _check(ProjectSettings.get_setting("application/config/name") == "Taiko Flow", "exported identity")
    _check(ResourceLoader.exists("res://scenes/main.tscn"), "exported main scene")
    _check(ResourceLoader.exists("res://scripts/main.gd"), "exported gameplay script")
    _check(ResourceLoader.exists("res://assets/template/fonts/ui_regular.tres"), "exported Japanese UI font")
    var packed := load("res://scenes/main.tscn") as PackedScene
    if packed != null:
        var main := packed.instantiate()
        root.add_child(main)
        await process_frame
        await process_frame
        _check(str(main.get("state")) == "title", "pack boots to title")
        var song: Dictionary = main.get("song")
        _check(str(song.get("title", "")) == "夜光まつり", "pack includes built-in chart")
        _check((song.get("notes", []) as Array).size() > 80, "pack includes playable notes")
        main.call("_start_song")
        await process_frame
        _check(str(main.get("state")) == "playing", "pack starts gameplay")
        main.queue_free()
        await process_frame
    if failures.is_empty():
        print("[exported-pack] PASS: identity, scene, font, chart, boot, gameplay")
        quit(0)
    else:
        for failure in failures:
            push_error("[exported-pack] " + failure)
        quit(1)

func _check(condition: bool, context: String) -> void:
    if not condition and context not in failures:
        failures.append(context)

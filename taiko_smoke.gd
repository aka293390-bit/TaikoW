extends Node

var failures: Array[String] = []
var checks := 0

func _ready() -> void:
    call_deferred("_run")

func _run() -> void:
    var packed := load("res://scenes/main.tscn") as PackedScene
    _check(packed != null, "main scene loads")
    if packed == null:
        _finish()
        return
    var main := packed.instantiate()
    get_tree().root.add_child(main)
    await get_tree().process_frame
    await get_tree().process_frame
    _check(str(main.get("state")) == "title", "boots to title")
    var built_in: Dictionary = main.get("song")
    _check(str(built_in.get("title", "")) == "夜光まつり", "built-in song is ready")
    _check((built_in.get("notes", []) as Array).size() > 80, "built-in chart has notes")
    var tja := "TITLE: Smoke Chart\nBPM: 120\nCOURSE: Oni\nLEVEL: 5\n#START\n11002000,\n#BPMCHANGE 150\n30004000,\n#GOGOSTART\n11112222,\n#GOGOEND\n#END\n"
    var parsed: Dictionary = main.call("_parse_tja", tja)
    _check(str(parsed.get("title", "")) == "Smoke Chart", "TJA title parses")
    _check(float(parsed.get("bpm", 0.0)) == 120.0, "TJA header BPM parses")
    _check((parsed.get("notes", []) as Array).size() >= 8, "TJA notes parse")
    main.call("_start_song")
    _check(str(main.get("state")) == "playing", "start enters gameplay")
    _check((main.get("notes") as Array).size() > 0, "gameplay receives chart")
    main.set("paused", true)
    _check(bool(main.get("paused")), "pause state is writable")
    main.set("paused", false)
    main.queue_free()
    await get_tree().process_frame
    _finish()

func _check(condition: bool, message: String) -> void:
    checks += 1
    if not condition:
        failures.append(message)

func _finish() -> void:
    if failures.is_empty():
        print("[taiko-tests] PASS: %d checks" % checks)
        get_tree().quit(0)
    else:
        for failure in failures:
            push_error("[taiko-tests] " + failure)
        get_tree().quit(1)

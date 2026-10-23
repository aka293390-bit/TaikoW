extends Control

# Taiko Flow — an original, browser-first rhythm game.
# All scoring and TJA parsing happen locally in this scene so the web export
# does not need a server or a database.

const BASE_SIZE := Vector2(1280.0, 720.0)
const HIT_X := 270.0
const NOTE_SPEED := 360.0
const APPROACH_TIME := 2.45
const GREAT_WINDOW := 0.075
const GOOD_WINDOW := 0.16
const MISS_WINDOW := 0.30

const BG := Color("2a0b12")
const PANEL := Color("4a1720")
const PANEL_2 := Color("6b241c")
const INK := Color("fff4dd")
const MUTED := Color("e5b9a5")
const CYAN := Color("75e5d1")
const PINK := Color("ff6b76")
const YELLOW := Color("ffd34e")
const RED := Color("e84b36")
const DON := Color("ff625c")
const KAT := Color("66d9e8")
const GOGO := Color("ffd166")

var ui_font: Font
var ui_bold: Font
var display_font: Font

var state := "title"
var paused := false
var song: Dictionary = {}
var notes: Array[Dictionary] = []
var note_index := 0
var elapsed := -2.0
var score := 0
var combo := 0
var max_combo := 0
var gauge := 0.28
var great_count := 0
var good_count := 0
var miss_count := 0
var total_notes := 0
var last_judgment := ""
var last_judgment_color := INK
var judgment_timer := 0.0
var pulse_timer := 0.0
var hit_flash := 0.0
var drum_flash := 0.0
var gogo_active := false
var status_message := "内蔵譜面を選択中"
var imported_file_name := ""
var selected_song_card := 0
var result_rank := ""
var result_message := ""
var show_help := false
var title_time := 0.0
var rng := RandomNumberGenerator.new()
var confetti: Array[Dictionary] = []

var file_dialog: FileDialog
var browser_file_input: Variant
var browser_file_reader: Variant
var import_button_rect := Rect2()
var play_button_rect := Rect2()
var help_button_rect := Rect2()
var pause_button_rect := Rect2()
var retry_button_rect := Rect2()
var title_button_rect := Rect2()
var left_pad_rect := Rect2()
var right_pad_rect := Rect2()
var help_close_rect := Rect2()

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    # The bundled subset is optimized for the template's default locales; this
    # game pins ja-JP, so ship a complete Japanese-capable font for the browser.
    ui_font = load("res://assets/fonts/ipagp.ttf") as Font
    ui_bold = load("res://assets/fonts/ipagp.ttf") as Font
    display_font = load("res://assets/fonts/ipagp.ttf") as Font
    rng.randomize()
    song = _built_in_song()
    _make_file_dialog()
    queue_redraw()

func _make_file_dialog() -> void:
    file_dialog = FileDialog.new()
    file_dialog.name = "TjaFileDialog"
    file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    file_dialog.access = FileDialog.ACCESS_FILESYSTEM
    file_dialog.title = "TJA譜面を読み込む"
    file_dialog.filters = PackedStringArray(["*.tja ; TJA譜面ファイル", "*.txt ; テキスト譜面"])
    file_dialog.file_selected.connect(_on_tja_file_selected)
    add_child(file_dialog)

func _open_local_tja_picker() -> void:
    # In a Web export this creates a browser-owned file input. The selected
    # file never enters the Manus workspace; only its text is read in memory.
    if OS.has_feature("web"):
        var document := JavaScriptBridge.get_interface("document")
        browser_file_input = JavaScriptBridge.create_object("input")
        browser_file_input.type = "file"
        browser_file_input.accept = ".tja,.txt,text/plain"
        browser_file_input.style = "display:none"
        document.body.appendChild(browser_file_input)
        browser_file_input.addEventListener("change", JavaScriptBridge.create_callback(_on_browser_file_selected))
        browser_file_input.click()
    else:
        file_dialog.popup_centered_ratio(0.82)

func _on_browser_file_selected(args: Array) -> void:
    if args.is_empty():
        return
    var target = args[0].target
    if target.files.length == 0:
        return
    browser_file_reader = JavaScriptBridge.create_object("FileReader")
    browser_file_reader.onload = JavaScriptBridge.create_callback(_on_browser_file_loaded)
    browser_file_reader.readAsText(target.files[0])

func _on_browser_file_loaded(args: Array) -> void:
    if args.is_empty():
        return
    var event = args[0]
    var text: String = str(event.target.result)
    _load_tja_text(text, "端末から読み込んだTJA")

func _load_tja_text(text: String, display_name: String) -> void:
    var parsed := _parse_tja(text)
    if parsed.is_empty() or (parsed.get("notes", []) as Array).is_empty():
        status_message = "譜面データが見つかりませんでした"
        return
    song = parsed
    imported_file_name = display_name
    status_message = "端末から読み込み完了"
    state = "title"

func _process(delta: float) -> void:
    title_time += delta
    pulse_timer += delta
    if state == "playing" and not paused:
        elapsed += delta
        judgment_timer = maxf(0.0, judgment_timer - delta)
        hit_flash = maxf(0.0, hit_flash - delta * 3.5)
        drum_flash = maxf(0.0, drum_flash - delta * 4.0)
        _advance_misses()
        if note_index >= notes.size() and elapsed > _last_note_time() + 1.15:
            _finish_song()
    elif state == "results":
        judgment_timer = maxf(0.0, judgment_timer - delta)
    queue_redraw()

func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        var key: int = event.keycode if event.keycode != 0 else event.physical_keycode
        if key == KEY_ESCAPE or key == KEY_P:
            if state == "playing":
                paused = not paused
            elif state == "help":
                show_help = false
                state = "title"
            get_viewport().set_input_as_handled()
            return
        if key == KEY_ENTER or key == KEY_SPACE:
            if state == "title":
                _start_song()
            elif state == "results":
                _start_song()
            elif state == "help":
                state = "title"
            elif state == "playing" and not paused:
                _hit("any")
            get_viewport().set_input_as_handled()
            return
        if key == KEY_F or key == KEY_J or key == KEY_D or key == KEY_K or key == KEY_G or key == KEY_H or key == KEY_S or key == KEY_L:
            if state == "playing" and not paused:
                _hit("any")
            get_viewport().set_input_as_handled()
            return
    if event is InputEventMouseButton and event.pressed:
        _handle_pointer(event.position)
    elif event is InputEventScreenTouch and event.pressed:
        _handle_pointer(event.position)

func _handle_pointer(pos: Vector2) -> void:
    if state == "title":
        if play_button_rect.has_point(pos):
            _start_song()
        elif import_button_rect.has_point(pos):
            _open_local_tja_picker()
        elif help_button_rect.has_point(pos):
            state = "help"
        return
    if state == "help":
        if help_close_rect.has_point(pos):
            state = "title"
        return
    if state == "playing":
        if pause_button_rect.has_point(pos):
            paused = not paused
        elif not paused and (left_pad_rect.has_point(pos) or right_pad_rect.has_point(pos)):
            _hit("any")
        return
    if state == "results":
        if retry_button_rect.has_point(pos):
            _start_song()
        elif title_button_rect.has_point(pos):
            state = "title"

func _start_song() -> void:
    notes = []
    for raw_note in song.get("notes", []):
        notes.append((raw_note as Dictionary).duplicate(true))
    note_index = 0
    elapsed = -2.05
    score = 0
    combo = 0
    max_combo = 0
    gauge = 0.28
    great_count = 0
    good_count = 0
    miss_count = 0
    last_judgment = ""
    judgment_timer = 0.0
    paused = false
    gogo_active = false
    result_rank = ""
    confetti.clear()
    total_notes = notes.size()
    state = "playing"
    status_message = ""

func _finish_song() -> void:
    state = "results"
    paused = false
    var accuracy := 0.0
    if total_notes > 0:
        accuracy = (float(great_count) + float(good_count) * 0.65) / float(total_notes)
    if accuracy >= 0.93:
        result_rank = "極"
        result_message = "夜空まで響く、完璧な演奏！"
    elif accuracy >= 0.78:
        result_rank = "華"
        result_message = "すばらしいリズム。もう一度、光らせよう。"
    elif accuracy >= 0.58:
        result_rank = "灯"
        result_message = "いい流れ。次は魂ゲージを満たそう。"
    else:
        result_rank = "芽"
        result_message = "ここからが本番。リズムを感じて再挑戦！"
    for i in range(34):
        confetti.append({
            "p": Vector2(590.0 + rng.randf_range(-250.0, 250.0), 160.0 + rng.randf_range(-10.0, 120.0)),
            "v": Vector2(rng.randf_range(-50.0, 50.0), rng.randf_range(25.0, 105.0)),
            "c": [PINK, CYAN, YELLOW, Color("9c83ff")][i % 4],
            "r": rng.randf_range(0.0, 6.2)
        })

func _advance_misses() -> void:
    while note_index < notes.size():
        var note := notes[note_index]
        if note.get("type", "don") == "roll":
            if elapsed > float(note.get("time", 0.0)) + float(note.get("duration", 0.8)) + MISS_WINDOW:
                note_index += 1
                continue
            break
        var delta := elapsed - float(note.get("time", 0.0))
        if delta > MISS_WINDOW:
            _register_miss()
            note_index += 1
            continue
        break

func _hit(kind: String) -> void:
    if note_index >= notes.size():
        return
    var note := notes[note_index]
    var note_kind: String = note.get("type", "don")
    if note_kind == "roll":
        var roll_delta := absf(elapsed - float(note.get("time", 0.0)))
        if roll_delta <= 0.34 and elapsed <= float(note.get("time", 0.0)) + float(note.get("duration", 0.8)):
            score += 100
            combo += 1
            max_combo = maxi(max_combo, combo)
            gauge = minf(1.0, gauge + 0.012)
            _set_judgment("連打！", YELLOW)
            drum_flash = 1.0
        return
    var delta := elapsed - float(note.get("time", 0.0))
    var abs_delta := absf(delta)
    if abs_delta > MISS_WINDOW:
        if delta > 0.0:
            _register_miss()
            note_index += 1
        return
    # Taiko Flow uses one unified drum hit: TJA note colors/types are kept for
    # compatibility, but the player never has to split Don and Ka inputs.
    var is_great := abs_delta <= GREAT_WINDOW
    if is_great:
        great_count += 1
        combo += 1
        var points := 1000 if not note.get("big", false) else 1500
        if gogo_active:
            points = int(float(points) * 1.2)
        score += points
        gauge = minf(1.0, gauge + (0.038 if not note.get("big", false) else 0.052))
        _set_judgment("良", CYAN)
    else:
        good_count += 1
        combo += 1
        score += 500
        gauge = minf(1.0, gauge + 0.018)
        _set_judgment("可", YELLOW)
    max_combo = maxi(max_combo, combo)
    note_index += 1
    drum_flash = 1.0
    hit_flash = 1.0

func _register_miss() -> void:
    miss_count += 1
    combo = 0
    gauge = maxf(0.0, gauge - 0.065)
    _set_judgment("不可", RED)

func _set_judgment(text: String, color: Color) -> void:
    last_judgment = text
    last_judgment_color = color
    judgment_timer = 0.62

func _last_note_time() -> float:
    if notes.is_empty():
        return 0.0
    var last: Dictionary = notes[-1]
    return float(last.get("time", 0.0)) + float(last.get("duration", 0.0))

func _on_tja_file_selected(path: String) -> void:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        status_message = "そのファイルを読み込めませんでした"
        return
    _load_tja_text(file.get_as_text(), path.get_file())

func _parse_tja(text: String) -> Dictionary:
    var lines := text.replace("\r", "").split("\n")
    var base := {"title": "TJA譜面", "subtitle": "読み込んだ譜面", "bpm": 120.0, "offset": 0.0, "wave": "", "course": "", "level": "", "notes": []}
    var charts: Array[Dictionary] = []
    var headers := base.duplicate(true)
    var active: Dictionary = {}
    var in_chart := false
    var current_time := 0.0
    var bpm := 120.0
    var measure := Vector2(4.0, 4.0)
    var scroll := 1.0
    var gogo := false
    var i := 0
    while i < lines.size():
        var raw: String = lines[i]
        var line := raw.strip_edges()
        i += 1
        if line.is_empty() or line.begins_with("//"):
            continue
        if not in_chart and (line.contains("=") or line.contains(":")) and not line.begins_with("#"):
            var separator := "=" if line.contains("=") else ":"
            var parts := line.split(separator, false, 1)
            if parts.size() == 2:
                var key := parts[0].strip_edges().to_upper()
                var value := parts[1].strip_edges()
                if key == "BPM":
                    bpm = maxf(1.0, value.to_float())
                    headers["bpm"] = bpm
                elif key == "OFFSET":
                    headers["offset"] = value.to_float()
                elif key == "TITLE":
                    headers["title"] = value
                elif key == "SUBTITLE":
                    headers["subtitle"] = value
                elif key == "WAVE":
                    headers["wave"] = value
                elif key == "COURSE":
                    headers["course"] = value
                elif key == "LEVEL":
                    headers["level"] = value
            continue
        var upper := line.to_upper()
        if upper == "#START":
            in_chart = true
            active = headers.duplicate(true)
            active["notes"] = []
            current_time = -float(headers.get("offset", 0.0))
            bpm = float(headers.get("bpm", 120.0))
            measure = Vector2(4.0, 4.0)
            scroll = 1.0
            gogo = false
            continue
        if upper == "#END":
            if in_chart:
                active["notes"] = _sort_notes(active.get("notes", []))
                charts.append(active.duplicate(true))
            in_chart = false
            continue
        if not in_chart:
            continue
        if upper == "#GOGOSTART":
            gogo = true
            continue
        if upper == "#GOGOEND":
            gogo = false
            continue
        if upper == "#BARLINEOFF" or upper == "#BARLINEON":
            continue
        if upper.begins_with("#BPMCHANGE"):
            var value := upper.get_slice(" ", 1) if upper.contains(" ") else upper.get_slice("#BPMCHANGE", 1)
            if value.is_valid_float():
                bpm = maxf(1.0, value.to_float())
            continue
        if upper.begins_with("#MEASURE"):
            var value := upper.get_slice(" ", 1) if upper.contains(" ") else upper.get_slice("#MEASURE", 1)
            var parts := value.split("/")
            if parts.size() == 2:
                measure = Vector2(maxf(1.0, parts[0].to_float()), maxf(1.0, parts[1].to_float()))
            continue
        if upper.begins_with("#SCROLL"):
            var value := upper.get_slice(" ", 1) if upper.contains(" ") else upper.get_slice("#SCROLL", 1)
            if value.is_valid_float():
                scroll = maxf(0.05, value.to_float())
            continue
        if upper.begins_with("#DELAY"):
            var value := upper.get_slice(" ", 1) if upper.contains(" ") else upper.get_slice("#DELAY", 1)
            if value.is_valid_float():
                current_time += value.to_float()
            continue
        if upper.begins_with("#BRANCH") or upper in ["#N", "#E", "#M"]:
            continue
        if line.begins_with("#") or not line.contains(","):
            continue
        var measure_text := line
        if measure_text.ends_with(","):
            measure_text = measure_text.substr(0, measure_text.length() - 1)
        var chars := measure_text.split("")
        if chars.is_empty():
            continue
        var measure_duration := (60.0 / bpm) * 4.0 * (measure.x / measure.y)
        var step := measure_duration / float(chars.size())
        for index in range(chars.size()):
            var digit: String = chars[index]
            if digit == "1" or digit == "2" or digit == "3" or digit == "4":
                var is_don := digit == "1" or digit == "3"
                var is_big := digit == "3" or digit == "4"
                (active["notes"] as Array).append({"time": current_time + step * float(index), "type": ("don_big" if is_don else "kat_big") if is_big else ("don" if is_don else "kat"), "big": is_big, "scroll": scroll, "gogo": gogo})
            elif digit == "5" or digit == "6":
                (active["notes"] as Array).append({"time": current_time + step * float(index), "type": "roll", "duration": step * 3.5, "big": digit == "6", "scroll": scroll, "gogo": gogo})
        current_time += measure_duration
    if in_chart:
        active["notes"] = _sort_notes(active.get("notes", []))
        charts.append(active.duplicate(true))
    if charts.is_empty():
        return {}
    var chosen: Dictionary = charts[0]
    for chart in charts:
        var course := str(chart.get("course", "")).to_lower()
        if course == "oni" or course == "extreme" or course == "ura":
            chosen = chart
            break
    return chosen

func _sort_notes(items: Array) -> Array[Dictionary]:
    var output: Array[Dictionary] = []
    for item in items:
        output.append(item as Dictionary)
    output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("time", 0.0)) < float(b.get("time", 0.0)))
    return output

func _built_in_song() -> Dictionary:
    var result := {"title": "夜光まつり", "subtitle": "内蔵オリジナル譜面  /  風鈴のリズム", "bpm": 132.0, "offset": 0.0, "wave": "", "course": "かんたん", "level": "★ 4", "notes": []}
    var out: Array[Dictionary] = []
    var beat := 60.0 / 132.0
    var t := 1.2
    var pattern := ["don", "kat", "don", "kat", "don", "don", "kat", "don", "roll", "don", "kat", "don_big", "kat", "don", "kat_big", "don"]
    for bar in range(13):
        for j in range(pattern.size()):
            if bar == 3 and j == 8:
                out.append({"time": t, "type": "roll", "duration": beat * 2.7, "big": false, "scroll": 1.0, "gogo": true})
            elif not (bar == 6 and j in [3, 7]) and not (bar == 10 and j == 5):
                var kind: String = pattern[j]
                out.append({"time": t, "type": kind, "big": kind.ends_with("_big"), "scroll": 1.0 if bar < 8 else 1.15, "gogo": bar >= 4 and bar <= 7})
            t += beat * 0.5
        t += beat * 0.4
    result["notes"] = out
    return result

func _draw() -> void:
    var sx := size.x / BASE_SIZE.x
    var sy := size.y / BASE_SIZE.y
    var scale := minf(sx, sy)
    var offset := Vector2((size.x - BASE_SIZE.x * scale) * 0.5, (size.y - BASE_SIZE.y * scale) * 0.5)
    draw_set_transform(offset, 0.0, Vector2(scale, scale))
    draw_rect(Rect2(Vector2.ZERO, BASE_SIZE), BG)
    _draw_background()
    if state == "title":
        _draw_title()
    elif state == "playing":
        _draw_playing()
    elif state == "results":
        _draw_results()
    elif state == "help":
        _draw_title()
        _draw_help()
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_background() -> void:
    # Original summer-festival stage: red awning, wooden stalls, lanterns and
    # a warm central curtain. It is drawn in code rather than copying artwork.
    draw_rect(Rect2(0.0, 0.0, BASE_SIZE.x, BASE_SIZE.y), Color("b82b24"), true)
    draw_rect(Rect2(0.0, 0.0, BASE_SIZE.x, 132.0), Color("e54a25"), true)
    draw_rect(Rect2(0.0, 92.0, BASE_SIZE.x, 22.0), Color("5a1519"), true)
    for i in range(16):
        var stripe_x := float(i) * 82.0 - 20.0
        draw_colored_polygon(PackedVector2Array([Vector2(stripe_x, 0.0), Vector2(stripe_x + 44.0, 0.0), Vector2(stripe_x + 30.0, 92.0), Vector2(stripe_x - 14.0, 92.0)]), Color("ff7b31", 0.65) if i % 2 == 0 else Color("a91f26", 0.72))
    # Side stalls and central festival curtain.
    draw_rect(Rect2(0.0, 132.0, 350.0, 310.0), Color("8d2020"), true)
    draw_rect(Rect2(930.0, 132.0, 350.0, 310.0), Color("8d2020"), true)
    draw_rect(Rect2(344.0, 128.0, 592.0, 306.0), Color("ffd28a"), true)
    draw_rect(Rect2(386.0, 160.0, 508.0, 258.0), Color("ef7251"), true)
    draw_rect(Rect2(426.0, 204.0, 428.0, 214.0), Color("ffb55e"), true)
    draw_arc(Vector2(640.0, 410.0), 230.0, PI, TAU, 40, Color(0.20, 0.04, 0.05, 0.78), 38.0)
    draw_string(ui_bold, Vector2(505.0, 250.0), "夜光まつり", HORIZONTAL_ALIGNMENT_LEFT, 270.0, 35, Color("fff0bd", 0.92))
    # Stall counters and hanging decorations.
    for x in [34.0, 1010.0]:
        draw_rect(Rect2(x, 300.0, 236.0, 112.0), Color("ef775c"), true)
        draw_rect(Rect2(x, 330.0, 236.0, 82.0), Color("f8d59a"), true)
        draw_line(Vector2(x, 330.0), Vector2(x + 236.0, 330.0), Color("fff0c1"), 7.0)
    for i in range(13):
        var lantern_x := 52.0 + float(i) * 99.0
        var lantern_y := 86.0 + sin(title_time * 1.5 + float(i)) * 5.0
        draw_line(Vector2(lantern_x, 0.0), Vector2(lantern_x, lantern_y - 18.0), Color("5a1519"), 2.0)
        draw_circle(Vector2(lantern_x, lantern_y), 19.0, Color("fff4bf", 0.25))
        draw_circle(Vector2(lantern_x, lantern_y), 13.0, YELLOW if i % 3 == 0 else Color("fff2d1"))
        draw_arc(Vector2(lantern_x, lantern_y), 14.0, 0.0, TAU, 24, Color("ff5b35"), 2.0)
    # Floor and patterned festival cloth.
    draw_rect(Rect2(0.0, 442.0, BASE_SIZE.x, 278.0), Color("321016"), true)
    draw_rect(Rect2(0.0, 442.0, BASE_SIZE.x, 38.0), Color("f8dbb0"), true)
    for i in range(16):
        var x := float(i) * 80.0
        draw_colored_polygon(PackedVector2Array([Vector2(x, 442.0), Vector2(x + 40.0, 442.0), Vector2(x + 22.0, 480.0), Vector2(x - 18.0, 480.0)]), Color("d34c45") if i % 2 == 0 else Color("6db6a6"))
    for i in range(10):
        var glow := Vector2(96.0 + float(i) * 126.0, 532.0 + sin(title_time + float(i)) * 18.0)
        draw_circle(glow, 42.0, Color(1.0, 0.43, 0.20, 0.035))
    draw_rect(Rect2(0.0, 0.0, BASE_SIZE.x, BASE_SIZE.y), Color(0.06, 0.015, 0.02, 0.34), true)

func _draw_title() -> void:
    _draw_header("TAIKO FLOW", "TJA対応 / ブラウザで完結するオリジナル太鼓ゲーム")
    draw_string(display_font, Vector2(82.0, 182.0), "夜を、叩こう。", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 54, INK)
    draw_string(ui_font, Vector2(86.0, 219.0), "譜面の鼓動を読み、光る判定ラインへ音を届ける。", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, MUTED)
    # left play card
    var card := Rect2(82.0, 280.0, 610.0, 250.0)
    _panel(card, PANEL, Color(0.36, 0.28, 0.62, 0.8), 18.0)
    draw_string(ui_bold, Vector2(112.0, 322.0), "演奏する譜面", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, CYAN)
    draw_string(display_font, Vector2(112.0, 370.0), str(song.get("title", "無題")), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 36, INK)
    draw_string(ui_font, Vector2(114.0, 402.0), str(song.get("subtitle", "")), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, MUTED)
    var course := str(song.get("course", "内蔵"))
    var level := str(song.get("level", ""))
    draw_string(ui_bold, Vector2(114.0, 446.0), "BPM " + str(snappedf(float(song.get("bpm", 120.0)), 0.1)), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, YELLOW)
    draw_string(ui_font, Vector2(250.0, 446.0), "コース  " + course + "   " + level, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, MUTED)
    if imported_file_name != "":
        draw_string(ui_font, Vector2(114.0, 482.0), "FILE  " + imported_file_name, HORIZONTAL_ALIGNMENT_LEFT, 420.0, 13, PINK)
    play_button_rect = Rect2(112.0, 556.0, 280.0, 64.0)
    import_button_rect = Rect2(410.0, 556.0, 282.0, 64.0)
    _button(play_button_rect, play_button_rect, "演奏をはじめる", CYAN, true)
    _button(import_button_rect, import_button_rect, "端末からTJAを選ぶ", PINK, false)
    # right info stack
    var side := Rect2(742.0, 280.0, 456.0, 340.0)
    _panel(side, Color(0.10, 0.07, 0.22, 0.82), Color(0.25, 0.20, 0.48, 0.7), 18.0)
    draw_string(ui_bold, Vector2(774.0, 324.0), "PLAY GUIDE", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, PINK)
    _guide_row(Vector2(774.0, 370.0), "たたく", "F / J / G / H  または  Space", PINK)
    _guide_row(Vector2(774.0, 420.0), "タイミング", "ノーツが線に重なったら1回", YELLOW)
    _guide_row(Vector2(774.0, 470.0), "タッチ", "画面下の太鼓をタップ / クリック", CYAN)
    draw_line(Vector2(774.0, 505.0), Vector2(1162.0, 505.0), Color(0.35, 0.28, 0.5, 0.7), 1.0)
    draw_string(ui_font, Vector2(774.0, 542.0), "P / Esc  ポーズ", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, MUTED)
    draw_string(ui_font, Vector2(774.0, 568.0), "TJAのTITLE / BPM / 譜面コマンドを解析", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, MUTED)
    help_button_rect = Rect2(742.0, 646.0, 456.0, 46.0)
    _button(help_button_rect, help_button_rect, "遊び方と対応コマンドを見る", Color("8f7cff"), false)
    if status_message != "":
        draw_string(ui_font, Vector2(84.0, 676.0), status_message, HORIZONTAL_ALIGNMENT_LEFT, 600.0, 13, CYAN)

func _draw_header(title: String, subtitle: String) -> void:
    draw_string(ui_bold, Vector2(54.0, 58.0), "◈", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 27, PINK)
    draw_string(display_font, Vector2(88.0, 59.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24, INK)
    draw_string(ui_font, Vector2(90.0, 83.0), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, MUTED)
    draw_line(Vector2(54.0, 105.0), Vector2(1226.0, 105.0), Color(0.40, 0.30, 0.68, 0.6), 1.0)

func _draw_playing() -> void:
    _draw_header(str(song.get("title", "演奏中")), "演奏中  /  " + str(song.get("course", "内蔵")))
    draw_string(ui_bold, Vector2(1010.0, 52.0), "SCORE  " + _format_score(score), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, YELLOW)
    draw_string(ui_font, Vector2(1010.0, 76.0), "BPM  " + str(snappedf(float(song.get("bpm", 120.0)), 0.1)), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, MUTED)
    # Soul gauge
    draw_string(ui_bold, Vector2(82.0, 142.0), "魂ゲージ", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, YELLOW)
    draw_rect(Rect2(172.0, 130.0, 520.0, 18.0), Color(0.08, 0.06, 0.16, 0.95), true)
    draw_rect(Rect2(172.0, 130.0, 520.0 * gauge, 18.0), Color(1.0, 0.45, 0.55, 0.9) if gauge < 0.75 else Color(1.0, 0.82, 0.32, 0.96), true)
    draw_rect(Rect2(172.0, 130.0, 520.0, 18.0), Color(0.56, 0.47, 0.82, 0.75), false, 2.0)
    if gauge >= 0.75:
        draw_string(ui_bold, Vector2(710.0, 146.0), "魂", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 19, YELLOW)
    draw_string(ui_bold, Vector2(870.0, 146.0), "COMBO  " + str(combo), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, CYAN)
    _draw_lane()
    draw_string(ui_font, Vector2(82.0, 520.0), "ノーツが判定ラインに重なったら、太鼓を1回たたく。", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, MUTED)
    left_pad_rect = Rect2(76.0, 566.0, 1128.0, 112.0)
    right_pad_rect = left_pad_rect
    _touch_pad(left_pad_rect, "たたく", PINK, "クリック / タップ / F J G H / Space")
    pause_button_rect = Rect2(1100.0, 122.0, 104.0, 34.0)
    _button(pause_button_rect, pause_button_rect, "再開" if paused else "ポーズ", PINK, false)
    if paused:
        _draw_pause_overlay()
    if judgment_timer > 0.0:
        var alpha := minf(1.0, judgment_timer * 2.8)
        draw_string(display_font, Vector2(HIT_X - 20.0, 270.0), last_judgment, HORIZONTAL_ALIGNMENT_CENTER, 120.0, 42, Color(last_judgment_color, alpha))
        if combo > 1:
            draw_string(ui_bold, Vector2(HIT_X - 25.0, 306.0), str(combo) + " コンボ", HORIZONTAL_ALIGNMENT_CENTER, 130.0, 14, Color(INK, alpha))

func _draw_lane() -> void:
    var lane := Rect2(68.0, 178.0, 1136.0, 300.0)
    _panel(lane, Color(0.07, 0.05, 0.15, 0.96), Color(0.34, 0.24, 0.60, 0.8), 20.0)
    draw_rect(Rect2(92.0, 220.0, 1086.0, 186.0), Color(0.10, 0.07, 0.22, 0.86), true)
    for i in range(13):
        var x := 112.0 + float(i) * 84.0
        draw_line(Vector2(x, 220.0), Vector2(x, 406.0), Color(0.39, 0.27, 0.55, 0.13), 1.0)
    draw_line(Vector2(92.0, 406.0), Vector2(1178.0, 406.0), Color(0.54, 0.37, 0.76, 0.6), 2.0)
    # Judgment target: an original circular drum glyph.
    draw_circle(Vector2(HIT_X, 313.0), 57.0 + drum_flash * 5.0, Color(0.10, 0.08, 0.25, 0.9))
    draw_arc(Vector2(HIT_X, 313.0), 60.0 + drum_flash * 6.0, 0.0, TAU, 48, Color(PINK, 0.9), 3.0)
    draw_arc(Vector2(HIT_X, 313.0), 43.0, 0.0, TAU, 48, Color(CYAN, 0.65), 2.0)
    draw_circle(Vector2(HIT_X, 313.0), 26.0, Color(0.16, 0.12, 0.31, 1.0))
    draw_line(Vector2(HIT_X - 16.0, 313.0), Vector2(HIT_X + 16.0, 313.0), Color(PINK, 0.9), 3.0)
    draw_line(Vector2(HIT_X, 297.0), Vector2(HIT_X, 329.0), Color(CYAN, 0.9), 3.0)
    draw_string(ui_bold, Vector2(HIT_X - 47.0, 382.0), "判定ライン", HORIZONTAL_ALIGNMENT_CENTER, 94.0, 12, MUTED)
    for note in notes:
        var time := float(note.get("time", 0.0))
        var scroll := float(note.get("scroll", 1.0))
        var distance := (time - elapsed) * NOTE_SPEED * scroll
        if distance < -120.0 or distance > 1000.0:
            continue
        var x := HIT_X + distance
        var y := 313.0
        var kind: String = note.get("type", "don")
        if kind == "roll":
            var end_x := x - float(note.get("duration", 0.8)) * NOTE_SPEED * scroll
            var rect_x := minf(x, end_x)
            var rect_w := maxf(32.0, absf(x - end_x))
            draw_rect(Rect2(rect_x, y - 15.0, rect_w, 30.0), Color(YELLOW, 0.82), true)
            draw_rect(Rect2(rect_x, y - 15.0, rect_w, 30.0), YELLOW, false, 2.0)
            draw_circle(Vector2(x, y), 25.0, YELLOW)
            draw_circle(Vector2(x, y), 15.0, Color("a95b44"))
        else:
            var color := PINK
            var radius := 32.0 if bool(note.get("big", false)) else 24.0
            draw_circle(Vector2(x, y), radius + 5.0, Color(color, 0.16))
            draw_circle(Vector2(x, y), radius, color)
            draw_circle(Vector2(x, y), radius - 6.0, Color(0.12, 0.09, 0.24, 1.0))
            draw_arc(Vector2(x, y), radius - 5.0, 0.0, TAU, 32, color, 3.0)
            if bool(note.get("big", false)):
                draw_arc(Vector2(x, y), radius + 6.0, 0.0, TAU, 32, Color(color, 0.85), 3.0)
                draw_string(ui_bold, Vector2(x - 12.0, y + 6.0), "大", HORIZONTAL_ALIGNMENT_CENTER, 24.0, 14, color)

func _draw_pause_overlay() -> void:
    draw_rect(Rect2(0.0, 0.0, BASE_SIZE.x, BASE_SIZE.y), Color(0.03, 0.02, 0.08, 0.72), true)
    _panel(Rect2(420.0, 218.0, 440.0, 240.0), PANEL, Color(0.48, 0.32, 0.74, 0.9), 20.0)
    draw_string(display_font, Vector2(420.0, 292.0), "ひとやすみ", HORIZONTAL_ALIGNMENT_CENTER, 440.0, 36, INK)
    draw_string(ui_font, Vector2(420.0, 328.0), "P / Esc またはボタンで演奏に戻ります", HORIZONTAL_ALIGNMENT_CENTER, 440.0, 15, MUTED)
    draw_string(ui_bold, Vector2(420.0, 392.0), "PAUSED", HORIZONTAL_ALIGNMENT_CENTER, 440.0, 17, PINK)

func _draw_results() -> void:
    _draw_header("RESULT / 演奏結果", str(song.get("title", "")))
    for item in confetti:
        var p: Vector2 = item["p"]
        p.y += fmod(title_time * float(item["v"].y), 520.0)
        draw_rect(Rect2(p, Vector2(8.0, 3.0)), item["c"], true)
    _panel(Rect2(288.0, 145.0, 704.0, 472.0), Color(0.09, 0.06, 0.20, 0.94), Color(0.44, 0.30, 0.70, 0.95), 26.0)
    draw_string(ui_bold, Vector2(338.0, 196.0), "演奏終了", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, PINK)
    draw_string(display_font, Vector2(338.0, 244.0), str(song.get("title", "")), HORIZONTAL_ALIGNMENT_LEFT, 600.0, 34, INK)
    draw_string(ui_font, Vector2(340.0, 274.0), result_message, HORIZONTAL_ALIGNMENT_LEFT, 600.0, 15, MUTED)
    draw_string(display_font, Vector2(690.0, 363.0), result_rank, HORIZONTAL_ALIGNMENT_CENTER, 180.0, 98, YELLOW)
    draw_string(ui_bold, Vector2(690.0, 402.0), "RANK", HORIZONTAL_ALIGNMENT_CENTER, 180.0, 14, PINK)
    _result_metric(Vector2(350.0, 344.0), "SCORE", _format_score(score), YELLOW)
    _result_metric(Vector2(350.0, 405.0), "MAX COMBO", str(max_combo), CYAN)
    _result_metric(Vector2(350.0, 466.0), "良 / 可 / 不可", str(great_count) + "  /  " + str(good_count) + "  /  " + str(miss_count), INK)
    _result_metric(Vector2(350.0, 527.0), "魂ゲージ", str(int(gauge * 100.0)) + "%", PINK)
    retry_button_rect = Rect2(338.0, 638.0, 300.0, 52.0)
    title_button_rect = Rect2(656.0, 638.0, 300.0, 52.0)
    _button(retry_button_rect, retry_button_rect, "もう一度演奏", CYAN, true)
    _button(title_button_rect, title_button_rect, "譜面選択へ", PINK, false)

func _draw_help() -> void:
    draw_rect(Rect2(0.0, 0.0, BASE_SIZE.x, BASE_SIZE.y), Color(0.03, 0.02, 0.08, 0.82), true)
    _panel(Rect2(222.0, 96.0, 836.0, 540.0), PANEL, Color(0.46, 0.30, 0.72, 0.95), 24.0)
    draw_string(display_font, Vector2(276.0, 160.0), "遊び方", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 40, INK)
    draw_string(ui_font, Vector2(278.0, 193.0), "流れてくるノーツが判定ラインに重なる瞬間に叩きます。", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, MUTED)
    _help_key(Vector2(282.0, 250.0), "たたく", "F / J / G / H / Space のどれでもOK", PINK)
    _help_key(Vector2(282.0, 315.0), "タイミング", "判定ラインに重なったら1回だけ入力", YELLOW)
    _help_key(Vector2(282.0, 380.0), "タッチ", "画面下の太鼓をタップ / クリック", CYAN)
    draw_string(ui_bold, Vector2(704.0, 250.0), "対応するTJAコマンド", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, CYAN)
    var commands := ["TITLE / SUBTITLE", "BPM / OFFSET / WAVE", "COURSE / LEVEL", "#START / #END", "#BPMCHANGE / #MEASURE", "#SCROLL / #DELAY", "#GOGOSTART / #GOGOEND", "#BARLINEOFF / #BRANCH"]
    for i in range(commands.size()):
        draw_string(ui_font, Vector2(704.0, 286.0 + float(i) * 29.0), "·  " + commands[i], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, INK if i < 4 else MUTED)
    draw_string(ui_font, Vector2(282.0, 482.0), "TJAの1 / 2 / 3 / 4は、すべて同じ太鼓入力で判定", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, INK)
    draw_string(ui_font, Vector2(282.0, 516.0), "良・可・不可の判定、コンボ、スコア、魂ゲージで腕前を記録。", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, MUTED)
    help_close_rect = Rect2(282.0, 555.0, 716.0, 50.0)
    _button(help_close_rect, help_close_rect, "わかった", CYAN, true)

func _panel(rect: Rect2, fill: Color, border: Color, radius: float) -> void:
    draw_style_box(_rounded_style(fill, border, 1.0, radius), rect)

func _rounded_style(fill: Color, border: Color, width: float, radius: float) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = fill
    style.border_color = border
    style.set_border_width_all(int(width))
    style.set_corner_radius_all(int(radius))
    return style

func _button(out_rect: Rect2, rect: Rect2, text: String, accent: Color, primary: bool) -> void:
    out_rect = rect
    var fill := Color(accent, 0.20 if primary else 0.06)
    var border := Color(accent, 0.95 if primary else 0.55)
    _panel(rect, fill, border, 12.0)
    draw_string(ui_bold, Vector2(rect.position.x, rect.position.y + rect.size.y * 0.62), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 16, INK if primary else accent)

func _guide_row(pos: Vector2, label: String, value: String, color: Color) -> void:
    draw_circle(pos + Vector2(6.0, -5.0), 6.0, color)
    draw_string(ui_bold, pos + Vector2(24.0, 0.0), label, HORIZONTAL_ALIGNMENT_LEFT, 90.0, 15, color)
    draw_string(ui_font, pos + Vector2(128.0, 0.0), value, HORIZONTAL_ALIGNMENT_LEFT, 250.0, 14, MUTED)

func _touch_pad(rect: Rect2, label: String, color: Color, hint: String) -> void:
    var active := drum_flash > 0.12 and ((label == "ドン" and last_judgment in ["良", "可"]) or (label == "カッ" and last_judgment in ["良", "可"]))
    _panel(rect, Color(color, 0.18 if active else 0.08), Color(color, 0.94 if active else 0.58), 18.0)
    draw_circle(Vector2(rect.position.x + 40.0, rect.position.y + rect.size.y * 0.5), 24.0, Color(color, 0.22))
    draw_circle(Vector2(rect.position.x + 40.0, rect.position.y + rect.size.y * 0.5), 15.0, color)
    draw_string(ui_bold, Vector2(rect.position.x + 80.0, rect.position.y + 44.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 23, INK)
    draw_string(ui_font, Vector2(rect.position.x + 80.0, rect.position.y + 72.0), "タップ / クリック   " + hint, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, MUTED)

func _result_metric(pos: Vector2, label: String, value: String, color: Color) -> void:
    draw_string(ui_font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, 180.0, 13, MUTED)
    draw_string(ui_bold, pos + Vector2(210.0, 0.0), value, HORIZONTAL_ALIGNMENT_LEFT, 280.0, 22, color)

func _help_key(pos: Vector2, label: String, value: String, color: Color) -> void:
    draw_circle(pos + Vector2(18.0, 1.0), 18.0, Color(color, 0.18))
    draw_circle(pos + Vector2(18.0, 1.0), 9.0, color)
    draw_string(ui_bold, pos + Vector2(52.0, 7.0), label, HORIZONTAL_ALIGNMENT_LEFT, 130.0, 18, INK)
    draw_string(ui_font, pos + Vector2(188.0, 7.0), value, HORIZONTAL_ALIGNMENT_LEFT, 340.0, 15, MUTED)

func _format_score(value: int) -> String:
    var raw := str(value)
    while raw.length() < 7:
        raw = "0" + raw
    return raw

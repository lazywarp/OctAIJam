extends Node
## Player settings: music and sound-effect volume, fullscreen. Loaded and applied at startup,
## saved to user://settings.cfg on every change. Also runs the Settings screen's input
## (main.gd calls update() while state is "settings"; hud.gd draws it).

const SynthScript := preload("res://scripts/synth.gd")

const PATH := "user://settings.cfg" # [audio] music, sfx (0..100 %); [display] fullscreen
const STEP := 10 # % per Left/Right press
const ITEMS := ["music", "sfx", "fullscreen", "back"]
const LABELS := {"music": "Music volume", "sfx": "Sound effects volume", "fullscreen": "Fullscreen", "back": "Back"}
const BLIP_HZ := 1568.0 # G6: the SFX level preview

var main
var music := 100
var sfx := 100
var fullscreen := false
var index := 0 # highlighted item
var value_flash := 0.0 # 1 -> 0, HUD pop when a value changes

var _hold := 0.0 # auto-repeat countdown, shared by up/down and left/right


func _ready() -> void:
	SynthScript.ensure_buses()
	load_settings()
	apply_all()


func _process(delta: float) -> void:
	value_flash = maxf(value_flash - delta * 4.0, 0.0)


# Esc or gamepad B leaves the screen. Handled here, before main.gd's _input sees the event,
# so Esc on this screen never quits.
func _input(event: InputEvent) -> void:
	if main == null or main.state != "settings":
		return
	var esc: bool = event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE
	var b: bool = event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B
	if esc or b:
		get_viewport().set_input_as_handled()
		back()


# --- Screen -----------------------------------------------------------------

## The Settings screen's per-frame input: up/down moves (like the main menu, with the same
## repeat timing), left/right steps a volume, select toggles fullscreen or goes back.
func update(delta: float) -> void:
	var v := _repeat_dir("menu_up", "menu_down", delta)
	if v != 0:
		_move(v)
	var h := _repeat_dir("move_left", "move_right", delta)
	if h != 0:
		adjust(ITEMS[index], h)
	if Input.is_action_just_pressed("menu_select"):
		choose(index)


# -1 / +1 on a fresh press of `neg` / `pos`, then auto-repeat while one of them is held.
func _repeat_dir(neg: String, pos: String, delta: float) -> int:
	if Input.is_action_just_pressed(neg):
		_hold = main.MENU_REPEAT_DELAY
		return -1
	if Input.is_action_just_pressed(pos):
		_hold = main.MENU_REPEAT_DELAY
		return 1
	if Input.is_action_pressed(neg) != Input.is_action_pressed(pos):
		_hold -= delta
		if _hold <= 0.0:
			_hold = main.MENU_REPEAT_RATE
			return -1 if Input.is_action_pressed(neg) else 1
	return 0


func _move(dir: int) -> void:
	index = posmod(index + dir, ITEMS.size())
	main.menu_flash = 1.0
	main.synth.play("blip", 2093.0, -12.0) # C7, the main menu's blip


## Left/right on an item: a volume steps by STEP; fullscreen flips either way.
func adjust(item: String, dir: int) -> void:
	match item:
		"music":
			set_music(music + STEP * dir)
		"sfx":
			set_sfx(sfx + STEP * dir)
		"fullscreen":
			set_fullscreen(not fullscreen)


## Space / Enter on an item.
func choose(i: int) -> void:
	index = i
	match ITEMS[i]:
		"fullscreen":
			set_fullscreen(not fullscreen)
		"back":
			back()


func back() -> void:
	main.synth.play("chime", 784.0, -12.0) # G5, a step down from the menu's select chime
	index = 0
	main._to_menu()


# --- Values -----------------------------------------------------------------

func set_music(percent: int) -> void:
	var v := clampi(percent, 0, 100)
	if v == music:
		return
	music = v
	value_flash = 1.0
	_apply_volume(SynthScript.MUSIC_BUS, music)
	save_settings()


## Plays a blip on the SFX bus at the new level, so the player hears it.
func set_sfx(percent: int) -> void:
	var v := clampi(percent, 0, 100)
	if v == sfx:
		return
	sfx = v
	value_flash = 1.0
	_apply_volume(SynthScript.SFX_BUS, sfx)
	save_settings()
	if main:
		main.synth.play("blip", BLIP_HZ, -8.0)


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	value_flash = 1.0
	_apply_fullscreen()
	save_settings()


## F11, anywhere.
func toggle_fullscreen() -> void:
	set_fullscreen(not fullscreen)


func apply_all() -> void:
	_apply_volume(SynthScript.MUSIC_BUS, music)
	_apply_volume(SynthScript.SFX_BUS, sfx)
	_apply_fullscreen()


# Percent to decibels on a squared curve, so each step sounds about as big as the last
# (50% = -12 dB, 10% = -40 dB). 0% mutes the bus.
static func percent_to_db(percent: int) -> float:
	var k := clampi(percent, 0, 100) / 100.0
	return -80.0 if k <= 0.0 else linear_to_db(k * k)


func _apply_volume(bus_name: String, percent: int) -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	if bus < 0:
		return
	AudioServer.set_bus_volume_db(bus, percent_to_db(percent))
	AudioServer.set_bus_mute(bus, percent <= 0)


func _apply_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return # no window to change
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


# --- File -------------------------------------------------------------------

## Loads the saved values. A missing, corrupt or out-of-range file falls back to the
## defaults (100%, 100%, windowed) quietly: the text is checked before ConfigFile parses
## it, because ConfigFile prints an engine error on a syntax error.
func load_settings() -> void:
	music = 100
	sfx = 100
	fullscreen = false
	if not FileAccess.file_exists(PATH):
		return
	var text := FileAccess.get_file_as_string(PATH)
	var cfg := ConfigFile.new()
	if not _looks_valid(text) or cfg.parse(text) != OK:
		return
	music = _read_percent(cfg, "audio", "music")
	sfx = _read_percent(cfg, "audio", "sfx")
	var fs: Variant = cfg.get_value("display", "fullscreen", false)
	fullscreen = fs is bool and fs


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", music)
	cfg.set_value("audio", "sfx", sfx)
	cfg.set_value("display", "fullscreen", fullscreen)
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("Could not save settings: %s" % error_string(err))


func _read_percent(cfg: ConfigFile, section: String, key: String) -> int:
	var v: Variant = cfg.get_value(section, key, 100)
	if not (v is int or v is float):
		return 100
	return clampi(snappedi(roundi(float(v)), STEP), 0, 100)


# Only what this file ever holds: blank lines, ; comments, [section] headers and
# key=value lines whose value is a number or true/false.
static func _looks_valid(text: String) -> bool:
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with(";"):
			continue
		if line.begins_with("[") and line.ends_with("]") and line.length() > 2:
			continue
		var eq := line.find("=")
		if eq <= 0:
			return false
		var value := line.substr(eq + 1).strip_edges()
		if not (value.is_valid_float() or value == "true" or value == "false"):
			return false
	return true

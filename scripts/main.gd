extends Node2D
## Game controller: beat clock, stillness timer, level loading, camera, audio cues.

const PlayerScript := preload("res://scripts/player.gd")
const PlatformScript := preload("res://scripts/platform.gd")
const HazardScript := preload("res://scripts/hazard.gd")
const HeatLampScript := preload("res://scripts/heat_lamp.gd")
const PendulumScript := preload("res://scripts/pendulum.gd")
const GoalScript := preload("res://scripts/goal.gd")
const SignScript := preload("res://scripts/sign.gd")
const ScoreNoteScript := preload("res://scripts/score_note.gd")
const PowerupScript := preload("res://scripts/powerup.gd")
const Powerups := preload("res://scripts/powerups.gd")
const SynthScript := preload("res://scripts/synth.gd")
const BackgroundScript := preload("res://scripts/background.gd")
const HudScript := preload("res://scripts/hud.gd")
const Levels := preload("res://scripts/levels.gd")
const CustomLevels := preload("res://scripts/custom_levels.gd")

const DEFAULT_BPM := 100.0
const TEMPO_RAMP_BEATS := 4.0 # a tempo zone eases to its new bpm over one bar
const IDLE_LIMIT := 2.0
const DRIP_START := 1.0 # stillness (s) before warning drips begin
const LAMP_HEAT := 2.0 # stillness fills this many times faster under a heat lamp
const DEFAULT_SWITCH_BEATS := 2
const SWITCH_GRACE := 0.7 # from this switch_phase on, the incoming beat group is already solid
const RESTART_MELT := 0.7 # auto-restart delay after melting from stillness
const RESTART_FAST := 0.5 # auto-restart delay after a sizzle or a fall
const SKIP_LOCKOUT := 0.2 # a fresh press after this long into dying restarts immediately
const ROOT_HZ := 523.25 # C5
const BASS_HZ := 130.81 # C3
const PAD_DB := -18.0 # per pad tone; three play at once, well under ticks and jump notes
const BEST_PATH := "user://best_times.cfg" # section "best", key = level index
# I - vi - IV - V, as semitones above the root.
const CHORDS := [[0, 4, 7], [9, 12, 16], [5, 9, 12], [7, 11, 14]]
const PLAY_STATES := ["play", "dying", "win"] # a level is running; every other state is a menu screen
const MENU_REPEAT_DELAY := 0.4 # holding up/down: first repeat after this long...
const MENU_REPEAT_RATE := 0.14 # ...then one step this often
# Main menu, top to bottom. "action" is "play", "quit", or the state of the screen the item
# opens. "soon" marks screens not built yet (M2 Free Play, L3 Custom Levels, M3 Settings):
# to plug one in, drop its "soon", then handle its state in _process (input) and hud.gd (drawing),
# and call _to_menu() to come back.
const MENU := [
	{"label": "Play", "action": "play"},
	{"label": "Free Play", "action": "free_play", "soon": true},
	{"label": "Custom Levels", "action": "custom_levels", "soon": true},
	{"label": "Settings", "action": "settings", "soon": true},
	{"label": "Quit", "action": "quit"},
]

## A score note was collected: its points, and the attempt's new note_points total.
signal note_collected(points: int, total: int)

var beat := 0
var beat_phase := 0.0 # 0..1 progress through the current beat
var switch_phase := 0.0 # 0..1 progress until beat platforms flip
var switch_beats := DEFAULT_SWITCH_BEATS
var bpm := DEFAULT_BPM
var tempo_flash := 0.0 # 1 -> 0, HUD highlight after a tempo change
var idle := 0.0
var deaths := 0
var powers: Array[Dictionary] = [] # active power-ups in pickup order: {kind, time_left, duration, charges}
var level_index := 0
var level: Dictionary = {}
var state := "menu" # menu, play, dying, win, end (and later one per menu screen)
var message := ""
var message_t := 0.0
var level_time := 0.0 # current attempt at this level; resets on death
var run_times: Array[float] = [] # this run's clear time per level, -1 if not cleared
var run_new_best: Array[bool] = [] # whether that clear set a new best
var best_times: Dictionary = {} # level index -> best clear time, persisted
var menu_index := 0 # highlighted main menu item
var menu_flash := 0.0 # 1 -> 0, HUD pop when the highlight moves or an item is chosen
var note_points := 0 # score-note points this attempt; reset on every level (re)load
var notes_collected := 0
var notes_total := 0 # score notes placed in the current level
var custom_source := "" # file of the custom level being played; "" for the built-in levels
## Called after a custom level is cleared (L3 can point it at its own screen); invalid = _to_menu().
var custom_return := Callable()

var camera: Camera2D
var world: Node2D
var player: PlayerScript
var synth: SynthScript

var _beat_clock := 0.0 # progress through the current beat, in beats (0..1)
var _bpm_from := DEFAULT_BPM
var _bpm_to := DEFAULT_BPM
var _ramp := 1.0 # 0..1 progress of the current tempo ramp
var _tempo_i := 0 # next untriggered tempo zone (zones are sorted by x)
var _tempo_zones: Array = []
var _state_t := 0.0
var _dying_t := 0.0 # time since death, for the skip lockout
var _melody_i := 0
var _pressed_this_frame := false
var _quitting := false
var _drip_t := 0.0 # countdown to the next stillness warning drip
var _goal: GoalScript
var _lamps: Array[Node] = [] # heat lamps the current player is standing in
var _menu_hold := 0.0 # countdown to the next auto-repeat step while up/down is held


func _ready() -> void:
	randomize()
	get_tree().auto_accept_quit = false # the window close button goes through _quit()
	_setup_input()
	_load_bests()
	RenderingServer.set_default_clear_color(Color("17122b"))

	synth = SynthScript.new()
	add_child(synth)
	var pad_hz: Array[float] = []
	for chord: Array in CHORDS:
		for semis: int in chord:
			var hz := _pad_hz(semis)
			if not pad_hz.has(hz):
				pad_hz.append(hz)
	synth.prerender("pad", pad_hz)

	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)
	var bg := BackgroundScript.new()
	bg.main = self
	bg_layer.add_child(bg)

	camera = Camera2D.new()
	camera.position = Vector2(640, 360)
	add_child(camera)
	camera.make_current()

	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)
	var hud := HudScript.new()
	hud.main = self
	hud_layer.add_child(hud)

	# For testing: `godot --path . -- --level 5` skips the menu and starts at that level.
	var args := OS.get_cmdline_user_args()
	var at := args.find("--level")
	if at >= 0 and at + 1 < args.size():
		_start_game()
		_load_level(clampi(args[at + 1].to_int() - 1, 0, level_count() - 1), true)
	CustomLevels.seed_if_empty()
	# For testing custom levels: `godot --path . -- --custom my_level.json` (a file name in
	# user://levels/, or a full path) plays that file; errors are printed, then the menu shows.
	at = args.find("--custom")
	if at >= 0:
		_play_custom_arg(args[at + 1] if at + 1 < args.size() else "")


func _setup_input() -> void:
	_add_action("move_left", [KEY_LEFT, KEY_A], [JOY_BUTTON_DPAD_LEFT], -1.0)
	_add_action("move_right", [KEY_RIGHT, KEY_D], [JOY_BUTTON_DPAD_RIGHT], 1.0)
	_add_action("jump", [KEY_SPACE, KEY_UP, KEY_W, KEY_Z], [JOY_BUTTON_A], 0.0)
	# Menus. The stick needs a firm push (0.5) so a resting stick can't flicker the highlight.
	_add_action("menu_up", [KEY_UP, KEY_W], [JOY_BUTTON_DPAD_UP], -1.0, JOY_AXIS_LEFT_Y, 0.5)
	_add_action("menu_down", [KEY_DOWN, KEY_S], [JOY_BUTTON_DPAD_DOWN], 1.0, JOY_AXIS_LEFT_Y, 0.5)
	_add_action("menu_select", [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER], [JOY_BUTTON_A], 0.0)


func _add_action(action: String, keys: Array, buttons: Array, stick_dir: float,
		axis := JOY_AXIS_LEFT_X, deadzone := 0.4) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, deadzone)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for b in buttons:
		var j := InputEventJoypadButton.new()
		j.button_index = b
		InputMap.action_add_event(action, j)
	if stick_dir != 0.0:
		var m := InputEventJoypadMotion.new()
		m.axis = axis
		m.axis_value = stick_dir
		InputMap.action_add_event(action, m)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_quit()
		elif event.keycode == KEY_F11:
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif event.keycode == KEY_M:
			_toggle_mute()
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_BACK:
		_toggle_mute()
	if (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton) and event.is_pressed():
		_pressed_this_frame = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		_pressed_this_frame = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()


# Stop all sound and give the mixer a moment to release it, so nothing leaks at exit.
func _quit() -> void:
	if _quitting:
		return
	_quitting = true
	synth.stop_all()
	await get_tree().create_timer(0.15).timeout
	get_tree().quit()


func _toggle_mute() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(bus, not AudioServer.is_bus_mute(bus))


func _process(delta: float) -> void:
	_update_beat(delta)
	message_t = maxf(message_t - delta, 0.0)
	tempo_flash = maxf(tempo_flash - delta, 0.0)
	menu_flash = maxf(menu_flash - delta * 4.0, 0.0)

	match state:
		"menu":
			_update_menu(delta)
		"play":
			level_time += delta
			if _input_active():
				idle = 0.0
			else:
				idle += delta * heat()
			player.melt = melt_ratio()
			player.heated = under_lamp()
			_update_tempo_zones()
			_update_drips(delta)
			_update_powers(delta)
			if idle >= IDLE_LIMIT and not _powers_cancel_melt():
				die("You stood still. You melted.")
			elif player.position.y > float(level.get("kill_y", 900.0)):
				die("You fell out of tune.")
		"dying", "win":
			_state_t -= delta
			if state == "dying":
				_dying_t += delta
				if _dying_t >= SKIP_LOCKOUT and _skip_pressed():
					_state_t = 0.0
			if _state_t <= 0.0:
				if state == "dying":
					if is_custom():
						_build_level(level, false)
					else:
						_load_level(level_index, false)
				elif is_custom():
					_finish_custom()
				elif level_index + 1 < Levels.all().size():
					_load_level(level_index + 1, true)
				else:
					state = "end"
					_state_t = 1.0
		"end":
			_state_t -= delta
			if _state_t <= 0.0 and Input.is_action_just_pressed("jump"):
				_to_menu()

	_update_camera(delta)
	_pressed_this_frame = false


# Warning drips while standing still: faster and slightly higher as the melt nears.
func _update_drips(delta: float) -> void:
	if idle < DRIP_START or idle >= IDLE_LIMIT:
		_drip_t = 0.0
		return
	_drip_t -= delta
	if _drip_t <= 0.0:
		var u := clampf((idle - DRIP_START) / (IDLE_LIMIT - DRIP_START), 0.0, 1.0)
		_drip_t = lerpf(0.35, 0.08, u)
		synth.play("drip", lerpf(900.0, 1300.0, u), -10.0)


func _input_active() -> bool:
	return _pressed_this_frame \
		or Input.is_action_pressed("move_left") \
		or Input.is_action_pressed("move_right") \
		or Input.is_action_pressed("jump")


func _skip_pressed() -> bool:
	return Input.is_action_just_pressed("jump") \
		or Input.is_action_just_pressed("move_left") \
		or Input.is_action_just_pressed("move_right")


func level_count() -> int:
	return Levels.all().size()


## Stillness speed multiplier: LAMP_HEAT under any heat lamp (overlaps don't stack).
func heat() -> float:
	return LAMP_HEAT if under_lamp() else 1.0


func under_lamp() -> bool:
	return not _lamps.is_empty()


# Lamps report the player entering and leaving. Only lamps in the current world
# count, and only for the current player, so signals from a level being freed
# can't leave the heat stuck on.
func lamp_entered(lamp: Node, body: Node) -> void:
	if body == player and lamp.get_parent() == world and not _lamps.has(lamp):
		_lamps.append(lamp)


func lamp_exited(lamp: Node) -> void:
	_lamps.erase(lamp)


func melt_ratio() -> float:
	return clampf(idle / IDLE_LIMIT, 0.0, 1.0)


## True while this group's bar is playing (ignores the grace overlap).
func beat_group_on(group: int) -> bool:
	return floori(float(beat) / switch_beats) % 2 == group


## True while the group is solid: its own bar, plus the incoming grace window.
func beat_group_active(group: int) -> bool:
	return beat_group_on(group) or switch_phase >= SWITCH_GRACE


## The metronome swing, -1..1, at an extreme on every tick. The background arm and
## pendulum platforms both read it, so they can never drift apart.
## beats_per_side > 1 slows the swing: 2 means one extreme every other tick.
func swing(offset := 0.0, beats_per_side := 1.0) -> float:
	return cos(PI * (beat + beat_phase + offset) / beats_per_side)


# --- Beat & music -----------------------------------------------------------

# The clock counts in beats, so changing bpm only changes its speed: beat and
# beat_phase stay continuous.
func _update_beat(delta: float) -> void:
	if _ramp < 1.0:
		_ramp = minf(_ramp + delta * bpm / 60.0 / TEMPO_RAMP_BEATS, 1.0)
		bpm = lerpf(_bpm_from, _bpm_to, smoothstep(0.0, 1.0, _ramp))
		tempo_flash = 1.0
	_beat_clock += delta * bpm / 60.0
	while _beat_clock >= 1.0:
		_beat_clock -= 1.0
		beat += 1
		_on_beat()
	beat_phase = _beat_clock
	switch_phase = (float(beat % switch_beats) + beat_phase) / switch_beats


## Jump straight to a tempo (level start); no ramp.
func set_bpm(value: float) -> void:
	if not is_equal_approx(value, bpm):
		tempo_flash = 1.0
	bpm = value
	_bpm_from = value
	_bpm_to = value
	_ramp = 1.0


## Ease from the current tempo to `value` over one bar.
func ramp_bpm(value: float) -> void:
	_bpm_from = bpm
	_bpm_to = value
	_ramp = 0.0


func _apply_level_tempo() -> void:
	set_bpm(float(level.get("bpm", DEFAULT_BPM)))
	_tempo_zones = level.get("tempo", []).duplicate()
	_tempo_zones.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) < float(q[0]))
	_tempo_i = 0


func _update_tempo_zones() -> void:
	while _tempo_i < _tempo_zones.size() and player.position.x > float(_tempo_zones[_tempo_i][0]):
		ramp_bpm(float(_tempo_zones[_tempo_i][1]))
		_tempo_i += 1


func _on_beat() -> void:
	var downbeat := beat % 4 == 0
	synth.play("tick", 1760.0 if downbeat else 1320.0, -8.0 if downbeat else -14.0)
	if downbeat:
		var root: int = CHORDS[_bar() % 4][0]
		synth.play("bass", BASS_HZ * pow(2.0, root / 12.0), -6.0)
		for semis: int in CHORDS[_bar() % 4]:
			synth.play("pad", _pad_hz(semis), PAD_DB)


## Pad voicing: chord tones folded into G3..F#4 around middle C, for smooth voice leading.
func _pad_hz(semis: int) -> float:
	return ROOT_HZ * 0.5 * pow(2.0, (posmod(semis + 5, 12) - 5) / 12.0)


func _bar() -> int:
	return floori(beat / 4.0)


func _chord_hz(index: int) -> float:
	var chord: Array = CHORDS[_bar() % 4]
	var semis: int = chord[index % 3] + 12 * (floori(index / 3.0) % 2)
	return ROOT_HZ * pow(2.0, semis / 12.0)


func _on_jump() -> void:
	synth.play("note", _chord_hz(_melody_i), -6.0)
	_melody_i += 1


func _on_land() -> void:
	synth.play("thud", 110.0, -10.0)


# --- Menu -------------------------------------------------------------------

## True while a level is running (play, dying, win); false on the menu screens and the end screen.
func is_playing() -> bool:
	return PLAY_STATES.has(state)


# Up/down moves the highlight (wrapping, auto-repeating while held); select runs it.
func _update_menu(delta: float) -> void:
	var dir := 0
	if Input.is_action_just_pressed("menu_up"):
		dir = -1
		_menu_hold = MENU_REPEAT_DELAY
	elif Input.is_action_just_pressed("menu_down"):
		dir = 1
		_menu_hold = MENU_REPEAT_DELAY
	elif Input.is_action_pressed("menu_up") != Input.is_action_pressed("menu_down"):
		_menu_hold -= delta
		if _menu_hold <= 0.0:
			_menu_hold = MENU_REPEAT_RATE
			dir = -1 if Input.is_action_pressed("menu_up") else 1
	if dir != 0:
		menu_move(dir)
	if Input.is_action_just_pressed("menu_select"):
		menu_select(menu_index)


## Step the highlight by `dir`, wrapping around the ends.
func menu_move(dir: int) -> void:
	menu_highlight(posmod(menu_index + dir, MENU.size()))


## Highlight an item directly (the HUD calls this on mouse hover).
func menu_highlight(i: int) -> void:
	if i == menu_index:
		return
	menu_index = i
	menu_flash = 1.0
	synth.play("tick", 2093.0, -12.0) # C7 blip


func menu_select(i: int) -> void:
	if state != "menu":
		return
	menu_index = i
	var item: Dictionary = MENU[i]
	var action: String = item["action"]
	if item.get("soon", false):
		synth.play("thud", 196.0, -8.0)
		_show("%s: coming soon" % item["label"], 1.4)
		return
	menu_flash = 1.0
	synth.play("chime", 1046.5, -10.0) # C6
	match action:
		"play":
			_start_game()
		"quit":
			_quit()
		_:
			_open_screen(action)


# Switch to a menu screen; its state name is its MENU action.
func _open_screen(screen: String) -> void:
	state = screen
	_state_t = 0.0
	message_t = 0.0


# Back to the main menu: clear away the level so the menu shows over the empty concert hall.
func _to_menu() -> void:
	state = "menu"
	message_t = 0.0
	if world:
		world.queue_free()
		world = null
	player = null
	_goal = null
	_lamps.clear()
	level = {}
	idle = 0.0
	set_bpm(DEFAULT_BPM)
	_tempo_zones = []
	camera.limit_bottom = 10000000
	camera.position = Vector2(640, 360)
	camera.reset_smoothing()


# --- Flow -------------------------------------------------------------------

func _start_game() -> void:
	deaths = 0
	run_times.clear()
	run_new_best.clear()
	for i in level_count():
		run_times.append(-1.0)
		run_new_best.append(false)
	_load_level(0, true)


func _load_level(i: int, announce: bool) -> void:
	level_index = i
	custom_source = ""
	_build_level(Levels.all()[i], announce)


# Builds `data` (a levels.gd-style Dictionary) as the current level and starts playing it.
func _build_level(data: Dictionary, announce: bool) -> void:
	level = data
	clear_powers() # before the tempo reset, so an expiring effect can't undo it
	switch_beats = int(level.get("switch_beats", DEFAULT_SWITCH_BEATS))
	_apply_level_tempo()
	if world:
		world.queue_free()
	world = Node2D.new()
	add_child(world)

	for r in level.get("solid", []):
		_add_platform(PlatformScript.Kind.SOLID, r)
	for r in level.get("a", []):
		_add_platform(PlatformScript.Kind.BEAT_A, r)
	for r in level.get("b", []):
		_add_platform(PlatformScript.Kind.BEAT_B, r)
	for pd in level.get("pend", []):
		var pn := PendulumScript.new()
		pn.setup(self, pd[0], pd[1], pd[2], pd[3], float(pd[4]) if pd.size() > 4 else 1.0)
		world.add_child(pn)
	for r in level.get("lamp", []):
		var lp := HeatLampScript.new()
		lp.setup(self, r)
		world.add_child(lp)
	for r in level.get("hot", []):
		var hz := HazardScript.new()
		hz.setup(self, r)
		world.add_child(hz)
	_spawn_powerups(level)
	note_points = 0
	notes_collected = 0
	notes_total = 0
	for nd in level.get("notes", []):
		add_note(nd[0], str(nd[1]))
	for s in level.get("signs", []):
		var sg := SignScript.new()
		sg.position = s[0]
		sg.text = s[1]
		world.add_child(sg)

	_goal = GoalScript.new()
	_goal.main = self
	_goal.position = level["goal"]
	world.add_child(_goal)

	player = PlayerScript.new()
	player.position = level["spawn"]
	world.add_child(player)
	player.jumped.connect(_on_jump)
	player.landed.connect(_on_land)

	idle = 0.0
	_lamps.clear()
	level_time = 0.0
	state = "play"
	camera.limit_bottom = int(level.get("cam_bottom", 800))
	camera.position = player.position + Vector2(0, -40)
	camera.reset_smoothing()
	if announce:
		_show(level["name"], 2.0)


func _add_platform(kind: int, rect: Rect2) -> void:
	var p := PlatformScript.new()
	p.setup(self, kind, rect)
	world.add_child(p)


# Pickups from the level's "power" entries, plus "snow" as the old refreezer shorthand.
func _spawn_powerups(data: Dictionary) -> void:
	for p in data.get("snow", []):
		_add_powerup(p, "refreeze")
	for pw in data.get("power", []):
		_add_powerup(pw[0], str(pw[1]))


func _add_powerup(pos: Vector2, kind: String) -> void:
	if not Powerups.has(kind):
		push_warning("%s: unknown power-up kind \"%s\" at %s, skipped" % [level.get("name", "?"), kind, pos])
		return
	var pu := PowerupScript.new()
	pu.setup(self, pos, kind)
	world.add_child(pu)


# --- Power-ups --------------------------------------------------------------
# Kinds live in powerups.gd. Effects are tracked here; they tick only while playing
# and are all cleared on every level (re)load.

## A pickup touched the cube. Returns false (and the pickup stays) if the kind is at its
## max charges and doesn't refresh. Otherwise starts it, adds a charge or restarts its timer.
func collect_power(kind: String) -> bool:
	if state != "play" or not Powerups.has(kind):
		return false
	var d := Powerups.def(kind)
	var fx := get_power(kind)
	if fx.is_empty():
		var dur := Powerups.duration(kind)
		fx = {"kind": kind, "duration": dur, "time_left": dur, "charges": 1}
		powers.append(fx)
		_power_hook(kind, "on_activate", [self, fx])
		return true
	if int(fx["charges"]) < int(d.get("max", 1)):
		fx["charges"] = int(fx["charges"]) + 1
	elif not bool(d.get("refresh", true)):
		return false
	fx["time_left"] = fx["duration"]
	return true


## Places a score note in the current world. Unknown types are skipped with a warning.
func add_note(pos: Vector2, type: String) -> bool:
	if not ScoreNoteScript.POINTS.has(type):
		push_warning("Unknown score note type \"%s\" at %s; skipped" % [type, pos])
		return false
	var sn := ScoreNoteScript.new()
	sn.setup(self, pos, type)
	world.add_child(sn)
	notes_total += 1
	return true


## A score note touched the cube: add its points and chime chord tones (higher value =
## higher and more notes). Returns false outside play, so the note stays put.
func collect_note(type: String) -> bool:
	if state != "play":
		return false
	var points: int = ScoreNoteScript.POINTS[type]
	note_points += points
	notes_collected += 1
	# Chord-tone indices (see _chord_hz): eighths walk the lower octave, quarters the upper,
	# a half rises a two-note step and a whole plays a three-note arpeggio.
	var tones: Array = {"eighth": [notes_collected % 3], "quarter": [3 + notes_collected % 3],
		"half": [2, 4], "whole": [3, 4, 5]}[type]
	for k in tones.size():
		var hz := _chord_hz(tones[k])
		if k == 0:
			synth.play("pling", hz, -9.0)
		else:
			get_tree().create_timer(k * 0.07).timeout.connect(synth.play.bind("pling", hz, -9.0))
	note_collected.emit(points, note_points)
	return true


## The active effect of this kind, or {} if none.
func get_power(kind: String) -> Dictionary:
	for fx in powers:
		if fx["kind"] == kind:
			return fx
	return {}


func has_power(kind: String) -> bool:
	return not get_power(kind).is_empty()


## Spends one charge (e.g. an extra jump); the last one ends the effect.
func use_power(kind: String) -> void:
	var fx := get_power(kind)
	if fx.is_empty():
		return
	fx["charges"] = int(fx["charges"]) - 1
	if int(fx["charges"]) <= 0:
		_end_power(fx, "used")


## 0..1 time left, for the HUD timer bar; 1 for "until used" kinds.
func power_ratio(fx: Dictionary) -> float:
	var dur: float = fx["duration"]
	return 1.0 if dur <= 0.0 else clampf(float(fx["time_left"]) / dur, 0.0, 1.0)


func clear_powers() -> void:
	for fx in powers.duplicate():
		_end_power(fx, "cleared")


func _update_powers(delta: float) -> void:
	for fx in powers.duplicate():
		if not powers.has(fx):
			continue # ended by an earlier effect's hook this frame
		_power_hook(fx["kind"], "on_tick", [self, fx, delta])
		if float(fx["duration"]) > 0.0:
			fx["time_left"] = float(fx["time_left"]) - delta
			if float(fx["time_left"]) <= 0.0:
				_end_power(fx, "timeout")


# Stillness ran out: the first effect whose on_melt hook saves the cube spends a charge.
func _powers_cancel_melt() -> bool:
	for fx in powers.duplicate():
		var saved: Variant = _power_hook(fx["kind"], "on_melt", [self, fx])
		if saved is bool and saved:
			use_power(fx["kind"])
			return true
	return false


func _end_power(fx: Dictionary, reason: String) -> void:
	if not powers.has(fx):
		return
	powers.erase(fx)
	_power_hook(fx["kind"], "on_expire", [self, fx, reason])


func _power_hook(kind: String, hook: String, args: Array) -> Variant:
	var cb: Callable = Powerups.def(kind).get(hook, Callable())
	return cb.callv(args) if cb.is_valid() else null


## The refreezer's effect: the cube refreezes instead of melting from stillness.
## Only stillness: hazards and falls still kill.
func refreeze() -> void:
	idle = 0.0
	_drip_t = 0.0
	player.melt = 0.0
	player.refreeze()
	synth.play("refreeze", 1046.5, -10.0) # C6
	_show("Refrozen!", 1.0)


func die(reason: String, hot := false) -> void:
	if state != "play":
		return
	# Only a stillness melt gets the longer delay; sizzles and falls restart faster.
	var delay := RESTART_MELT if idle >= IDLE_LIMIT and not hot else RESTART_FAST
	state = "dying"
	_state_t = delay
	_dying_t = 0.0
	deaths += 1
	player.die(hot)
	synth.play("sizzle" if hot else "melt", 660.0, -4.0)
	_show(reason, delay)


func reach_goal() -> void:
	if state != "play":
		return
	state = "win"
	_state_t = 1.8
	player.win()
	_goal.celebrate()
	for k in 6:
		get_tree().create_timer(k * 0.09).timeout.connect(synth.play.bind("note", _chord_hz(k), -5.0))
	if is_custom():
		_show("Bravo! %s" % format_time(level_time), 1.8) # custom clears never touch best times
	else:
		_show("Bravo! New best %s" % format_time(level_time) if _record_clear() else "Bravo!", 1.8)


# --- Custom levels ------------------------------------------------------------

## Plays a custom level (a validated in-game Dictionary, e.g. CustomLevels.load_file()'s
## "level"). Death reloads it; clearing it calls custom_return (default: the main menu).
## Built-in progress (run times, best times) is never touched.
func play_custom(data: Dictionary, source_path := "") -> void:
	custom_source = source_path if source_path != "" else "custom"
	deaths = 0
	_build_level(data, true)


## True while the current level is a custom one.
func is_custom() -> bool:
	return custom_source != ""


func _finish_custom() -> void:
	custom_source = ""
	if custom_return.is_valid():
		custom_return.call()
	else:
		_to_menu()


# --custom: resolve the argument, validate the file and play it, or print why not.
func _play_custom_arg(arg: String) -> void:
	var path := CustomLevels.resolve(arg)
	var entry: Dictionary = CustomLevels.load_file(path) if path != "" else {}
	if entry.is_empty() or not bool(entry["ok"]):
		var errors: Array = entry.get("errors", ["file not found (looked in %s)" % ProjectSettings.globalize_path(CustomLevels.dir_path())])
		print("Custom level \"%s\" not loaded:" % arg)
		for e in errors:
			print("  " + str(e))
		_show("Custom level not loaded (see the console)", 3.0)
		return
	for w in entry["warnings"]:
		print("%s: warning: %s" % [entry["file"], w])
	print("Playing custom level \"%s\" from %s" % [entry["name"], path if path.begins_with("res://") else ProjectSettings.globalize_path(path)])
	play_custom(entry["level"], path)


# Stores this run's clear time and updates the saved best. Returns true on a new best.
func _record_clear() -> bool:
	var i := level_index
	if i < run_times.size():
		run_times[i] = level_time
	var old: float = best_times.get(i, -1.0)
	if old >= 0.0 and level_time >= old:
		return false
	best_times[i] = level_time
	if i < run_new_best.size():
		run_new_best[i] = true
	_save_bests()
	return true


func _load_bests() -> void:
	best_times.clear()
	var cfg := ConfigFile.new()
	if cfg.load(BEST_PATH) != OK or not cfg.has_section("best"):
		return # missing or unreadable: start with no bests
	for key: String in cfg.get_section_keys("best"):
		var t: Variant = cfg.get_value("best", key, -1.0)
		if key.is_valid_int() and (t is float or t is int) and float(t) > 0.0:
			best_times[key.to_int()] = float(t)


func _save_bests() -> void:
	var cfg := ConfigFile.new()
	for i: int in best_times:
		cfg.set_value("best", str(i), best_times[i])
	var err := cfg.save(BEST_PATH)
	if err != OK:
		push_warning("Could not save best times: %s" % error_string(err))


func level_name(i: int) -> String:
	return str(Levels.all()[i].get("name", ""))


func best_time(i: int) -> float:
	return best_times.get(i, -1.0)


## Sum of this run's clear times (levels not cleared count as zero).
func run_total() -> float:
	var total := 0.0
	for t in run_times:
		total += maxf(t, 0.0)
	return total


## m:ss.t, e.g. 0:23.4. Negative means no time.
static func format_time(t: float) -> String:
	if t < 0.0:
		return "--"
	var tenths := floori(t * 10.0)
	return "%d:%02d.%d" % [floori(tenths / 600.0), floori(tenths / 10.0) % 60, tenths % 10]


func _show(text: String, duration: float) -> void:
	message = text
	message_t = duration


func _update_camera(delta: float) -> void:
	if not is_instance_valid(player): # menu screens have no level
		return
	var lead := clampf(player.velocity.x * 0.35, -180.0, 180.0)
	var target := player.position + Vector2(lead, -60.0)
	camera.position = camera.position.lerp(target, 1.0 - exp(-5.0 * delta))

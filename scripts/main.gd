extends Node2D
## Game controller: beat clock, stillness timer, level loading, camera, audio cues.

const PlayerScript := preload("res://scripts/player.gd")
const PlatformScript := preload("res://scripts/platform.gd")
const HazardScript := preload("res://scripts/hazard.gd")
const HeatLampScript := preload("res://scripts/heat_lamp.gd")
const PendulumScript := preload("res://scripts/pendulum.gd")
const GoalScript := preload("res://scripts/goal.gd")
const SignScript := preload("res://scripts/sign.gd")
const SnowflakeScript := preload("res://scripts/snowflake.gd")
const SynthScript := preload("res://scripts/synth.gd")
const BackgroundScript := preload("res://scripts/background.gd")
const HudScript := preload("res://scripts/hud.gd")
const Levels := preload("res://scripts/levels.gd")

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

var beat := 0
var beat_phase := 0.0 # 0..1 progress through the current beat
var switch_phase := 0.0 # 0..1 progress until beat platforms flip
var switch_beats := DEFAULT_SWITCH_BEATS
var bpm := DEFAULT_BPM
var tempo_flash := 0.0 # 1 -> 0, HUD highlight after a tempo change
var idle := 0.0
var deaths := 0
var has_snow := false # holding a refreezer: the next stillness melt is cancelled once
var level_index := 0
var level: Dictionary = {}
var state := "title" # title, play, dying, win, end
var message := ""
var message_t := 0.0
var level_time := 0.0 # current attempt at this level; resets on death
var run_times: Array[float] = [] # this run's clear time per level, -1 if not cleared
var run_new_best: Array[bool] = [] # whether that clear set a new best
var best_times: Dictionary = {} # level index -> best clear time, persisted

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

	# For testing: `godot --path . -- --level 5` skips the title and starts at that level.
	var args := OS.get_cmdline_user_args()
	var at := args.find("--level")
	if at >= 0 and at + 1 < args.size():
		_start_game()
		_load_level(clampi(args[at + 1].to_int() - 1, 0, level_count() - 1), true)


func _setup_input() -> void:
	_add_action("move_left", [KEY_LEFT, KEY_A], [JOY_BUTTON_DPAD_LEFT], -1.0)
	_add_action("move_right", [KEY_RIGHT, KEY_D], [JOY_BUTTON_DPAD_RIGHT], 1.0)
	_add_action("jump", [KEY_SPACE, KEY_UP, KEY_W, KEY_Z], [JOY_BUTTON_A], 0.0)


func _add_action(action: String, keys: Array, buttons: Array, stick_dir: float) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.4)
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
		m.axis = JOY_AXIS_LEFT_X
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

	match state:
		"title":
			if Input.is_action_just_pressed("jump"):
				_start_game()
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
			if idle >= IDLE_LIMIT and has_snow:
				_refreeze()
			elif idle >= IDLE_LIMIT:
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
					_load_level(level_index, false)
				elif level_index + 1 < Levels.all().size():
					_load_level(level_index + 1, true)
				else:
					state = "end"
					_state_t = 1.0
		"end":
			_state_t -= delta
			if _state_t <= 0.0 and Input.is_action_just_pressed("jump"):
				_start_game()

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
	level = Levels.all()[i]
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
	for p in level.get("snow", []):
		var sf := SnowflakeScript.new()
		sf.setup(self, p)
		world.add_child(sf)
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
	has_snow = false
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


## A snowflake touched the cube. Returns false (and leaves the pickup) if one is already held.
func collect_snow() -> bool:
	if state != "play" or has_snow:
		return false
	has_snow = true
	synth.play("chime", 1567.98, -14.0) # G6
	return true


# The held snowflake spends itself instead of letting the cube melt from stillness.
# Only stillness: hazards and falls still kill.
func _refreeze() -> void:
	has_snow = false
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
	_show("Bravo! New best %s" % format_time(level_time) if _record_clear() else "Bravo!", 1.8)


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
	if state == "title" or not is_instance_valid(player):
		return
	var lead := clampf(player.velocity.x * 0.35, -180.0, 180.0)
	var target := player.position + Vector2(lead, -60.0)
	camera.position = camera.position.lerp(target, 1.0 - exp(-5.0 * delta))

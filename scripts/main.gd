extends Node2D
## Game controller: beat clock, stillness timer, level loading, camera, audio cues.

const PlayerScript := preload("res://scripts/player.gd")
const PlatformScript := preload("res://scripts/platform.gd")
const HazardScript := preload("res://scripts/hazard.gd")
const GoalScript := preload("res://scripts/goal.gd")
const SignScript := preload("res://scripts/sign.gd")
const SynthScript := preload("res://scripts/synth.gd")
const BackgroundScript := preload("res://scripts/background.gd")
const HudScript := preload("res://scripts/hud.gd")
const Levels := preload("res://scripts/levels.gd")

const DEFAULT_BPM := 100.0
const TEMPO_RAMP_BEATS := 4.0 # a tempo zone eases to its new bpm over one bar
const IDLE_LIMIT := 2.0
const DRIP_START := 1.0 # stillness (s) before warning drips begin
const DEFAULT_SWITCH_BEATS := 2
const SWITCH_GRACE := 0.7 # from this switch_phase on, the incoming beat group is already solid
const RESTART_MELT := 0.7 # auto-restart delay after melting from stillness
const RESTART_FAST := 0.5 # auto-restart delay after a sizzle or a fall
const SKIP_LOCKOUT := 0.2 # a fresh press after this long into dying restarts immediately
const ROOT_HZ := 523.25 # C5
const BASS_HZ := 130.81 # C3
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
var level_index := 0
var level: Dictionary = {}
var state := "title" # title, play, dying, win, end
var message := ""
var message_t := 0.0

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
var _drip_t := 0.0 # countdown to the next stillness warning drip
var _goal: GoalScript


func _ready() -> void:
	randomize()
	_setup_input()
	RenderingServer.set_default_clear_color(Color("17122b"))

	synth = SynthScript.new()
	add_child(synth)

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
			get_tree().quit()
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
			if _input_active():
				idle = 0.0
			else:
				idle += delta
			player.melt = melt_ratio()
			_update_tempo_zones()
			_update_drips(delta)
			if idle >= IDLE_LIMIT:
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


func melt_ratio() -> float:
	return clampf(idle / IDLE_LIMIT, 0.0, 1.0)


## True while this group's bar is playing (ignores the grace overlap).
func beat_group_on(group: int) -> bool:
	return floori(float(beat) / switch_beats) % 2 == group


## True while the group is solid: its own bar, plus the incoming grace window.
func beat_group_active(group: int) -> bool:
	return beat_group_on(group) or switch_phase >= SWITCH_GRACE


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
	for r in level.get("hot", []):
		var hz := HazardScript.new()
		hz.setup(self, r)
		world.add_child(hz)
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
	_show("Bravo!", 1.8)


func _show(text: String, duration: float) -> void:
	message = text
	message_t = duration


func _update_camera(delta: float) -> void:
	if state == "title" or not is_instance_valid(player):
		return
	var lead := clampf(player.velocity.x * 0.35, -180.0, 180.0)
	var target := player.position + Vector2(lead, -60.0)
	camera.position = camera.position.lerp(target, 1.0 - exp(-5.0 * delta))

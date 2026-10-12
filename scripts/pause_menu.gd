extends Node
## Pause menu. Pausing sets SceneTree.paused, which freezes main.gd (beat clock, stillness,
## level timer, power-ups, death and win countdowns), the world, the background and the
## camera. Only this node, the HUD and the synth run while paused (PROCESS_MODE_ALWAYS),
## so pads already sounding ring out but no new ticks, bass or notes start.

const ITEMS := ["Resume", "Exit to main menu", "Exit game"]

var main
var index := 0 # highlighted item
var flash := 0.0 # 1 -> 0, HUD pop when the highlight moves or an item is chosen

var _hold := 0.0 # countdown to the next auto-repeat step while up/down is held


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_open() -> bool:
	return get_tree().paused


func open() -> void:
	if is_open() or not main.is_playing():
		return
	index = 0
	flash = 1.0
	_hold = main.MENU_REPEAT_DELAY
	get_tree().paused = true
	main.synth.play("thud", 196.0, -10.0)


func _unpause() -> void:
	get_tree().paused = false


# Esc / Start pause during a level; Esc, Start or B resume. While paused main.gd gets no
# input, so its other keys (mute, fullscreen) are passed on to it here.
func _input(event: InputEvent) -> void:
	var key: bool = event is InputEventKey and event.pressed and not event.echo
	var pad: bool = event is InputEventJoypadButton and event.pressed
	var toggle: bool = (key and event.keycode == KEY_ESCAPE) or (pad and event.button_index == JOY_BUTTON_START)
	if not is_open():
		if toggle and main.is_playing():
			open()
			get_viewport().set_input_as_handled()
		return
	if toggle or (pad and event.button_index == JOY_BUTTON_B):
		select(0)
		get_viewport().set_input_as_handled()
	else:
		main._input(event)


# Leaving the window mid-level pauses it.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_inside_tree() and main and main.is_playing():
		open()


# Up/down moves the highlight (wrapping, auto-repeating while held), like the main menu.
# Select is read here, after this frame's physics, so Space on Resume can't also jump.
func _process(delta: float) -> void:
	flash = maxf(flash - delta * 4.0, 0.0)
	if not is_open():
		return
	var dir := 0
	if Input.is_action_just_pressed("menu_up"):
		dir = -1
		_hold = main.MENU_REPEAT_DELAY
	elif Input.is_action_just_pressed("menu_down"):
		dir = 1
		_hold = main.MENU_REPEAT_DELAY
	elif Input.is_action_pressed("menu_up") != Input.is_action_pressed("menu_down"):
		_hold -= delta
		if _hold <= 0.0:
			_hold = main.MENU_REPEAT_RATE
			dir = -1 if Input.is_action_pressed("menu_up") else 1
	if dir != 0:
		highlight(posmod(index + dir, ITEMS.size()))
	if Input.is_action_just_pressed("menu_select"):
		select(index)


## Highlight an item directly (the HUD calls this on mouse hover).
func highlight(i: int) -> void:
	if i == index:
		return
	index = i
	flash = 1.0
	main.synth.play("tick", 2093.0, -12.0) # C7 blip, as on the main menu


func select(i: int) -> void:
	if not is_open():
		return
	index = i
	flash = 1.0
	main.synth.play("chime", 1046.5, -10.0) # C6
	match i:
		0: # Resume: that was an input, so the pause doesn't count toward melting.
			_unpause()
			main.idle = 0.0
		1: # Abandon the attempt: no time or best is recorded.
			_unpause()
			main._to_menu()
		2:
			main._quit()

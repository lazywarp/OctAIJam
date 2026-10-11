extends CharacterBody2D
## The ice cube. Platformer movement plus a melt visual driven by main.gd.

signal jumped
signal landed

const SIZE := 36.0
const SPEED := 340.0
const GROUND_ACCEL := 2600.0
const GROUND_FRICTION := 3200.0
const AIR_ACCEL := 1700.0
const GRAVITY := 1700.0
const MAX_FALL := 1300.0
const JUMP_VELOCITY := -640.0
const COYOTE_TIME := 0.1
const JUMP_BUFFER := 0.12
const INK := Color("1a1424")

var melt := 0.0 # 0..1, how close to melting from standing still
var dead := false

var _shown_melt := 0.0
var _melt_speed := 2.4
var _coyote := 0.0
var _buffer := 0.0
var _was_on_floor := true
var _squash := Vector2.ONE
var _face := 1.0
var _time := 0.0
var _box := StyleBoxFlat.new()


func _ready() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(SIZE - 2.0, SIZE)
	shape.shape = rect
	add_child(shape)
	_box.border_color = Color(1, 1, 1, 0.95)
	_box.set_border_width_all(2)


func die(hot: bool) -> void:
	dead = true
	velocity = Vector2.ZERO
	_melt_speed = 4.0 if hot else 2.4 # fully melted well before main.gd restarts


func win() -> void:
	dead = true
	velocity = Vector2.ZERO
	visible = false


func _physics_process(delta: float) -> void:
	if dead:
		return
	var dir := Input.get_axis("move_left", "move_right")
	var on_floor := is_on_floor()

	var accel := GROUND_ACCEL if on_floor else AIR_ACCEL
	if is_zero_approx(dir) and on_floor:
		accel = GROUND_FRICTION
	velocity.x = move_toward(velocity.x, dir * SPEED, accel * delta)
	velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)

	_coyote = COYOTE_TIME if on_floor else _coyote - delta
	_buffer = JUMP_BUFFER if Input.is_action_just_pressed("jump") else _buffer - delta
	if _buffer > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		_buffer = 0.0
		_coyote = 0.0
		_squash = Vector2(0.7, 1.3)
		jumped.emit()
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= 0.5

	move_and_slide()

	var now_on_floor := is_on_floor()
	if now_on_floor and not _was_on_floor:
		_squash = Vector2(1.3, 0.75)
		landed.emit()
	_was_on_floor = now_on_floor
	if not is_zero_approx(dir):
		_face = signf(dir)


func _process(delta: float) -> void:
	_time += delta
	var target := 1.0 if dead else melt
	if target > _shown_melt:
		_shown_melt = move_toward(_shown_melt, target, delta * (_melt_speed if dead else 10.0))
	else:
		_shown_melt = move_toward(_shown_melt, target, delta * 5.0)
	_squash = _squash.lerp(Vector2.ONE, 1.0 - exp(-12.0 * delta))
	queue_redraw()


func _draw() -> void:
	var m := _shown_melt
	var bottom := SIZE * 0.5

	if m > 0.02:
		_ellipse(Vector2(0, bottom - 2.0), Vector2(SIZE * (0.5 + 1.3 * m), 3.0 + 5.0 * m),
			Color(0.55, 0.85, 1.0, 0.55 * m))
	if dead and m > 0.97:
		return

	var w := SIZE * (1.0 + 0.5 * m) * _squash.x
	var h := SIZE * (1.0 - 0.8 * m) * _squash.y
	var shake := sin(_time * 70.0) * 2.5 * maxf(m - 0.4, 0.0)
	var rect := Rect2(-w * 0.5 + shake, bottom - h, w, h)

	_box.bg_color = Color(0.72, 0.93, 1.0, 0.9)
	_box.set_corner_radius_all(int(6.0 + 10.0 * m))
	draw_style_box(_box, rect)
	draw_line(rect.position + Vector2(6, 6), rect.position + Vector2(6, minf(h - 6.0, 16.0)),
		Color(1, 1, 1, 0.9), 3.0)

	# Drips once it starts to go soft.
	if m > 0.25:
		for i in 3:
			var t := fposmod(_time * 1.6 + i * 0.37, 1.0)
			var px := rect.position.x + w * (0.2 + 0.3 * i)
			draw_circle(Vector2(px, bottom - h * 0.3 + t * h * 0.5), 1.0 + 2.5 * m,
				Color(0.6, 0.9, 1.0, 0.8 * (1.0 - t)))

	if h < 14.0:
		return
	var cx := rect.get_center().x + _face * 3.0
	var eye_y := rect.position.y + h * 0.42
	draw_circle(Vector2(cx - 7, eye_y), 2.6, INK)
	draw_circle(Vector2(cx + 7, eye_y), 2.6, INK)
	if m < 0.4:
		draw_arc(Vector2(cx, eye_y + 3), 5.0, 0.3, PI - 0.3, 8, INK, 2.0)
	else:
		draw_arc(Vector2(cx, eye_y + 11), 5.0, PI + 0.4, TAU - 0.4, 8, INK, 2.0)
		draw_circle(Vector2(rect.end.x - 4, rect.position.y + 6), 3.0, Color(0.6, 0.9, 1.0))


func _ellipse(c: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_colored_polygon(pts, col)

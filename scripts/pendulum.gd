extends AnimatableBody2D
## A brass slab hanging from a rod, swinging with the background metronome.

const COL := Color("e8b04a")
const INK := Color("1a1424")
const HEIGHT := 24.0

var main
var pivot := Vector2.ZERO
var rod_length := 200.0
var width := 140.0
var max_angle := 0.6

var _box := StyleBoxFlat.new()


func setup(m, p: Vector2, length: float, w: float, angle := 0.6) -> void:
	main = m
	pivot = p
	rod_length = length
	width = w
	max_angle = angle
	position = _target()


func _ready() -> void:
	sync_to_physics = true
	process_physics_priority = -1 # move before the player reads its floor
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(width, HEIGHT)
	cs.shape = r
	cs.one_way_collision = true
	add_child(cs)
	_box.set_corner_radius_all(8)
	_box.set_border_width_all(3)
	_box.border_color = INK


func _target() -> Vector2:
	var s: float = main.swing()
	var a := s * max_angle
	return pivot + Vector2(sin(a), cos(a)) * rod_length


func _physics_process(_delta: float) -> void:
	position = _target()
	queue_redraw()


func _draw() -> void:
	var top := Vector2(0, -HEIGHT * 0.5)
	var piv := pivot - position
	# Rod and pivot cap.
	draw_line(piv, top, INK, 6.0)
	draw_line(piv, top, Color(COL, 0.85), 3.0)
	draw_circle(piv, 9.0, INK)
	draw_circle(piv, 6.0, COL)
	draw_circle(piv + Vector2(-2, -2), 2.0, Color(1, 1, 1, 0.6))

	# The slab: a brass metronome weight with a shine and a centre clamp.
	var r := Rect2(Vector2(-width * 0.5, -HEIGHT * 0.5), Vector2(width, HEIGHT))
	_box.bg_color = COL
	draw_style_box(_box, r)
	draw_rect(Rect2(r.position + Vector2(6, 4), Vector2(width - 12, 3)), Color(1, 1, 1, 0.45))
	draw_rect(Rect2(r.position + Vector2(6, HEIGHT - 9), Vector2(width - 12, 4)), Color(COL.darkened(0.35), 0.8))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-10, -HEIGHT * 0.5 + 3), Vector2(10, -HEIGHT * 0.5 + 3),
		Vector2(6, HEIGHT * 0.5 - 4), Vector2(-6, HEIGHT * 0.5 - 4),
	]), COL.darkened(0.25))
	draw_circle(top + Vector2(0, 2), 4.0, INK)

extends Area2D
## A stage heat lamp. Not deadly on its own: while the cube stands in its light,
## stillness fills twice as fast. The fixture hangs at the top of the rect and the
## light cone fades out at the bottom.

const PlayerScript := preload("res://scripts/player.gd")
const INK := Color("1a1424")
const WARM := Color("ffb347")
const BULB := Color("fff1c4")
const HOUSING_W := 44.0
const HOUSING_H := 22.0

var main
var size := Vector2(160, 300)
var _t := 0.0


func setup(m, rect: Rect2) -> void:
	main = m
	size = rect.size
	position = rect.get_center()


func _ready() -> void:
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = size
	cs.shape = r
	add_child(cs)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_t = randf() * 10.0


func _on_body_entered(body: Node2D) -> void:
	if body is PlayerScript:
		main.lamp_entered(self, body)


func _on_body_exited(body: Node2D) -> void:
	if body is PlayerScript:
		main.lamp_exited(self)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var top := -size.y * 0.5
	var bottom := size.y * 0.5
	var flicker := 0.92 + 0.05 * sin(_t * 13.0) + 0.03 * sin(_t * 31.0 + 1.3)
	var bulb_y := top + HOUSING_H + 2.0

	# Light cone: narrow at the bulb, full rect width at the bottom, fading out.
	var hw := size.x * 0.5
	var glow := Color(WARM, 0.26 * flicker)
	var faint := Color(WARM, 0.06 * flicker) # keeps the zone's edge readable at the floor
	var clear := Color(WARM, 0.0)
	draw_polygon(PackedVector2Array([
		Vector2(-HOUSING_W * 0.4, bulb_y), Vector2(HOUSING_W * 0.4, bulb_y),
		Vector2(hw, bottom), Vector2(-hw, bottom)
	]), PackedColorArray([glow, glow, faint, faint]))
	# A brighter core so the cone reads as a beam, not a box.
	var core := Color(WARM, 0.14 * flicker)
	draw_polygon(PackedVector2Array([
		Vector2(-HOUSING_W * 0.25, bulb_y), Vector2(HOUSING_W * 0.25, bulb_y),
		Vector2(hw * 0.45, bottom), Vector2(-hw * 0.45, bottom)
	]), PackedColorArray([core, core, clear, clear]))

	# Fixture: cord, dark housing, glowing bulb.
	draw_line(Vector2(0, top - 40.0), Vector2(0, top + 2.0), INK, 3.0)
	draw_circle(Vector2(0, bulb_y), 16.0, Color(WARM, 0.25 * flicker))
	draw_circle(Vector2(0, bulb_y), 8.0, BULB.lerp(WARM, 0.3 * (1.0 - flicker)))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-8, top), Vector2(8, top),
		Vector2(HOUSING_W * 0.5, top + HOUSING_H), Vector2(-HOUSING_W * 0.5, top + HOUSING_H)
	]), INK)
	draw_line(Vector2(-HOUSING_W * 0.5 + 3.0, top + HOUSING_H - 1.0),
		Vector2(HOUSING_W * 0.5 - 3.0, top + HOUSING_H - 1.0), WARM, 2.0)

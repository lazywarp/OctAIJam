extends Area2D
## A glass of lemonade. Dive in to finish the level.

const PlayerScript := preload("res://scripts/player.gd")

var main
var _t := 0.0
var _splash := -1.0


func _ready() -> void:
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(56, 80)
	cs.shape = r
	cs.position = Vector2(0, -40)
	add_child(cs)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body is PlayerScript:
		main.reach_goal()


func celebrate() -> void:
	_splash = 0.0


func _process(delta: float) -> void:
	_t += delta
	if _splash >= 0.0:
		_splash += delta
	queue_redraw()


func _half_width(y: float) -> float:
	return lerpf(26.0, 34.0, -y / 96.0)


func _draw() -> void:
	draw_circle(Vector2(0, -50), 70.0 + 6.0 * sin(_t * 3.0), Color(1.0, 0.9, 0.4, 0.08))

	var top := -62.0 - (10.0 if _splash >= 0.0 else 0.0)
	var liquid := PackedVector2Array([
		Vector2(-_half_width(top), top), Vector2(_half_width(top), top),
		Vector2(26, 0), Vector2(-26, 0),
	])
	draw_colored_polygon(liquid, Color(1.0, 0.88, 0.3, 0.85))
	for i in 4:
		var by := fposmod(-_t * 30.0 - i * 17.0, -top)
		draw_circle(Vector2(-14 + i * 9, -by), 2.0, Color(1, 1, 1, 0.5))

	var bob := sin(_t * 2.0) * 2.0
	draw_rect(Rect2(-20, top - 8 + bob, 14, 14), Color(0.8, 0.95, 1.0, 0.85))
	draw_rect(Rect2(6, top - 6 - bob, 12, 12), Color(0.8, 0.95, 1.0, 0.85))
	if _splash >= 0.0:
		# The player, safe and chilled.
		draw_rect(Rect2(-9, top - 12 + bob, 18, 18), Color(0.72, 0.93, 1.0))
		for i in 8:
			var a := -PI * (0.15 + 0.7 * i / 7.0)
			var p := Vector2(cos(a), sin(a)) * _splash * 160.0 + Vector2(0, 300.0 * _splash * _splash)
			draw_circle(Vector2(0, top) + p, 3.0, Color(1.0, 0.9, 0.4, maxf(1.0 - _splash, 0.0)))

	draw_line(Vector2(8, -20), Vector2(26, -124), Color(1.0, 0.4, 0.55), 5.0)
	draw_circle(Vector2(-32, -96), 13.0, Color(1.0, 0.9, 0.2))
	draw_circle(Vector2(-32, -96), 9.0, Color(1.0, 0.97, 0.6))
	var glass := PackedVector2Array([Vector2(-34, -96), Vector2(34, -96), Vector2(26, 0), Vector2(-26, 0), Vector2(-34, -96)])
	draw_polyline(glass, Color(1, 1, 1, 0.85), 3.0)

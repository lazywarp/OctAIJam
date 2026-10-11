extends Area2D
## Red-hot notes. Touching one melts the cube instantly.

const PlayerScript := preload("res://scripts/player.gd")

var main
var size := Vector2(40, 40)
var _t := 0.0


func setup(m, rect: Rect2) -> void:
	main = m
	size = rect.size
	position = rect.get_center()


func _ready() -> void:
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = size - Vector2(6, 6)
	cs.shape = r
	add_child(cs)
	body_entered.connect(_on_body_entered)
	_t = randf() * 10.0


func _on_body_entered(body: Node2D) -> void:
	if body is PlayerScript:
		main.die("Too hot! You melted.", true)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var r := Rect2(-size * 0.5, size)
	draw_rect(r.grow(6.0), Color(1.0, 0.3, 0.1, 0.12 + 0.05 * sin(_t * 5.0)))
	draw_rect(r, Color(0.45, 0.05, 0.08))
	var n := int(size.x / 16.0) + 1
	for i in n:
		var x := r.position.x + (i + 0.5) * size.x / n
		var hgt := 12.0 + 8.0 * sin(_t * 9.0 + i * 1.7)
		var col := Color(1.0, 0.45 + 0.25 * sin(_t * 7.0 + i), 0.1)
		draw_colored_polygon(PackedVector2Array([
			Vector2(x - 7, r.position.y), Vector2(x, r.position.y - hgt), Vector2(x + 7, r.position.y)
		]), col)
	draw_rect(r, Color(1.0, 0.45, 0.2), false, 2.0)

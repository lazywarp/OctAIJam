extends Node2D
## Screen-space backdrop: a giant metronome, music staves and notes that pulse on the beat.

var main


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var vp := get_viewport_rect().size
	var cam: Vector2 = main.camera.get_screen_center_position()
	var beat: int = main.beat
	var phase: float = main.beat_phase
	var pulse := pow(1.0 - phase, 3.0)

	draw_circle(Vector2(vp.x * 0.5, vp.y * 0.6), vp.y * 0.7, Color(0.35, 0.15, 0.55, 0.16 + 0.05 * pulse))

	# A small metronome in the top-right corner, clear of the play area. It swings to an
	# extreme on every tick.
	var k := 0.32
	var base := Vector2(vp.x - 96.0, 300.0)
	draw_colored_polygon(PackedVector2Array([
		base + Vector2(-170, 0) * k, base + Vector2(170, 0) * k, base + Vector2(60, -560) * k, base + Vector2(-60, -560) * k
	]), Color(1, 1, 1, 0.07))
	var swing: float = main.swing()
	var angle := swing * 0.5
	var pivot := base + Vector2(0, -70) * k
	var dir := Vector2(sin(angle), -cos(angle))
	draw_line(pivot, pivot + dir * 520.0 * k, Color(1, 1, 1, 0.22), 3.0)
	draw_circle(pivot + dir * 330.0 * k, 9.0, Color(1, 1, 1, 0.2 + 0.15 * pulse))

	# Staves drift with a little parallax.
	for st in 3:
		var y0 := fposmod(st * 260.0 - cam.y * 0.1, vp.y + 200.0) - 100.0
		for l in 5:
			draw_line(Vector2(0, y0 + l * 16.0), Vector2(vp.x, y0 + l * 16.0), Color(1, 1, 1, 0.06), 2.0)

	# Floating notes that throb with the beat.
	for i in 18:
		var x := fposmod(i * 211.0 - cam.x * 0.25, vp.x + 120.0) - 60.0
		var y := fposmod(i * 137.0 - cam.y * 0.2, vp.y) + sin(i + beat * 0.5) * 6.0
		var s := 1.0 + 0.35 * pulse * float((i + beat) % 3 == 0)
		var col := Color(1, 1, 1, 0.1)
		draw_circle(Vector2(x, y), 7.0 * s, col)
		draw_line(Vector2(x + 6.0 * s, y), Vector2(x + 6.0 * s, y - 26.0 * s), col, 2.0)

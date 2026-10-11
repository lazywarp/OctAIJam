extends Node2D
## Screen-space UI: title, level name, stillness meter, messages, end screen.

var main
var font: Font
var _t := 0.0


func _ready() -> void:
	font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _text(y: float, text: String, size: int, col: Color) -> void:
	var w := get_viewport_rect().size.x
	draw_string_outline(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, 8, Color(0.05, 0.03, 0.1, 0.8))
	draw_string(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, col)


func _draw() -> void:
	var vp := get_viewport_rect().size
	var blink := 0.55 + 0.45 * sin(_t * 4.0)

	match main.state:
		"title":
			_text(vp.y * 0.32, "MELTRONOME", 96, Color("bff3ff"))
			_text(vp.y * 0.32 + 60, "You are an ice cube at a very strange concert.", 26, Color.WHITE)
			_text(vp.y * 0.32 + 96, "Stop pressing for 2 seconds and you melt.", 26, Color("ffb3a0"))
			_text(vp.y * 0.72, "Press SPACE to begin", 34, Color(1, 1, 1, blink))
			_text(vp.y * 0.72 + 44, "Move: Arrows / A D     Jump: Space / W     Fullscreen: F11     Quit: Esc", 18, Color(1, 1, 1, 0.6))
		"end":
			_text(vp.y * 0.34, "FINE", 110, Color("ffe27a"))
			_text(vp.y * 0.34 + 60, "The concert is over. You stayed frozen.", 28, Color.WHITE)
			_text(vp.y * 0.34 + 100, "Melts: %d" % main.deaths, 28, Color("bff3ff"))
			_text(vp.y * 0.74, "Press SPACE to play again (da capo)", 30, Color(1, 1, 1, blink))
		_:
			_draw_play_hud(vp)

	if main.message_t > 0.0:
		var a := clampf(main.message_t * 2.0, 0.0, 1.0)
		_text(vp.y * 0.28, main.message, 46, Color(1, 1, 1, a))


func _draw_play_hud(vp: Vector2) -> void:
	var blink := 0.55 + 0.45 * sin(_t * 10.0)
	var k: float = 1.0 if main.state == "dying" else (0.0 if main.state == "win" else main.melt_ratio())

	if k > 0.4:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(1.0, 0.35, 0.2, (k - 0.4) / 0.6 * 0.18))

	draw_string_outline(font, Vector2(24, 44), main.level.get("name", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, 8, Color(0.05, 0.03, 0.1, 0.8))
	draw_string(font, Vector2(24, 44), main.level.get("name", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE)
	var right := "Level %d/%d    Melts: %d" % [main.level_index + 1, main.level_count(), main.deaths]
	draw_string(font, Vector2(vp.x - 424, 44), right, HORIZONTAL_ALIGNMENT_RIGHT, 400, 24, Color(1, 1, 1, 0.85))

	var bar := Rect2(vp.x * 0.5 - 180.0, vp.y - 44.0, 360.0, 12.0)
	draw_rect(bar, Color(1, 1, 1, 0.12))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * k, bar.size.y)), Color("8fe3ff").lerp(Color("ff5a3c"), k))
	draw_rect(bar, Color(1, 1, 1, 0.5), false, 2.0)
	var label := "KEEP MOVING!" if k > 0.5 else "stillness"
	var label_col := Color(1.0, 0.5, 0.4, blink) if k > 0.5 else Color(1, 1, 1, 0.5)
	draw_string(font, Vector2(0, bar.position.y - 8.0), label, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 18, label_col)

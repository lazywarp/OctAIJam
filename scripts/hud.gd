extends Node2D
## Screen-space UI: main menu, level name, stillness meter, messages, end screen.

const Powerups := preload("res://scripts/powerups.gd")
const POWER_STEP := 22.0 # spacing of the active power-up icons on the meter panel
const POWER_MAX := 5 # icons that fit left of the meter label

var main
var font: Font
var _t := 0.0
var _menu_rects: Array[Rect2] = [] # main menu item hit boxes, from the last draw (for the mouse)
var _pause_rects: Array[Rect2] = [] # pause menu item hit boxes, likewise
var _box := StyleBoxFlat.new()


func _ready() -> void:
	font = ThemeDB.fallback_font


# Mouse on the main menu or the pause menu: hovering highlights an item, a left click selects it.
func _input(event: InputEvent) -> void:
	var paused: bool = main.pause_menu.is_open()
	if main.state != "menu" and not paused:
		return
	var mouse_move := event is InputEventMouseMotion
	var click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if not mouse_move and not click:
		return
	var at := get_local_mouse_position()
	if paused:
		for i in _pause_rects.size():
			if _pause_rects[i].has_point(at):
				if click:
					main.pause_menu.select(i)
				else:
					main.pause_menu.highlight(i)
				return
		return
	for i in _menu_rects.size():
		if _menu_rects[i].has_point(at):
			if click:
				main.menu_select(i)
			else:
				main.menu_highlight(i)
			return


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
		"menu":
			_draw_menu(vp)
		"settings":
			_draw_settings(vp)
		"end":
			# Dim the last level so the results table stays readable.
			draw_rect(Rect2(Vector2.ZERO, vp), Color(0.05, 0.03, 0.1, 0.8))
			_text(vp.y * 0.24, "FINE", 110, Color("ffe27a"))
			_text(vp.y * 0.24 + 56, "The concert is over. You stayed frozen.", 28, Color.WHITE)
			_text(vp.y * 0.24 + 94, "Melts: %d" % main.deaths, 28, Color("bff3ff"))
			_draw_times_table(vp, vp.y * 0.24 + 136)
			_text(vp.y * 0.80, "Press SPACE for the menu (da capo)", 30, Color(1, 1, 1, blink))
		_:
			_draw_play_hud(vp)

	if main.message_t > 0.0 and main.state != "menu" and not main.pause_menu.is_open(): # the menu draws its own
		var a := clampf(main.message_t * 2.0, 0.0, 1.0)
		_text(vp.y * 0.28, main.message, 46, Color(1, 1, 1, a))

	if main.pause_menu.is_open():
		_draw_pause(vp)

	if AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")):
		var pos := Vector2(vp.x - 224, vp.y - 20)
		draw_string_outline(font, pos, "Muted (M)", HORIZONTAL_ALIGNMENT_RIGHT, 200, 18, 6, Color(0.05, 0.03, 0.1, 0.6))
		draw_string(font, pos, "Muted (M)", HORIZONTAL_ALIGNMENT_RIGHT, 200, 18, Color(1, 1, 1, 0.5))


# Main menu: title and premise, the items (the highlighted one in lemon between an ice cube
# and a note, both bobbing on the beat), any "coming soon" message, and a controls hint.
func _draw_menu(vp: Vector2) -> void:
	var top := vp.y * 0.2
	_text(top, "MELTRONOME", 96, Color("bff3ff"))
	_text(top + 54, "You are an ice cube at a very strange concert.", 26, Color.WHITE)
	_text(top + 88, "Stop pressing for 2 seconds and you melt.", 22, Color("ffb3a0"))

	var items: Array = main.MENU
	var y0 := vp.y * 0.47
	var step := 52.0
	var cx := vp.x * 0.5
	var phase: float = main.beat_phase
	var pulse := pow(1.0 - phase, 3.0) # 1 on the tick, easing to 0
	var pop: float = main.menu_flash
	_menu_rects.clear()
	for i in items.size():
		var item: Dictionary = items[i]
		var label: String = item["label"]
		var soon: bool = item.get("soon", false)
		var sel: bool = i == main.menu_index
		var y := y0 + step * i
		var size := 40 if sel else 34
		if sel:
			size += roundi(4.0 * pop)
		var col := Color("ffe27a") if sel else Color.WHITE
		if soon:
			col.a = 0.75 if sel else 0.4
		var half := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.5
		if sel:
			# A soft lemon band behind the row, a touch brighter on the tick.
			var band := Rect2(cx - half - 70.0, y - step * 0.72, half * 2.0 + 140.0 + (44.0 if soon else 0.0), step * 0.92)
			draw_rect(band, Color(1.0, 0.89, 0.48, 0.07 + 0.05 * pulse))
		_text(y, label, size, col)
		_menu_rects.append(Rect2(cx - 220.0, y - step * 0.68, 440.0, step))
		if soon:
			var tag_pos := Vector2(cx + half + 12.0, y - 4.0)
			draw_string_outline(font, tag_pos, "soon", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 5, Color(0.05, 0.03, 0.1, 0.8))
			draw_string(font, tag_pos, "soon", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.89, 0.48, 0.75 if sel else 0.5))
		if sel:
			var mid := y - size * 0.36
			var bob := -6.0 * pulse
			_draw_cube(Vector2(cx - half - 38.0, mid + bob), 30.0 + 4.0 * pulse)
			_draw_note(Vector2(cx + half + (74.0 if soon else 30.0), mid - bob), Color("ffe27a"))

	if main.message_t > 0.0:
		var a := clampf(main.message_t * 2.0, 0.0, 1.0)
		_text(y0 + step * items.size() + 8.0, main.message, 24, Color(1.0, 0.89, 0.48, a))
	_text(vp.y - 52.0, "Menu: Up / Down, Space / Enter    In game: Move with Arrows / A D, Jump with Space / W", 18, Color(1, 1, 1, 0.6))
	_text(vp.y - 26.0, "Mute: M    Fullscreen: F11    Quit: Esc", 18, Color(1, 1, 1, 0.6))


# Pause overlay: the frozen level dimmed behind "PAUSED" and the items, highlighted like the
# main menu. The cube and note bob on the HUD's own clock, since the beat is frozen.
func _draw_pause(vp: Vector2) -> void:
	var pm = main.pause_menu
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.05, 0.03, 0.1, 0.72))
	var top := vp.y * 0.3
	_text(top, "PAUSED", 96, Color("bff3ff"))
	_text(top + 46, "The concert holds its breath.", 24, Color(1, 1, 1, 0.75))

	var items: Array = pm.ITEMS
	var y0 := vp.y * 0.53
	var step := 52.0
	var cx := vp.x * 0.5
	var pulse := pow(1.0 - fposmod(_t * 1.2, 1.0), 3.0)
	var pop: float = pm.flash
	_pause_rects.clear()
	for i in items.size():
		var label: String = items[i]
		var sel: bool = i == pm.index
		var y := y0 + step * i
		var size := 40 if sel else 34
		if sel:
			size += roundi(4.0 * pop)
		var half := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.5
		if sel:
			draw_rect(Rect2(cx - half - 70.0, y - step * 0.72, half * 2.0 + 140.0, step * 0.92), Color(1.0, 0.89, 0.48, 0.07 + 0.05 * pulse))
		_text(y, label, size, Color("ffe27a") if sel else Color.WHITE)
		_pause_rects.append(Rect2(cx - 240.0, y - step * 0.68, 480.0, step))
		if sel:
			var mid := y - size * 0.36
			var bob := -6.0 * pulse
			_draw_cube(Vector2(cx - half - 38.0, mid + bob), 30.0 + 4.0 * pulse)
			_draw_note(Vector2(cx + half + 30.0, mid - bob), Color("ffe27a"))
	_text(y0 + step * items.size() + 14.0, "Up / Down, Space / Enter    Resume: Esc", 18, Color(1, 1, 1, 0.6))


# Settings screen, styled like the main menu: label on the left, value on the right (a bar
# and a percentage for volumes, On/Off for fullscreen), the highlighted row in lemon on a
# soft band between the bobbing cube and note.
func _draw_settings(vp: Vector2) -> void:
	var top := vp.y * 0.2
	_text(top, "SETTINGS", 80, Color("bff3ff"))
	_text(top + 50, "Tune the concert to your ears.", 24, Color.WHITE)

	var s = main.settings
	var items: Array = s.ITEMS
	var y0 := vp.y * 0.43
	var step := 60.0
	var cx := vp.x * 0.5
	var left := cx - 360.0
	var right := cx + 360.0
	var pulse := pow(1.0 - float(main.beat_phase), 3.0)
	var pop: float = main.menu_flash
	var vpop: float = s.value_flash
	var lemon := Color("ffe27a")
	for i in items.size():
		var item: String = items[i]
		var label: String = s.LABELS[item]
		var sel: bool = i == int(s.index)
		var y := y0 + step * i + (12.0 if item == "back" else 0.0) # Back sits a little apart
		var size := 34 if sel else 30
		if sel:
			size += roundi(4.0 * pop)
		var col := lemon if sel else Color.WHITE
		var mid := y - size * 0.36
		if sel:
			draw_rect(Rect2(left - 40.0, y - step * 0.7, right - left + 80.0, step * 0.92), Color(1.0, 0.89, 0.48, 0.07 + 0.05 * pulse))
			var bob := -6.0 * pulse
			_draw_cube(Vector2(left - 72.0, mid + bob), 30.0 + 4.0 * pulse)
			_draw_note(Vector2(right + 66.0, mid - bob), lemon)
		if item == "back":
			_text(y, label, size, col)
			continue
		draw_string_outline(font, Vector2(left, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 8, Color(0.05, 0.03, 0.1, 0.8))
		draw_string(font, Vector2(left, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		var vsize := size + (roundi(3.0 * vpop) if sel else 0)
		if item == "fullscreen":
			var on: bool = s.fullscreen
			_cell(right, y, "On" if on else "Off", vsize, col if on else Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_RIGHT)
			continue
		var pct: int = s.music if item == "music" else s.sfx
		_cell(right, y, "%d%%" % pct, vsize, col, HORIZONTAL_ALIGNMENT_RIGHT)
		# The level bar, with small arrows either side on the highlighted row.
		var bar := Rect2(right - 310.0, mid - 6.0, 180.0, 12.0)
		draw_rect(bar.grow(4.0), Color(0.05, 0.03, 0.1, 0.6))
		draw_rect(bar, Color(1, 1, 1, 0.12))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * pct / 100.0, bar.size.y)), lemon if sel else Color("8fe3ff"))
		for k in range(1, 10): # 10% ticks
			var x := bar.position.x + bar.size.x * k / 10.0
			draw_line(Vector2(x, bar.position.y), Vector2(x, bar.end.y), Color(0.05, 0.03, 0.1, 0.35), 1.0)
		draw_rect(bar, Color(1, 1, 1, 0.5), false, 2.0)
		if sel:
			var a := Color(1.0, 0.89, 0.48, 0.9)
			var ly := bar.get_center().y
			draw_colored_polygon(PackedVector2Array([Vector2(bar.position.x - 18.0, ly), Vector2(bar.position.x - 10.0, ly - 6.0), Vector2(bar.position.x - 10.0, ly + 6.0)]), a)
			draw_colored_polygon(PackedVector2Array([Vector2(bar.end.x + 18.0, ly), Vector2(bar.end.x + 10.0, ly - 6.0), Vector2(bar.end.x + 10.0, ly + 6.0)]), a)

	_text(vp.y - 52.0, "Left / Right to adjust  ·  Space / Enter to choose  ·  Esc to go back", 18, Color(1, 1, 1, 0.6))
	_text(vp.y - 26.0, "Up / Down to move    Mute: M    Fullscreen: F11", 18, Color(1, 1, 1, 0.6))


# A little ice cube, like the player: centred on c, side s.
func _draw_cube(c: Vector2, s: float) -> void:
	var rect := Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s))
	_box.bg_color = Color(0.72, 0.93, 1.0, 0.95)
	_box.set_corner_radius_all(5)
	_box.border_color = Color(0.05, 0.03, 0.1, 0.8)
	_box.set_border_width_all(2)
	draw_style_box(_box, rect)
	draw_line(rect.position + Vector2(6, 6), rect.position + Vector2(6, minf(s - 6.0, 13.0)), Color(1, 1, 1, 0.9), 3.0)


# An eighth note: head at about c, stem and flag up and right.
func _draw_note(c: Vector2, col: Color) -> void:
	var outline := Color(0.05, 0.03, 0.1, 0.8)
	var head := c + Vector2(0, 8)
	var stem_top := head + Vector2(7, -26)
	for pass_i in 2:
		var w := 3.0 if pass_i == 1 else 7.0
		var k := col if pass_i == 1 else outline
		draw_set_transform(head, -0.35, Vector2(1.3, 1.0))
		draw_circle(Vector2.ZERO, 7.0 if pass_i == 1 else 9.0, k)
		draw_set_transform(Vector2.ZERO)
		draw_line(Vector2(stem_top.x, head.y - 2.0), stem_top, k, w)
		draw_line(stem_top, stem_top + Vector2(9, 10), k, w)


func _draw_play_hud(vp: Vector2) -> void:
	var blink := 0.55 + 0.45 * sin(_t * 10.0)
	var k: float = 1.0 if main.state == "dying" else (0.0 if main.state == "win" else main.melt_ratio())

	if k > 0.4:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(1.0, 0.35, 0.2, (k - 0.4) / 0.6 * 0.18))

	draw_string_outline(font, Vector2(24, 44), main.level.get("name", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, 8, Color(0.05, 0.03, 0.1, 0.8))
	draw_string(font, Vector2(24, 44), main.level.get("name", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE)
	var f: float = main.tempo_flash
	var tempo := "%d BPM" % roundi(main.bpm)
	var tempo_size := roundi(lerpf(18.0, 24.0, f))
	draw_string_outline(font, Vector2(24, 72), tempo, HORIZONTAL_ALIGNMENT_LEFT, -1, tempo_size, 6, Color(0.05, 0.03, 0.1, 0.8))
	draw_string(font, Vector2(24, 72), tempo, HORIZONTAL_ALIGNMENT_LEFT, -1, tempo_size, Color(1, 1, 1, 0.6).lerp(Color("ffe27a"), f))
	var right := "Level %d/%d    Melts: %d" % [main.level_index + 1, main.level_count(), main.deaths]
	draw_string(font, Vector2(vp.x - 424, 44), right, HORIZONTAL_ALIGNMENT_RIGHT, 400, 24, Color(1, 1, 1, 0.85))
	var timer: String = main.format_time(main.level_time)
	draw_string(font, Vector2(vp.x - 424, 74), timer, HORIZONTAL_ALIGNMENT_RIGHT, 400, 24, Color(1, 1, 1, 0.85))

	var bar := Rect2(vp.x * 0.5 - 180.0, vp.y - 44.0, 360.0, 12.0)
	# Dark backing so the meter stays readable over ivory piano keys.
	draw_rect(Rect2(bar.position + Vector2(-16, -32), bar.size + Vector2(32, 42)), Color(0.05, 0.03, 0.1, 0.6))
	draw_rect(bar, Color(1, 1, 1, 0.12))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * k, bar.size.y)), Color("8fe3ff").lerp(Color("ff5a3c"), k))
	var lamp: bool = main.state == "play" and main.under_lamp()
	draw_rect(bar, Color(1, 1, 1, 0.5), false, 2.0)
	if lamp:
		draw_rect(bar.grow(3.0), Color(1.0, 0.7, 0.28, 0.6 + 0.2 * sin(_t * 6.0)), false, 2.0)
	_draw_powers(bar)
	var label := "KEEP MOVING!" if k > 0.5 else ("UNDER THE LAMP" if lamp else "stillness")
	var label_col := Color(1.0, 0.5, 0.4, blink) if k > 0.5 else (Color(1.0, 0.7, 0.28, 0.85) if lamp else Color(1, 1, 1, 0.5))
	draw_string(font, Vector2(0, bar.position.y - 8.0), label, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 18, label_col)


# Active power-ups: a row of small icons at the left end of the meter panel, each with a
# thin timer bar underneath (full for "until used" kinds). The last 2 s blink.
func _draw_powers(bar: Rect2) -> void:
	var n := mini(main.powers.size(), POWER_MAX)
	for i in n:
		var fx: Dictionary = main.powers[i]
		var kind: String = fx["kind"]
		var c := bar.position + Vector2(8.0 + POWER_STEP * i, -20.0)
		var timed := float(fx["duration"]) > 0.0
		var a := 1.0
		if timed and float(fx["time_left"]) < 2.0:
			a = 0.45 + 0.55 * absf(cos(_t * 6.0))
		Powerups.draw_icon(self, kind, c, 7.0, _t * 0.5, Color(Powerups.color(kind), a))
		var under := Rect2(c + Vector2(-8.0, 10.0), Vector2(16.0, 2.0))
		draw_rect(under, Color(1, 1, 1, 0.15))
		var r: float = main.power_ratio(fx)
		draw_rect(Rect2(under.position, Vector2(under.size.x * r, under.size.y)), Color(Powerups.accent(kind), a))
		if int(fx["charges"]) > 1:
			draw_string(font, c + Vector2(5.0, 1.0), str(fx["charges"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.85))


# End screen: this run's time and the best time per level, then the run total.
func _draw_times_table(vp: Vector2, y: float) -> void:
	var cx := vp.x * 0.5
	var dim := Color(1, 1, 1, 0.55)
	_cell(cx + 80, y, "This run", 18, dim, HORIZONTAL_ALIGNMENT_RIGHT)
	_cell(cx + 220, y, "Best", 18, dim, HORIZONTAL_ALIGNMENT_RIGHT)
	var n: int = main.level_count()
	for i in n:
		var row_y := y + 28.0 * (i + 1)
		var run_t: float = main.run_times[i] if i < main.run_times.size() else -1.0
		var new_best: bool = i < main.run_new_best.size() and main.run_new_best[i]
		_cell(cx - 220, row_y, main.level_name(i), 22, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		_cell(cx + 80, row_y, main.format_time(run_t), 22, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		_cell(cx + 220, row_y, main.format_time(main.best_time(i)), 22, Color("ffe27a") if new_best else Color("bff3ff"), HORIZONTAL_ALIGNMENT_RIGHT)
	var total_y := y + 28.0 * (n + 1) + 8.0
	draw_line(Vector2(cx - 220, total_y - 24), Vector2(cx + 220, total_y - 24), Color(1, 1, 1, 0.3), 1.0)
	_cell(cx - 220, total_y, "Total", 22, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	_cell(cx + 80, total_y, main.format_time(main.run_total()), 22, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)


# A table cell: LEFT draws from x, RIGHT ends at x.
func _cell(x: float, y: float, text: String, size: int, col: Color, align: HorizontalAlignment) -> void:
	var w := 300.0
	var pos := Vector2(x if align == HORIZONTAL_ALIGNMENT_LEFT else x - w, y)
	draw_string_outline(font, pos, text, align, w, size, 6, Color(0.05, 0.03, 0.1, 0.8))
	draw_string(font, pos, text, align, w, size, col)

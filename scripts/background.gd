extends Node2D
## Screen-space backdrop. Every theme shares music staves and notes that pulse on
## the beat; each level picks a theme with its "bg" key and adds a small layer of its own.
## Keep it all faint: platforms and the ice cube must stay the most readable things.

## clear: background colour, ink: staves, notes and metronome.
const THEMES := {
	"hall": {clear = Color("17122b"), ink = Color(1, 1, 1)},
	"syncopation": {clear = Color("0e1430"), ink = Color(0.85, 0.9, 1.0)},
	"fortissimo": {clear = Color("1c0c14"), ink = Color(1.0, 0.82, 0.72)},
	"dacapo": {clear = Color("0b1d24"), ink = Color(0.8, 1.0, 0.96)},
	"accelerando": {clear = Color("201420"), ink = Color(1.0, 0.92, 0.78)},
	"finale": {clear = Color("1a0f22"), ink = Color(1.0, 0.9, 0.8)},
}

var main

var _theme := ""
var _t := 0.0 # seconds, for slow drifts (embers)
var _streak := 0.0 # accumulated streak travel in pixels; its speed follows the tempo


func _process(delta: float) -> void:
	var theme := _current_theme()
	if theme != _theme:
		_theme = theme
		RenderingServer.set_default_clear_color(THEMES[theme].clear)
	_t += delta
	_streak += delta * _bpm() / 60.0 * 260.0
	queue_redraw()


func _current_theme() -> String:
	var playing: bool = main.is_playing()
	if not playing: # menu screens and the end screen
		return "hall"
	var lvl: Dictionary = main.level
	var theme: String = str(lvl.get("bg", "hall"))
	return theme if THEMES.has(theme) else "hall"


func _bpm() -> float:
	var b: Variant = main.get("bpm")
	return float(b) if b != null else 100.0


func _draw() -> void:
	if _theme == "":
		return
	var vp := get_viewport_rect().size
	var cam: Vector2 = main.camera.get_screen_center_position()
	var beat: int = main.beat
	var phase: float = main.beat_phase
	var pulse := pow(1.0 - phase, 3.0)
	var th: Dictionary = THEMES[_theme]
	var ink: Color = th.ink

	match _theme:
		"syncopation":
			_draw_syncopation(vp, pulse)
		"fortissimo":
			_draw_fortissimo(vp, pulse)
		"dacapo":
			_draw_dacapo(vp, cam)
		"accelerando":
			_draw_accelerando(vp, cam)
		"finale":
			_draw_finale(vp, pulse)

	# The corner metronome; in Accelerando it has come loose and become the pendulums.
	if _theme != "accelerando":
		_draw_metronome(vp, pulse, ink)

	# Staves drift with a little parallax.
	for st in 3:
		var y0 := fposmod(st * 260.0 - cam.y * 0.1, vp.y + 200.0) - 100.0
		for l in 5:
			draw_line(Vector2(0, y0 + l * 16.0), Vector2(vp.x, y0 + l * 16.0), Color(ink, 0.06), 2.0)

	# Floating notes that throb with the beat.
	for i in 18:
		var x := fposmod(i * 211.0 - cam.x * 0.25, vp.x + 120.0) - 60.0
		var y := fposmod(i * 137.0 - cam.y * 0.2, vp.y) + sin(i + beat * 0.5) * 6.0
		var s := 1.0 + 0.35 * pulse * float((i + beat) % 3 == 0)
		var col := Color(ink, 0.1)
		draw_circle(Vector2(x, y), 7.0 * s, col)
		draw_line(Vector2(x + 6.0 * s, y), Vector2(x + 6.0 * s, y - 26.0 * s), col, 2.0)


# A small metronome in the top-right corner, clear of the play area. It swings to an
# extreme on every tick.
func _draw_metronome(vp: Vector2, pulse: float, ink: Color) -> void:
	var k := 0.32
	var base := Vector2(vp.x - 96.0, 300.0)
	draw_colored_polygon(PackedVector2Array([
		base + Vector2(-170, 0) * k, base + Vector2(170, 0) * k, base + Vector2(60, -560) * k, base + Vector2(-60, -560) * k
	]), Color(ink, 0.07))
	var swing: float = main.swing()
	var angle := swing * 0.5
	var pivot := base + Vector2(0, -70) * k
	var dir := Vector2(sin(angle), -cos(angle))
	draw_line(pivot, pivot + dir * 520.0 * k, Color(ink, 0.22), 3.0)
	draw_circle(pivot + dir * 330.0 * k, 9.0, Color(ink, 0.2 + 0.15 * pulse))


# A vertical band fading from `top` colour to `bottom` colour.
func _draw_band(y0: float, y1: float, w: float, top: Color, bottom: Color) -> void:
	draw_polygon(
		PackedVector2Array([Vector2(0, y0), Vector2(w, y0), Vector2(w, y1), Vector2(0, y1)]),
		PackedColorArray([top, top, bottom, bottom]))


# II: soft, desaturated stage-light washes from the rafters, leaning left then right on
# alternate beats.
func _draw_syncopation(vp: Vector2, pulse: float) -> void:
	var swing: float = main.swing()
	var lit := Color(0.72, 0.76, 0.92)
	for side in 2:
		var w := 0.5 + 0.5 * swing * (1.0 if side == 0 else -1.0)
		var a := (0.03 + 0.015 * pulse) * w
		var sx := vp.x * (0.25 if side == 0 else 0.75)
		var reach := vp.x * (0.12 if side == 0 else -0.12)
		var top := Color(lit, a * 1.6)
		var bottom := Color(lit, 0.0)
		draw_polygon(PackedVector2Array([
			Vector2(sx - 30.0, -10.0), Vector2(sx + 30.0, -10.0),
			Vector2(sx + reach + 260.0, vp.y), Vector2(sx + reach - 260.0, vp.y)
		]), PackedColorArray([top, top, bottom, bottom]))
		draw_circle(Vector2(sx, -20.0), 46.0, Color(lit, a * 2.0))


# III: a deep stage glow rising from below and slow embers drifting up through it.
func _draw_fortissimo(vp: Vector2, pulse: float) -> void:
	_draw_band(vp.y * 0.45, vp.y, vp.x, Color(0.9, 0.25, 0.06, 0.0), Color(0.9, 0.28, 0.06, 0.16 + 0.03 * pulse))
	for i in 34:
		var speed := 18.0 + float(i % 5) * 7.0
		var rise := fposmod(_t * speed + i * 97.0, vp.y + 60.0)
		var y := vp.y + 30.0 - rise
		var x := fposmod(i * 173.0, vp.x) + sin(_t * 0.6 + i * 1.7) * 18.0
		var life := rise / (vp.y + 60.0)
		var a := 0.32 * (1.0 - life) * (0.7 + 0.3 * sin(_t * 3.0 + i))
		draw_circle(Vector2(x, y), 1.6 + float(i % 3) * 0.6, Color(1.0, 0.6, 0.25, a))


# IV: faint organ pipes and repeat signs that slide down as you climb.
func _draw_dacapo(vp: Vector2, cam: Vector2) -> void:
	var col := Color(0.6, 0.95, 0.9)
	# Pipes stand on a floor that drops away as the camera rises.
	var floor_y := vp.y + 140.0 - (cam.y - 400.0) * 0.3
	var n := 15
	var pw := 34.0
	var gap := 12.0
	var x0 := vp.x * 0.5 - (n * (pw + gap) - gap) * 0.5
	for i in n:
		var c := absf(float(i) - (n - 1) * 0.5) # 0 in the middle
		var h := 560.0 - c * 38.0 + float(i % 2) * 40.0
		var x := x0 + i * (pw + gap)
		var top := floor_y - h
		draw_rect(Rect2(x, top, pw, h), Color(col, 0.035))
		draw_rect(Rect2(x + 4.0, top, 4.0, h), Color(col, 0.03))
		# The pipe's mouth: a small dark notch a third of the way up.
		var my := floor_y - h * 0.3
		draw_colored_polygon(PackedVector2Array([
			Vector2(x + 6.0, my), Vector2(x + pw - 6.0, my), Vector2(x + pw * 0.5, my - 14.0)
		]), Color(0, 0, 0, 0.12))
	# Repeat signs (thick bar, thin bar, two dots) tile up both edges with more parallax.
	for side in 2:
		var x := 70.0 if side == 0 else vp.x - 70.0
		var flip := 1.0 if side == 0 else -1.0
		for j in 3:
			var y := fposmod(j * 340.0 - cam.y * 0.35 + side * 170.0, 1020.0) - 150.0
			var c2 := Color(col, 0.07)
			if side == 1:
				c2.a *= clampf((y - 300.0) / 80.0, 0.0, 1.0) # fade out under the corner metronome
			draw_rect(Rect2(x - 8.0, y, 16.0, 150.0), c2)
			draw_rect(Rect2(x + 16.0 * flip - 2.0, y, 4.0, 150.0), c2)
			draw_circle(Vector2(x + 34.0 * flip, y + 52.0), 7.0, c2)
			draw_circle(Vector2(x + 34.0 * flip, y + 98.0), 7.0, c2)


# V: a brass dusk with speed streaks that rush past faster as the tempo rises. No
# metronome: it came loose and became the pendulums.
func _draw_accelerando(vp: Vector2, cam: Vector2) -> void:
	_draw_band(vp.y * 0.35, vp.y, vp.x, Color(0.85, 0.55, 0.2, 0.0), Color(0.95, 0.6, 0.2, 0.16))
	var speed := clampf((_bpm() - 100.0) / 40.0, 0.0, 1.0)
	var col := Color(1.0, 0.86, 0.6)
	for i in 18:
		var ln := 100.0 + float(i % 4) * 50.0 + speed * 90.0
		var lane := float(i * 7 % 18) / 18.0
		var y := fposmod(lane * (vp.y + 100.0) - cam.y * 0.15, vp.y + 100.0) - 50.0
		var travel := _streak * (0.6 + float(i % 3) * 0.25) + i * 331.0 + cam.x * 0.3
		var x := vp.x + ln - fposmod(travel, vp.x + ln * 2.0)
		# Bright head on the left, fading tail streaming out behind to the right.
		var head := Color(col, 0.13 + 0.07 * speed)
		var tail := Color(col, 0.0)
		draw_polygon(PackedVector2Array([
			Vector2(x, y - 2.0), Vector2(x + ln, y - 0.5), Vector2(x + ln, y + 0.5), Vector2(x, y + 2.0)
		]), PackedColorArray([head, tail, tail, head]))


# VI: the last curtain call. A crimson valance along the top, warm footlights that
# swell on the beat, and slow gold confetti drifting down.
func _draw_finale(vp: Vector2, pulse: float) -> void:
	_draw_band(vp.y * 0.55, vp.y, vp.x, Color(1.0, 0.72, 0.3, 0.0), Color(1.0, 0.7, 0.3, 0.1 + 0.03 * pulse))
	# Valance: a strip with scalloped swags hanging below it.
	var red := Color(0.75, 0.12, 0.2, 0.16)
	draw_rect(Rect2(0, 0, vp.x, 18.0), red)
	var swag := 160.0
	for i in ceili(vp.x / swag) + 1:
		var x0 := i * swag
		var pts := PackedVector2Array([Vector2(x0, 17.0)])
		for k in 9:
			var u := float(k) / 8.0
			pts.append(Vector2(x0 + u * swag, 18.0 + sin(u * PI) * 26.0))
		draw_colored_polygon(pts, red)
		# A small tassel where two swags meet.
		draw_line(Vector2(x0, 18.0), Vector2(x0, 40.0), Color(1.0, 0.8, 0.4, 0.14), 2.0)
		draw_circle(Vector2(x0, 42.0), 3.0, Color(1.0, 0.8, 0.4, 0.14))
	# Confetti: small gold flecks falling and turning; each has a fixed lane and speed.
	for i in 28:
		var speed := 22.0 + float(i % 4) * 9.0
		var fall := fposmod(_t * speed + i * 131.0, vp.y + 40.0)
		var y := fall - 20.0
		var x := fposmod(i * 193.0, vp.x) + sin(_t * 0.8 + i * 2.3) * 22.0
		var turn := absf(sin(_t * 2.0 + i)) # 0..1, the fleck's apparent width as it spins
		var a := 0.22 * clampf(fall / 80.0, 0.0, 1.0) # fade in under the valance
		var col := Color(1.0, 0.82, 0.4, a) if i % 3 != 0 else Color(1.0, 0.55, 0.6, a)
		draw_rect(Rect2(x - 3.0 * turn, y - 2.0, 6.0 * turn + 1.0, 4.0), col)

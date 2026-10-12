extends Area2D
## Score note pickup: an eighth, quarter, half or whole note worth 10 / 25 / 50 / 100.
## Touch it to collect (see main.collect_note); it pops and plays a pitched chime.
## Drawn as the real notation glyph in warm cream with a dark ink edge, so it reads on
## both the dark hall and the cream piano keys, and never sits on a slab like beat blocks.

const PlayerScript := preload("res://scripts/player.gd")
const POINTS := {"eighth": 10, "quarter": 25, "half": 50, "whole": 100}
const SCALE := {"eighth": 1.35, "quarter": 1.42, "half": 1.5, "whole": 1.65}
const CREAM := Color("fff4dc")
const GOLD := Color("ffd76a")
const INK := Color("1a1424")
const POP_TIME := 0.3
const HEAD_TILT := -0.38 # radians; note heads lean up to the right

var main
var type := "eighth"
var _pop := -1.0 # >= 0 once collected: time since the pickup


func setup(m, pos: Vector2, t: String) -> void:
	main = m
	position = pos
	type = t


func _ready() -> void:
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 13.0 * float(SCALE[type])
	cs.shape = c
	add_child(cs)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body is PlayerScript and _pop < 0.0 and main.collect_note(type):
		_pop = 0.0
		set_deferred("monitoring", false)


func _process(delta: float) -> void:
	if _pop >= 0.0:
		_pop += delta
		if _pop >= POP_TIME:
			queue_free()
	queue_redraw()


## 0 (eighth) .. 1 (whole): drives glow strength and warmth.
func _rank() -> float:
	return clampf((float(POINTS[type]) - 10.0) / 90.0, 0.0, 1.0)


func _draw() -> void:
	var s: float = SCALE[type]
	var glow_col := CREAM.lerp(GOLD, _rank())
	if _pop >= 0.0:
		# Pop: the glyph swells and fades while glints fly out.
		var u := _pop / POP_TIME
		var a := 1.0 - u
		draw_circle(Vector2.ZERO, (16.0 + 22.0 * u) * s, Color(glow_col, 0.18 * a))
		var n := 4 + int(_rank() * 3.0)
		for i in n:
			var dir := Vector2.from_angle(TAU * i / n + 0.4)
			_glint(dir * (12.0 + 30.0 * u) * s, 4.0 * a + 1.0, Color(glow_col, a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * (1.0 + 0.6 * u))
		_draw_glyph(s, a)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return

	# Bob in time: a full up-and-down every two beats, at an extreme on each tick,
	# with a slight sway like it's tapping along.
	var b: float = main.beat + main.beat_phase
	var y := 3.0 * cos(PI * b)
	var sway := 0.07 * sin(PI * b)
	# Soft glow, stronger and warmer for higher values.
	var k := _rank()
	# Stacked faint discs fake a radial falloff, so it reads as light, not a grey plate.
	for i in 4:
		draw_circle(Vector2(0, y), (19.0 + 6.0 * k) * s * (1.0 - 0.2 * i), Color(glow_col, 0.025 + 0.035 * k))
	if type == "whole":
		# A warm gold glow that breathes with the beat (a soft fill, not a ring, so the
		# oval doesn't read as an eye).
		var breathe: float = 1.0 - main.beat_phase
		draw_circle(Vector2(0, y), 15.0 * s, Color(GOLD, 0.06 + 0.06 * breathe))
	draw_set_transform(Vector2(0, y), sway, Vector2.ONE)
	_draw_glyph(s, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if type == "whole":
		# A small glint that blinks on the downbeat.
		var g: float = clampf(1.0 - main.beat_phase * 2.5, 0.0, 1.0) if main.beat % 4 == 0 else 0.0
		_glint(Vector2(9.0, y - 7.0) * s, 5.0 * g, Color(1, 1, 1, g))


# The notation glyph around the origin, bounding box roughly centred. `a` = alpha.
func _draw_glyph(s: float, a: float) -> void:
	var ink := Color(INK, 0.85 * a)
	var col := Color(CREAM, a)
	if type == "whole":
		# Wide gold-cream oval with a narrow, steeply slanted opening, no stem: thick
		# sides and a slim slot read as a whole note, not an eye.
		var outer := Vector2(11.0, 6.6) * s
		var hole := Vector2(2.4, 4.6) * s
		var gold := Color(CREAM.lerp(GOLD, 0.45), a)
		_ring(Vector2.ZERO, outer + Vector2(1.8, 1.8), 0.0, hole - Vector2(1.0, 1.0), 0.95, ink)
		_ring(Vector2.ZERO, outer, 0.0, hole, 0.95, gold)
		return

	var head_c := Vector2(-3.0, 9.0) * s
	var head := Vector2(6.6, 4.6) * s
	var stem_x := head_c.x + 5.6 * s
	var stem_bot := head_c.y - 1.5 * s
	var stem_top := -17.0 * s
	var w := 2.2 * s
	# Ink edges first, then the cream glyph on top.
	var hole := Vector2(4.6, 2.3) * s
	if type == "half":
		_ring(head_c, head + Vector2(1.8, 1.8), HEAD_TILT, hole - Vector2(1.2, 1.2), HEAD_TILT - 0.25, ink)
	else:
		_ellipse(head_c, head + Vector2(1.8, 1.8), HEAD_TILT, ink)
	draw_line(Vector2(stem_x, stem_bot), Vector2(stem_x, stem_top - 1.6), ink, w + 3.2)
	var flag := PackedVector2Array()
	if type == "eighth":
		flag = _flag(Vector2(stem_x, stem_top), s)
		draw_polyline(flag + PackedVector2Array([flag[0]]), ink, 3.2, true)
	if type == "half":
		_ring(head_c, head, HEAD_TILT, hole, HEAD_TILT - 0.25, col)
	else:
		_ellipse(head_c, head, HEAD_TILT, col)
	draw_line(Vector2(stem_x, stem_bot), Vector2(stem_x, stem_top), col, w)
	if type == "eighth":
		draw_colored_polygon(flag, col)


# An eighth-note flag: a curved tail from the stem top sweeping down to the right.
func _flag(top: Vector2, s: float) -> PackedVector2Array:
	return PackedVector2Array([
		top + Vector2(-1.1, 0.0) * s,
		top + Vector2(3.5, 3.5) * s,
		top + Vector2(8.0, 8.5) * s,
		top + Vector2(8.5, 14.0) * s,
		top + Vector2(6.5, 19.0) * s,
		top + Vector2(6.8, 13.5) * s,
		top + Vector2(4.0, 9.5) * s,
		top + Vector2(-1.1, 7.0) * s,
	])


# Points sampled by polar angle (not the ellipse parameter), so two ellipses with
# different tilts share directions and the ring quads between them stay simple.
func _ellipse_points(c: Vector2, r: Vector2, rot: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var phi := TAU * i / n
		var cx := cos(phi - rot) / r.x
		var sy := sin(phi - rot) / r.y
		pts.append(c + Vector2.from_angle(phi) / sqrt(cx * cx + sy * sy))
	return pts


func _ellipse(c: Vector2, r: Vector2, rot: float, col: Color) -> void:
	draw_colored_polygon(_ellipse_points(c, r, rot, 32), col)


# A filled ellipse with an elliptical hole (hollow note head), drawn as quads.
func _ring(c: Vector2, outer: Vector2, outer_rot: float, inner: Vector2, inner_rot: float, col: Color) -> void:
	var n := 32
	var o := _ellipse_points(c, outer, outer_rot, n)
	var h := _ellipse_points(c, inner, inner_rot, n)
	for i in n:
		var j := (i + 1) % n
		draw_colored_polygon(PackedVector2Array([o[i], o[j], h[j], h[i]]), col)


func _glint(p: Vector2, r: float, col: Color) -> void:
	if r <= 0.1:
		return
	draw_line(p - Vector2(r, 0), p + Vector2(r, 0), col, 1.5)
	draw_line(p - Vector2(0, r), p + Vector2(0, r), col, 1.5)

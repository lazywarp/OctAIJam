extends StaticBody2D
## Piano-key ground, or note blocks that only exist on alternating bars.

enum Kind { SOLID, BEAT_A, BEAT_B }

const WHITE_KEY_W := 40.0
const BLACK_KEYS := [0, 1, 3, 4, 5] # positions in a 7-key octave followed by a black key
const COL_A := Color("38e0ff")
const COL_B := Color("ff4fd8")
const INK := Color("1a1424")

var main
var kind: int = Kind.SOLID
var size := Vector2(100, 24)
var active := true

var _shape: CollisionShape2D
var _box := StyleBoxFlat.new()


func setup(m, k: int, rect: Rect2) -> void:
	main = m
	kind = k
	size = rect.size
	position = rect.get_center()


func _ready() -> void:
	_shape = CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = size
	_shape.shape = r
	_shape.one_way_collision = kind != Kind.SOLID or size.y <= 40.0
	add_child(_shape)
	_box.set_corner_radius_all(8)
	_box.set_border_width_all(2)
	set_process(kind != Kind.SOLID)
	if kind != Kind.SOLID:
		_update_active(true)


func _process(_delta: float) -> void:
	_update_active(false)
	queue_redraw()


func _update_active(force: bool) -> void:
	var group := 0 if kind == Kind.BEAT_A else 1
	var now: bool = main.beat_group_active(group)
	if now != active or force:
		active = now
		_shape.set_deferred("disabled", not active)


func _draw() -> void:
	var r := Rect2(-size * 0.5, size)
	if kind == Kind.SOLID:
		_draw_keys(r)
		return

	var col := COL_A if kind == Kind.BEAT_A else COL_B
	var group := 0 if kind == Kind.BEAT_A else 1
	var sw: float = main.switch_phase
	var own_bar: bool = main.beat_group_on(group)
	var grace: float = main.SWITCH_GRACE
	var blink := own_bar and sw > grace and fmod(sw * 20.0, 2.0) < 1.0
	if active and own_bar:
		# Current bar: solid, blinking as it is about to leave.
		_box.bg_color = Color(col, 0.55 if blink else 0.95)
		_box.border_color = Color.WHITE
		draw_style_box(_box, r)
		_draw_note(r.get_center(), Color(INK, 0.7))
	elif active:
		# Incoming during the grace overlap: already solid, fading in.
		var k := clampf((sw - grace) / (1.0 - grace), 0.0, 1.0)
		_box.bg_color = Color(col, lerpf(0.45, 0.9, k))
		_box.border_color = Color.WHITE
		draw_style_box(_box, r)
		_draw_note(r.get_center(), Color(INK, 0.5))
	else:
		_box.bg_color = Color(col, 0.08)
		_box.border_color = Color(col, 0.5)
		draw_style_box(_box, r)


func _draw_keys(r: Rect2) -> void:
	draw_rect(r, Color("efe9dc"))
	var n := ceili(r.size.x / WHITE_KEY_W)
	var key_h := minf(r.size.y * 0.6, 110.0)
	for i in n:
		var x := r.position.x + i * WHITE_KEY_W
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(0, 0, 0, 0.3), 2.0)
	for i in n:
		if (i % 7) in BLACK_KEYS:
			var bx := r.position.x + (i + 1) * WHITE_KEY_W - 12.0
			if bx + 24.0 < r.end.x:
				draw_rect(Rect2(bx, r.position.y, 24.0, key_h), INK)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 4.0)), Color(1, 1, 1, 0.7))
	draw_rect(r, INK, false, 3.0)


func _draw_note(c: Vector2, col: Color) -> void:
	draw_circle(c + Vector2(-3, 4), 5.0, col)
	draw_line(c + Vector2(1.5, 4), c + Vector2(1.5, -11), col, 2.0)
	draw_line(c + Vector2(1.5, -11), c + Vector2(8, -5), col, 2.0)

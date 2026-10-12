extends Area2D
## Refreezer pickup: a snowflake. Touch it to hold one free save; the first time
## stillness would melt you, it refreezes the cube instead (see main.gd).
## You can hold only one, so a second flake waits until the first is used.

const PlayerScript := preload("res://scripts/player.gd")
const ICE := Color("e8fbff")
const BLUE := Color("8fe3ff")
const RADIUS := 13.0
const BURST_TIME := 0.45

var main
var _t := 0.0
var _burst := -1.0 # >= 0 once collected: time since the pickup


func setup(m, pos: Vector2) -> void:
	main = m
	position = pos


func _ready() -> void:
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = RADIUS + 5.0
	cs.shape = c
	add_child(cs)
	body_entered.connect(_on_body_entered)
	# Each flake starts at its own point in the bob/spin, but deterministically.
	_t = fposmod(position.x * 0.013 + position.y * 0.007, 10.0)


func _on_body_entered(body: Node2D) -> void:
	if body is PlayerScript:
		_try_collect()


# Collecting can fail (already holding one), so keep trying while the cube overlaps.
func _physics_process(_delta: float) -> void:
	if _burst < 0.0 and is_instance_valid(main.player) and overlaps_body(main.player):
		_try_collect()


func _try_collect() -> void:
	if _burst >= 0.0:
		return
	if main.collect_snow():
		_burst = 0.0
		set_deferred("monitoring", false)


func _process(delta: float) -> void:
	_t += delta
	if _burst >= 0.0:
		_burst += delta
		if _burst >= BURST_TIME:
			queue_free()
	queue_redraw()


func _draw() -> void:
	if _burst >= 0.0:
		# Little burst: the flake swells and fades while six shards fly out.
		var u := _burst / BURST_TIME
		var a := 1.0 - u
		draw_arc(Vector2.ZERO, RADIUS + 26.0 * u, 0.0, TAU, 32, Color(BLUE, a * 0.8), 2.0)
		for i in 6:
			var dir := Vector2.from_angle(TAU * i / 6.0 + _t)
			draw_circle(dir * (RADIUS + 34.0 * u), 2.5 * a, Color(ICE, a))
		draw_flake(self, Vector2.ZERO, RADIUS * (1.0 + 0.5 * u), _t * 0.6, Color(ICE, a))
		return

	var c := Vector2(0, sin(_t * 2.2) * 4.0)
	draw_circle(c, RADIUS + 9.0 + 2.0 * sin(_t * 3.0), Color(BLUE, 0.12))
	draw_flake(self, c, RADIUS, _t * 0.6, ICE)
	# Soft sparkle: a small four-point glint that hops between arm tips.
	var tip := floori(_t * 1.5) % 6
	var glow := sin(fposmod(_t * 1.5, 1.0) * PI)
	var sp := c + Vector2.from_angle(_t * 0.6 + TAU * tip / 6.0) * RADIUS
	var s := 5.0 * glow
	draw_line(sp - Vector2(s, 0), sp + Vector2(s, 0), Color(1, 1, 1, glow), 1.5)
	draw_line(sp - Vector2(0, s), sp + Vector2(0, s), Color(1, 1, 1, glow), 1.5)


## A six-armed snowflake with a pair of barbs on each arm. Shared with the HUD icon.
static func draw_flake(ci: CanvasItem, c: Vector2, r: float, rot: float, col: Color) -> void:
	var w := maxf(r * 0.16, 1.5)
	var barb := Color(col.lerp(BLUE, 0.35), col.a)
	for i in 6:
		var dir := Vector2.from_angle(rot + TAU * i / 6.0)
		var tip := c + dir * r
		ci.draw_line(c, tip, col, w)
		var mid := c + dir * r * 0.55
		var b := r * 0.32
		ci.draw_line(mid, mid + dir.rotated(0.8) * b, barb, w * 0.8)
		ci.draw_line(mid, mid + dir.rotated(-0.8) * b, barb, w * 0.8)
	ci.draw_circle(c, r * 0.2, col)

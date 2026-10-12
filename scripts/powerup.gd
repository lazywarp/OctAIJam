extends Area2D
## Power-up pickup: bobs and glows in its kind's colours (see powerups.gd). Touch it and
## main.gd activates the effect; it bursts and plays the kind's collect sound.
## Collecting can be refused (e.g. a refreezer while one is held); then it stays put.

const PlayerScript := preload("res://scripts/player.gd")
const Powerups := preload("res://scripts/powerups.gd")
const RADIUS := 13.0
const BURST_TIME := 0.45

var main
var kind := ""
var _t := 0.0
var _burst := -1.0 # >= 0 once collected: time since the pickup


func setup(m, pos: Vector2, k: String) -> void:
	main = m
	position = pos
	kind = k


func _ready() -> void:
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = RADIUS + 5.0
	cs.shape = c
	add_child(cs)
	body_entered.connect(_on_body_entered)
	# Each pickup starts at its own point in the bob/spin, but deterministically.
	_t = fposmod(position.x * 0.013 + position.y * 0.007, 10.0)


func _on_body_entered(body: Node2D) -> void:
	if body is PlayerScript:
		_try_collect()


# Collecting can fail, so keep trying while the cube overlaps.
func _physics_process(_delta: float) -> void:
	if _burst < 0.0 and is_instance_valid(main.player) and overlaps_body(main.player):
		_try_collect()


func _try_collect() -> void:
	if _burst >= 0.0:
		return
	if main.collect_power(kind):
		_burst = 0.0
		set_deferred("monitoring", false)
		var snd: Array = Powerups.def(kind).get("sound", ["chime", 1567.98, -14.0])
		main.synth.play(str(snd[0]), float(snd[1]), float(snd[2]))


func _process(delta: float) -> void:
	_t += delta
	if _burst >= 0.0:
		_burst += delta
		if _burst >= BURST_TIME:
			queue_free()
	queue_redraw()


func _draw() -> void:
	var col := Powerups.color(kind)
	var acc := Powerups.accent(kind)
	if _burst >= 0.0:
		# Little burst: the icon swells and fades while six shards fly out.
		var u := _burst / BURST_TIME
		var a := 1.0 - u
		draw_arc(Vector2.ZERO, RADIUS + 26.0 * u, 0.0, TAU, 32, Color(acc, a * 0.8), 2.0)
		for i in 6:
			var dir := Vector2.from_angle(TAU * i / 6.0 + _t)
			draw_circle(dir * (RADIUS + 34.0 * u), 2.5 * a, Color(col, a))
		Powerups.draw_icon(self, kind, Vector2.ZERO, RADIUS * (1.0 + 0.5 * u), _t * 0.6, Color(col, a))
		return

	var c := Vector2(0, sin(_t * 2.2) * 4.0)
	# Soft glow: two light rings so it reads as a glow, not a dark disc.
	var pulse := 2.0 * sin(_t * 3.0)
	draw_circle(c, RADIUS + 12.0 + pulse, Color(col, 0.08))
	draw_circle(c, RADIUS + 5.0 + pulse * 0.5, Color(col, 0.12))
	Powerups.draw_icon(self, kind, c, RADIUS, _t * 0.6, col)
	# Soft sparkle: a small four-point glint that hops around the rim.
	var tip := floori(_t * 1.5) % 6
	var glow := sin(fposmod(_t * 1.5, 1.0) * PI)
	var sp := c + Vector2.from_angle(_t * 0.6 + TAU * tip / 6.0) * RADIUS
	var s := 5.0 * glow
	draw_line(sp - Vector2(s, 0), sp + Vector2(s, 0), Color(1, 1, 1, glow), 1.5)
	draw_line(sp - Vector2(0, s), sp + Vector2(0, s), Color(1, 1, 1, glow), 1.5)

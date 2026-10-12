extends RefCounted
## Power-up registry: one entry per kind. main.gd tracks the active effects, powerup.gd is
## the pickup, hud.gd shows the icons. Adding a kind means adding one entry to _builtin()
## (plus whatever the effect itself changes in main.gd / player.gd).
##
## Each kind is a Dictionary; everything except "name" is optional:
##   name: String          display name
##   color: Color          main colour (icon, glow, shards)
##   accent: Color         second colour (burst ring, timer bar)
##   icon: Callable        func(ci: CanvasItem, c: Vector2, r: float, rot: float, col: Color)
##                         draws the icon centred on c; the pickup and the HUD both use it
##   duration: float       seconds; 0 = until used (see main.use_power)
##   max: int              charges it can hold (default 1)
##   refresh: bool         collecting it while at max charges restarts the timer and takes
##                         the pickup (default true); false leaves the pickup in the world
##   sound: Array          collect sound for synth.play: [kind, hz, volume_db]
## Hooks (all optional; m is main.gd, fx the effect: {kind, time_left, duration, charges}):
##   on_activate(m, fx)            first collected (not on refresh or extra charges)
##   on_tick(m, fx, delta)         every frame while active and playing
##   on_expire(m, fx, reason)      ended: reason is "timeout", "used" or "cleared" (level load)
##   on_melt(m, fx) -> bool        stillness is about to melt the cube; return true to
##                                 cancel the melt (the hook must reset the stillness), which
##                                 spends one charge

const ICE := Color("e8fbff")
const BLUE := Color("8fe3ff")
const MINT := Color("5ef0a8") # Grace Note
const MINT_LIGHT := Color("d2ffe6")
const LAVENDER := Color("b996ff") # Fermata
const LAVENDER_LIGHT := Color("ece2ff")
const LIME := Color("d8ef5e") # Ritardando
const LIME_LIGHT := Color("f6ffc8")
const GRACE_TIME := 10.0
const FERMATA_TIME := 5.0
const RIT_TIME := 8.0
const RIT_SCALE := 0.75 # Ritardando's tempo multiplier
const RIT_IN_BEATS := 1.0 # eases down over a beat...
const RIT_OUT_BEATS := 4.0 # ...and back up over a bar once it ends

static var _kinds: Dictionary = _builtin()


static func _builtin() -> Dictionary:
	return {
		# Refreezer: held until used, max one, cancels the next stillness melt.
		"refreeze": {
			"name": "Refreezer",
			"color": ICE,
			"accent": BLUE,
			"icon": draw_flake,
			"duration": 0.0,
			"max": 1,
			"refresh": false, # a second flake waits in the world until the first is used
			"sound": ["chime", 1567.98, -14.0], # G6
			"on_melt": func(m, _fx: Dictionary) -> bool:
				m.refreeze()
				return true,
		},
		# Grace Note: one extra jump in mid-air (not during coyote time), until used or 10 s.
		# Landing doesn't refill it. player.gd asks through its air_jump callable.
		"grace": {
			"name": "Grace Note",
			"color": MINT,
			"accent": MINT_LIGHT,
			"icon": draw_grace,
			"duration": GRACE_TIME,
			"max": 1,
			"sound": ["grace", 1567.98, -11.0], # G6 flicked from A6
			"on_activate": _grace_activate,
			"on_expire": _grace_expire,
		},
		# Fermata: both beat-block colours hold solid for 5 s (main.beat_hold; platform.gd
		# blinks the ones about to drop in the last second). The beat clock keeps running, so
		# alternation resumes from the current beat.
		"fermata": {
			"name": "Fermata",
			"color": LAVENDER,
			"accent": LAVENDER_LIGHT,
			"icon": draw_fermata,
			"duration": FERMATA_TIME,
			"sound": ["fermata", 783.99, -12.0], # G5
			"on_activate": func(m, fx: Dictionary) -> void:
				m.beat_hold = float(fx["time_left"]),
			"on_tick": func(m, fx: Dictionary, _delta: float) -> void:
				m.beat_hold = float(fx["time_left"]),
			"on_expire": func(m, _fx: Dictionary, _reason: String) -> void:
				m.beat_hold = 0.0,
		},
		# Ritardando: multiplies the level's tempo by 0.75 for 8 s. Tempo zones still apply
		# underneath (scaled), and the level tempo is full again once it eases back.
		"ritardando": {
			"name": "Ritardando",
			"color": LIME,
			"accent": LIME_LIGHT,
			"icon": draw_rit,
			"duration": RIT_TIME,
			"sound": ["ritard", 1318.51, -12.0], # E6, falling and slowing
			"on_activate": func(m, _fx: Dictionary) -> void:
				m.scale_tempo(RIT_SCALE, RIT_IN_BEATS),
			"on_expire": func(m, _fx: Dictionary, reason: String) -> void:
				m.scale_tempo(1.0, 0.0 if reason == "cleared" else RIT_OUT_BEATS),
		},
	}


static func _grace_activate(m, _fx: Dictionary) -> void:
	m.player.air_jump = _grace_jump.bind(m)
	m.player.air_jump_color = MINT


static func _grace_expire(m, _fx: Dictionary, _reason: String) -> void:
	if is_instance_valid(m.player):
		m.player.air_jump = Callable()


# The cube asks for a mid-air jump: spend the charge and flick a grace note into a chord tone.
static func _grace_jump(m) -> bool:
	if not m.has_power("grace"):
		return false
	m.use_power("grace")
	m.synth.play("grace", m._chord_hz(4), -7.0)
	return true


## Adds or replaces a kind at runtime (tests, mods). Built-in kinds belong in _builtin().
static func register(kind: String, def: Dictionary) -> void:
	_kinds[kind] = def


static func has(kind: String) -> bool:
	return _kinds.has(kind)


static func def(kind: String) -> Dictionary:
	return _kinds.get(kind, {})


static func color(kind: String) -> Color:
	return def(kind).get("color", Color.WHITE)


static func accent(kind: String) -> Color:
	return def(kind).get("accent", color(kind))


static func duration(kind: String) -> float:
	return float(def(kind).get("duration", 0.0))


## Draws the kind's icon; falls back to a plain dot if the kind has no icon drawer.
static func draw_icon(ci: CanvasItem, kind: String, c: Vector2, r: float, rot: float, col: Color) -> void:
	var icon: Callable = def(kind).get("icon", Callable())
	if icon.is_valid():
		icon.call(ci, c, r, rot, col)
	else:
		ci.draw_circle(c, r * 0.6, col)


## A six-armed snowflake with a pair of barbs on each arm (the refreezer icon).
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


## A slashed grace note (acciaccatura): a small eighth note, slashed through stem and flag.
## rot only rocks it a little.
static func draw_grace(ci: CanvasItem, c: Vector2, r: float, rot: float, col: Color) -> void:
	var tilt := sin(rot * 2.0) * 0.12
	var w := maxf(r * 0.15, 1.5)
	var head := c + Vector2(-0.24, 0.56).rotated(tilt) * r
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(head + Vector2(cos(a) * 0.4, sin(a) * 0.28).rotated(tilt - 0.4) * r)
	ci.draw_colored_polygon(pts, col)
	var stem_top := c + Vector2(0.13, -0.86).rotated(tilt) * r
	ci.draw_line(c + Vector2(0.13, 0.48).rotated(tilt) * r, stem_top, col, w)
	ci.draw_polyline(PackedVector2Array([stem_top, c + Vector2(0.5, -0.54).rotated(tilt) * r,
		c + Vector2(0.52, -0.18).rotated(tilt) * r]), col, w)
	ci.draw_line(c + Vector2(-0.4, 0.04).rotated(tilt) * r, c + Vector2(0.62, -0.5).rotated(tilt) * r, col, w)


## The fermata: a crescent arc, thickest at the top, over a dot. It doesn't spin: it holds.
static func draw_fermata(ci: CanvasItem, c: Vector2, r: float, _rot: float, col: Color) -> void:
	var base := c + Vector2(0, r * 0.4)
	var pts := PackedVector2Array()
	for i in 17: # outer edge, left to right over the top
		var a := PI + PI * i / 16.0
		pts.append(base + Vector2(cos(a) * 1.0, sin(a) * 0.96) * r)
	for i in 17: # inner edge back, flatter, so the arc tapers to its tips
		var a := TAU - PI * i / 16.0
		pts.append(base + Vector2(cos(a) * 0.78, sin(a) * 0.6) * r)
	ci.draw_colored_polygon(pts, col)
	ci.draw_circle(base + Vector2(0, -r * 0.14), r * 0.23, col)


## Ritardando: a little metronome whose arm swings slowly, its weight low on the arm.
static func draw_rit(ci: CanvasItem, c: Vector2, r: float, rot: float, col: Color) -> void:
	var w := maxf(r * 0.14, 1.5)
	var body := PackedVector2Array([
		c + Vector2(-0.62, 0.86) * r, c + Vector2(-0.24, -0.78) * r,
		c + Vector2(0.24, -0.78) * r, c + Vector2(0.62, 0.86) * r,
	])
	ci.draw_colored_polygon(body, Color(col, col.a * 0.3))
	body.append(body[0])
	ci.draw_polyline(body, col, w)
	var pivot := c + Vector2(0, 0.58) * r
	var dir := Vector2.UP.rotated(sin(rot * 2.5) * 0.5)
	ci.draw_line(pivot, pivot + dir * r * 1.3, col, w)
	var weight := pivot + dir * r * 0.95
	ci.draw_rect(Rect2(weight - Vector2(0.2, 0.13) * r, Vector2(0.4, 0.26) * r), col)
	ci.draw_line(c + Vector2(-0.5, 0.58) * r, c + Vector2(0.5, 0.58) * r, col, w)

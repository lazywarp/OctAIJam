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
	}


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

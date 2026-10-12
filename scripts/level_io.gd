extends RefCounted
## Level files: converts between the in-game level Dictionaries (see levels.gd) and the
## JSON level format documented in docs/LEVEL_FORMAT.md. Rects become [x, y, w, h],
## points [x, y]; everything else keeps its levels.gd key and shape.
##   to_json_dict(level) / to_json_text(level): in-game Dictionary -> JSON (stable key order).
##   from_json_text(text): JSON -> { ok, level, errors, warnings }. Never crashes: anything
##   wrong comes back as a readable error such as "solid[3]: expected [x, y, w, h], got [1, 2]".
## Reading files from disk is the loader's job (block L2), not this script's.

const BackgroundScript := preload("res://scripts/background.gd")

const FORMAT := 1

## Limits, so a broken or hostile file can't hang the game.
const MAX_TEXT_CHARS := 1000000
const MAX_COORD := 100000.0 # |x|, |y| in world pixels
const MAX_SIZE := 100000.0 # rect width / height
const MAX_LIST := 2000 # items in any one list
const MAX_TOTAL := 8000 # items in all lists together
const MAX_NAME := 64
const MAX_TEXT := 200 # sign text
const MAX_KIND := 32 # power-up kind
const MIN_BPM := 30.0
const MAX_BPM := 400.0
const MAX_SWITCH_BEATS := 16
const MAX_ROD := 2000.0
const MAX_ANGLE := 1.5 # radians, just under 90 degrees
const MAX_BEATS_PER_SIDE := 16.0
const MAX_ERRORS := 30

const NOTE_TYPES := ["eighth", "quarter", "half", "whole"]

## Every key, in the order files are written.
const KEY_ORDER := [
	"format", "name", "bg", "bpm", "switch_beats", "spawn", "goal", "kill_y", "cam_bottom",
	"tempo", "solid", "a", "b", "hot", "lamp", "pend", "snow", "notes", "power", "signs",
]

## List keys and the shape of their items; these are written one item per line.
const LISTS := {
	"tempo": "tempo", "solid": "rect", "a": "rect", "b": "rect", "hot": "rect",
	"lamp": "rect", "pend": "pend", "snow": "point", "notes": "note", "power": "power",
	"signs": "sign",
}


## In-game level -> JSON-ready Dictionary (Vector2 -> [x, y], Rect2 -> [x, y, w, h]).
## Keys are in KEY_ORDER, starting with "format"; unknown keys are left out.
static func to_json_dict(level: Dictionary) -> Dictionary:
	var out := {"format": FORMAT}
	for key: String in KEY_ORDER:
		if key != "format" and level.has(key):
			out[key] = _encode(level[key])
	return out


## In-game level -> pretty JSON text: one key per line, one list item per line.
static func to_json_text(level: Dictionary) -> String:
	var d := to_json_dict(level)
	var keys: Array = d.keys()
	var lines := PackedStringArray()
	for i in keys.size():
		var key: String = keys[i]
		var value: Variant = d[key]
		var comma := "," if i < keys.size() - 1 else ""
		if LISTS.has(key) and value is Array and not (value as Array).is_empty():
			var items: Array = value
			lines.append("\t%s: [" % JSON.stringify(key))
			for j in items.size():
				lines.append("\t\t" + _inline(items[j]) + ("," if j < items.size() - 1 else ""))
			lines.append("\t]" + comma)
		else:
			lines.append("\t%s: %s%s" % [JSON.stringify(key), _inline(value), comma])
	return "{\n" + "\n".join(lines) + "\n}\n"


## JSON text -> { "ok": bool, "level": Dictionary, "errors": Array[String],
## "warnings": Array[String] }. "level" is empty unless ok. Unknown keys are warnings
## (so files from newer versions still load); keys starting with "_" are comments.
static func from_json_text(text: String) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var result := {"ok": false, "level": {}, "errors": errors, "warnings": warnings}
	if text.strip_edges().is_empty():
		errors.append("the file is empty")
		return result
	if text.length() > MAX_TEXT_CHARS:
		errors.append("the file is too large (%d characters, max %d)" % [text.length(), MAX_TEXT_CHARS])
		return result
	var extreme := _extreme_number(text)
	if extreme != "":
		errors.append(extreme)
		return result
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append("invalid JSON at line %d: %s" % [json.get_error_line() + 1, json.get_error_message()])
		return result
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		errors.append("the file must contain one JSON object { ... }, got %s" % _describe(data))
		return result
	var root: Dictionary = data

	if not root.has("format"):
		errors.append("missing \"format\": 1 (the level format version)")
	else:
		var f: Variant = _number(root["format"], "format", 1.0, 1000000.0, errors)
		if f != null:
			if float(f) != floorf(float(f)):
				errors.append("format: expected a whole number, got %s" % _describe(root["format"]))
			elif int(f) > FORMAT:
				errors.append("format: this file uses format %d, but this version of Meltronome reads format %d" % [int(f), FORMAT])
			elif int(f) != FORMAT:
				errors.append("format: unknown format %d (expected %d)" % [int(f), FORMAT])
	for k: Variant in root.keys():
		var key := str(k)
		if not KEY_ORDER.has(key) and not key.begins_with("_"):
			warnings.append("unknown key \"%s\" ignored (made for a newer version?)" % _clip(key, 40))
	for key: String in ["name", "spawn", "goal", "solid"]:
		if not root.has(key):
			errors.append("missing required key \"%s\"" % key)

	var level := {}
	var total := 0
	for key: String in KEY_ORDER:
		if key == "format" or not root.has(key):
			continue
		var v: Variant = root[key]
		var out: Variant = null
		if LISTS.has(key):
			if typeof(v) != TYPE_ARRAY:
				errors.append("%s: expected a list [ ... ], got %s" % [key, _describe(v)])
				continue
			var items: Array = v
			if items.size() > MAX_LIST:
				errors.append("%s: too many items (%d, max %d)" % [key, items.size(), MAX_LIST])
				continue
			total += items.size()
			out = _list(items, key, LISTS[key], errors)
		else:
			out = _single(v, key, errors)
		if out != null:
			level[key] = out
	if total > MAX_TOTAL:
		errors.append("too many items in all lists together (%d, max %d)" % [total, MAX_TOTAL])
	if level.has("solid") and (level["solid"] as Array).is_empty():
		errors.append("solid: needs at least one rect, or there is nothing to stand on")

	if errors.size() > MAX_ERRORS:
		var more := errors.size() - MAX_ERRORS
		errors.resize(MAX_ERRORS)
		errors.append("... and %d more errors" % more)
	if errors.is_empty():
		result["ok"] = true
		result["level"] = level
	return result


# --- Validation. Each helper returns the in-game value, or null after appending errors. ---

static func _single(v: Variant, key: String, errors: Array[String]) -> Variant:
	match key:
		"name":
			if typeof(v) != TYPE_STRING or (v as String).strip_edges().is_empty():
				errors.append("name: expected a non-empty string, got %s" % _describe(v))
				return null
			var s: String = v
			if s.length() > MAX_NAME:
				errors.append("name: too long (%d characters, max %d)" % [s.length(), MAX_NAME])
				return null
			return s
		"bg":
			if typeof(v) != TYPE_STRING or not BackgroundScript.THEMES.has(v):
				errors.append("bg: expected one of %s, got %s" % [", ".join(PackedStringArray(BackgroundScript.THEMES.keys())), _describe(v)])
				return null
			return v as String
		"bpm":
			return _number(v, "bpm", MIN_BPM, MAX_BPM, errors)
		"switch_beats":
			var n: Variant = _number(v, "switch_beats", 1.0, MAX_SWITCH_BEATS, errors)
			if n == null:
				return null
			if float(n) != floorf(float(n)):
				errors.append("switch_beats: expected a whole number, got %s" % _describe(v))
				return null
			return int(n)
		"spawn", "goal":
			return _point(v, key, errors)
		"kill_y":
			return _number(v, "kill_y", -MAX_COORD, MAX_COORD, errors)
		"cam_bottom":
			var c: Variant = _number(v, "cam_bottom", -MAX_COORD, MAX_COORD, errors)
			return null if c == null else int(roundf(float(c)))
	return null


static func _list(items: Array, key: String, shape: String, errors: Array[String]) -> Variant:
	var out := []
	var bad := false
	for i in items.size():
		var path := "%s[%d]" % [key, i]
		var item: Variant = null
		match shape:
			"rect":
				item = _rect(items[i], path, errors)
			"point":
				item = _point(items[i], path, errors)
			"tempo":
				item = _tempo(items[i], path, errors)
			"pend":
				item = _pend(items[i], path, errors)
			"note", "power", "sign":
				item = _tagged(items[i], path, shape, errors)
		if item == null:
			bad = true
		else:
			out.append(item)
	return null if bad else out


static func _number(v: Variant, path: String, lo: float, hi: float, errors: Array[String]) -> Variant:
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		errors.append("%s: expected a number, got %s" % [path, _describe(v)])
		return null
	var f := float(v)
	if not is_finite(f):
		errors.append("%s: expected a finite number, got %s" % [path, _describe(v)])
		return null
	if f > hi and is_inf(lo):
		errors.append("%s: %s is too large (max %s)" % [path, _fmt(f), _fmt(hi)])
		return null
	if f < lo or f > hi:
		errors.append("%s: %s is out of range (%s to %s)" % [path, _fmt(f), _fmt(lo), _fmt(hi)])
		return null
	return f


static func _point(v: Variant, path: String, errors: Array[String]) -> Variant:
	if typeof(v) != TYPE_ARRAY or (v as Array).size() != 2:
		errors.append("%s: expected [x, y], got %s" % [path, _describe(v)])
		return null
	var a: Array = v
	var x: Variant = _number(a[0], path + " x", -MAX_COORD, MAX_COORD, errors)
	var y: Variant = _number(a[1], path + " y", -MAX_COORD, MAX_COORD, errors)
	if x == null or y == null:
		return null
	return Vector2(float(x), float(y))


static func _rect(v: Variant, path: String, errors: Array[String]) -> Variant:
	if typeof(v) != TYPE_ARRAY or (v as Array).size() != 4:
		errors.append("%s: expected [x, y, w, h], got %s" % [path, _describe(v)])
		return null
	var a: Array = v
	var x: Variant = _number(a[0], path + " x", -MAX_COORD, MAX_COORD, errors)
	var y: Variant = _number(a[1], path + " y", -MAX_COORD, MAX_COORD, errors)
	var w: Variant = _size(a[2], path + " w", MAX_SIZE, errors)
	var h: Variant = _size(a[3], path + " h", MAX_SIZE, errors)
	if x == null or y == null or w == null or h == null:
		return null
	return Rect2(float(x), float(y), float(w), float(h))


## A number > 0 and <= hi.
static func _size(v: Variant, path: String, hi: float, errors: Array[String]) -> Variant:
	var n: Variant = _number(v, path, -INF, hi, errors)
	if n != null and float(n) <= 0.0:
		errors.append("%s: must be greater than 0, got %s" % [path, _describe(v)])
		return null
	return n


static func _tempo(v: Variant, path: String, errors: Array[String]) -> Variant:
	if typeof(v) != TYPE_ARRAY or (v as Array).size() != 2:
		errors.append("%s: expected [x, bpm], got %s" % [path, _describe(v)])
		return null
	var a: Array = v
	var x: Variant = _number(a[0], path + " x", -MAX_COORD, MAX_COORD, errors)
	var bpm: Variant = _number(a[1], path + " bpm", MIN_BPM, MAX_BPM, errors)
	if x == null or bpm == null:
		return null
	return [float(x), float(bpm)]


static func _pend(v: Variant, path: String, errors: Array[String]) -> Variant:
	if typeof(v) != TYPE_ARRAY or (v as Array).size() < 4 or (v as Array).size() > 5:
		errors.append("%s: expected [[x, y], rod_length, width, max_angle, beats_per_side?], got %s" % [path, _describe(v)])
		return null
	var a: Array = v
	var pivot: Variant = _point(a[0], path + " pivot", errors)
	var rod: Variant = _size(a[1], path + " rod_length", MAX_ROD, errors)
	var width: Variant = _size(a[2], path + " width", MAX_ROD, errors)
	var angle: Variant = _number(a[3], path + " max_angle", 0.0, MAX_ANGLE, errors)
	var beats: Variant = 1.0
	if a.size() == 5:
		beats = _size(a[4], path + " beats_per_side", MAX_BEATS_PER_SIDE, errors)
	if pivot == null or rod == null or width == null or angle == null or beats == null:
		return null
	var out := [pivot, float(rod), float(width), float(angle)]
	if a.size() == 5:
		out.append(float(beats))
	return out


## [[x, y], "string"] items: notes (note type), power (kind) and signs (text).
static func _tagged(v: Variant, path: String, shape: String, errors: Array[String]) -> Variant:
	var label: String = {"note": "type", "power": "kind", "sign": "text"}[shape]
	if typeof(v) != TYPE_ARRAY or (v as Array).size() != 2:
		errors.append("%s: expected [[x, y], \"%s\"], got %s" % [path, label, _describe(v)])
		return null
	var a: Array = v
	var pos: Variant = _point(a[0], path + " position", errors)
	if typeof(a[1]) != TYPE_STRING:
		errors.append("%s %s: expected a string, got %s" % [path, label, _describe(a[1])])
		return null
	var s: String = a[1]
	match shape:
		"note":
			if not NOTE_TYPES.has(s):
				errors.append("%s type: unknown note type %s (expected eighth, quarter, half or whole)" % [path, _describe(s)])
				return null
		"power":
			if s.is_empty() or s.length() > MAX_KIND:
				errors.append("%s kind: expected 1 to %d characters, got %s" % [path, MAX_KIND, _describe(s)])
				return null
		"sign":
			if s.length() > MAX_TEXT:
				errors.append("%s text: too long (%d characters, max %d)" % [path, s.length(), MAX_TEXT])
				return null
	if pos == null:
		return null
	return [pos, s]


## Godot's JSON parser prints engine warnings for exponents past a double's range, so
## numbers with a 3-digit exponent (far outside every limit anyway) are refused first.
## Returns an error message, or "" if there are none. Skips over strings.
static func _extreme_number(text: String) -> String:
	var re := RegEx.create_from_string("\"(?:[^\"\\\\]|\\\\.)*\"|(-?[0-9.]+[eE][+-]?[0-9]{3,})")
	for m: RegExMatch in re.search_all(text):
		if m.get_string(1) != "":
			var line := text.left(m.get_start(1)).count("\n") + 1
			return "line %d: number %s is far too large or small" % [line, _clip(m.get_string(1), 24)]
	return ""


# --- Writing helpers ---

static func _encode(v: Variant) -> Variant:
	match typeof(v):
		TYPE_VECTOR2, TYPE_VECTOR2I:
			var p := Vector2(v)
			return [_json_num(p.x), _json_num(p.y)]
		TYPE_RECT2, TYPE_RECT2I:
			var r := Rect2(v)
			return [_json_num(r.position.x), _json_num(r.position.y), _json_num(r.size.x), _json_num(r.size.y)]
		TYPE_ARRAY:
			var out := []
			for item: Variant in (v as Array):
				out.append(_encode(item))
			return out
		TYPE_INT, TYPE_FLOAT:
			return _json_num(float(v))
		TYPE_STRING, TYPE_STRING_NAME, TYPE_BOOL, TYPE_NIL:
			return v
	return str(v)


## Whole numbers become ints so they're written as 600, not 600.0.
static func _json_num(f: float) -> Variant:
	if is_finite(f) and f == roundf(f) and absf(f) < 1e15:
		return int(f)
	return f


static func _inline(v: Variant) -> String:
	match typeof(v):
		TYPE_ARRAY:
			var parts := PackedStringArray()
			for item: Variant in (v as Array):
				parts.append(_inline(item))
			return "[" + ", ".join(parts) + "]"
		TYPE_INT:
			return str(v)
		TYPE_FLOAT:
			return _fmt(float(v)) if is_finite(float(v)) else "null"
	return JSON.stringify(v)


## Up to 6 decimals, no trailing zeros.
static func _fmt(f: float) -> String:
	if not is_finite(f):
		return str(f)
	if absf(f) >= 1e15:
		return str(f)
	if f == roundf(f):
		return str(int(f))
	return String.num(f, 6)


# --- Error helpers ---

## Short description of a JSON value for error messages; never huge.
static func _describe(v: Variant, depth: int = 0) -> String:
	match typeof(v):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_INT, TYPE_FLOAT:
			return _fmt(float(v))
		TYPE_STRING:
			return JSON.stringify(_clip(v as String, 24))
		TYPE_ARRAY:
			var a: Array = v
			if a.is_empty():
				return "[]"
			if depth >= 2:
				return "[...]"
			if a.size() > 6:
				return "a list of %d items" % a.size()
			var parts := PackedStringArray()
			for item: Variant in a:
				parts.append(_describe(item, depth + 1))
			return "[" + ", ".join(parts) + "]"
		TYPE_DICTIONARY:
			return "an object { ... }"
	return "an unsupported value"


static func _clip(s: String, n: int) -> String:
	return s if s.length() <= n else s.left(n) + "..."

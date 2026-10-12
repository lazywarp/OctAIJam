extends RefCounted
## Custom levels: the player's own JSON level files in user://levels/ (format: see
## docs/LEVEL_FORMAT.md, parsing and validation: level_io.gd). Static helpers only:
##   seed_if_empty(): first run, writes a README and a starter level into the folder.
##   scan(): one entry per *.json file, each already validated.
##   load_file(path): reads and validates one file; same entry shape as scan().
##   resolve(arg): turns a path or a bare file name into a readable path (for --custom).
##   open_folder(): shows the folder in the OS file manager.
## Nothing here crashes or prints engine errors on a bad file: every problem comes back as
## a readable error string in the entry.

const LevelIO := preload("res://scripts/level_io.gd")
const Powerups := preload("res://scripts/powerups.gd")

const DIR := "user://levels/"
const EXAMPLES_DIR := "res://levels/examples/" # the built-in levels as files; shipped in exports
## Bigger files are refused without reading them. Any file within LevelIO's character
## limit fits (a UTF-8 character is at most 4 bytes); LevelIO then checks characters.
const MAX_BYTES := LevelIO.MAX_TEXT_CHARS * 4
const README_FILE := "README.txt"
const STARTER_FILE := "my_first_level.json"

const README := """Meltronome custom levels
========================

Put your own levels here as .json files, one level per file. The game finds every
*.json file in this folder (not in subfolders) and checks it for mistakes.

The format is described in docs/LEVEL_FORMAT.md ("Meltronome level format") in the
game's source. The quickest start: copy my_first_level.json, rename it and edit it
in any text editor. Units are pixels and y grows downward.

To test a level straight away, start the game from a terminal:

    godot --path <game folder> -- --custom my_first_level.json
    Meltronome.x86_64 -- --custom my_first_level.json      (exported build)

If the file has a mistake, the errors are printed and the game opens the main menu.
The game never changes or deletes files in this folder.
"""

## A short tour: beat blocks over hot notes, a lamp with a snowflake, a pendulum, notes.
const STARTER := """{
	"format": 1,
	"_comment": "Your first custom level. Copy it, rename it and make it yours.",
	"name": "My First Level",
	"bg": "hall",
	"bpm": 100,
	"spawn": [0, 570],
	"goal": [2400, 600],
	"tempo": [
		[1080, 115]
	],
	"solid": [
		[-340, 200, 40, 600],
		[-300, 600, 800, 200],
		[1080, 560, 420, 240],
		[1860, 600, 700, 200]
	],
	"a": [
		[600, 540, 140, 24]
	],
	"b": [
		[840, 480, 140, 24]
	],
	"hot": [
		[500, 680, 1460, 120]
	],
	"lamp": [
		[1240, 300, 200, 260]
	],
	"pend": [
		[[1660, 330], 200, 160, 0.4]
	],
	"snow": [
		[1160, 520]
	],
	"notes": [
		[[150, 560], "eighth"],
		[[250, 560], "eighth"],
		[[350, 560], "eighth"],
		[[910, 400], "half"],
		[[1660, 420], "whole"],
		[[2000, 560], "quarter"],
		[[2100, 560], "quarter"]
	],
	"signs": [
		[[120, 440], "Welcome to your own level! Edit it in a text editor."],
		[[1290, 250], "Blue, then pink: ride the beat. Grab the snowflake."],
		[[2200, 500], "Lemonade ahead!"]
	]
}
"""


static func dir_path() -> String:
	return DIR


## Creates the levels folder if it's missing. Returns false if that failed.
static func ensure_dir() -> bool:
	if DirAccess.dir_exists_absolute(DIR):
		return true
	return DirAccess.make_dir_recursive_absolute(DIR) == OK


## First run: if the folder is missing or empty, writes the README and the starter level.
## Never overwrites a file that's already there.
static func seed_if_empty() -> void:
	var existed := DirAccess.dir_exists_absolute(DIR)
	if not ensure_dir():
		return
	if existed:
		var d := DirAccess.open(DIR)
		if d == null:
			return
		d.include_hidden = true
		if not d.get_files().is_empty() or not d.get_directories().is_empty():
			return
	_write_new(DIR + README_FILE, README)
	_write_new(DIR + STARTER_FILE, STARTER)


static func _write_new(path: String, text: String) -> void:
	if FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)


## One entry per *.json file in the folder, sorted by file name:
## { path, file, name, ok, errors, warnings, level } (see load_file). Non-JSON files and
## subfolders are ignored; a missing folder gives an empty list.
static func scan(dir := DIR) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var d := DirAccess.open(dir)
	if d == null:
		return out
	var files: Array[String] = []
	for f: String in d.get_files():
		if f.get_extension().to_lower() == "json":
			files.append(f)
	files.sort_custom(func(p: String, q: String) -> bool: return p.naturalnocasecmp_to(q) < 0)
	var base := dir if dir.ends_with("/") else dir + "/"
	for f: String in files:
		out.append(load_file(base + f))
	return out


## The built-in levels as example files (res://levels/examples/), same entries as scan().
static func examples() -> Array[Dictionary]:
	return scan(EXAMPLES_DIR)


## Reads and validates one level file. Returns
## { path, file, name, ok, errors: Array[String], warnings: Array[String], level }:
## name is the level's name when ok, else the file name without ".json"; level is the
## in-game Dictionary (empty unless ok).
static func load_file(path: String) -> Dictionary:
	var entry := {
		"path": path, "file": path.get_file(), "name": path.get_file().get_basename(),
		"ok": false, "errors": [] as Array[String], "warnings": [] as Array[String], "level": {},
	}
	var errors: Array[String] = entry["errors"]
	var text := _read_text(path, errors)
	if not errors.is_empty():
		return entry
	var res: Dictionary = LevelIO.from_json_text(text)
	errors.append_array(res["errors"])
	var warnings: Array[String] = entry["warnings"]
	warnings.append_array(res["warnings"])
	if not bool(res["ok"]):
		return entry
	var level: Dictionary = res["level"]
	# Power-up kinds are free text in the format; flag the ones this version doesn't have
	# (the game skips them).
	for pw: Array in level.get("power", []):
		if not Powerups.has(str(pw[1])):
			warnings.append("power: unknown power-up kind \"%s\" will be skipped" % pw[1])
	entry["ok"] = true
	entry["level"] = level
	entry["name"] = str(level["name"])
	return entry


# The file as text, or "" after appending a readable error. Checks the size before reading
# and the UTF-8 before decoding, since a decoding error would be printed by the engine.
static func _read_text(path: String, errors: Array[String]) -> String:
	if not FileAccess.file_exists(path):
		errors.append("file not found")
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("could not open the file (%s)" % error_string(FileAccess.get_open_error()))
		return ""
	var size := f.get_length()
	if size > MAX_BYTES:
		errors.append("the file is too large (%d KB, max %d KB)" % [ceili(size / 1024.0), roundi(MAX_BYTES / 1024.0)])
		return ""
	var bytes := f.get_buffer(size)
	if bytes.size() != size:
		errors.append("could not read the file (%s)" % error_string(f.get_error()))
		return ""
	if bytes.size() >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF:
		bytes = bytes.slice(3) # UTF-8 byte order mark, as some Windows editors write
	var bad := _utf8_error_at(bytes)
	if bad >= 0:
		errors.append("not a UTF-8 text file (bad byte at offset %d); save it as UTF-8 text" % bad)
		return ""
	if bytes.is_empty():
		errors.append("the file is empty")
		return ""
	return bytes.get_string_from_utf8()


# Offset of the first byte that isn't valid UTF-8 text (NUL counts as invalid), or -1.
static func _utf8_error_at(b: PackedByteArray) -> int:
	var i := 0
	var n := b.size()
	while i < n:
		var c := b[i]
		if c < 0x80:
			if c == 0:
				return i
			i += 1
			continue
		var more := 0
		var lo := 0x80 # allowed range of the first continuation byte (rules out overlong
		var hi := 0xBF # encodings, surrogates and code points above U+10FFFF)
		if c >= 0xC2 and c <= 0xDF:
			more = 1
		elif c >= 0xE0 and c <= 0xEF:
			more = 2
			if c == 0xE0:
				lo = 0xA0
			elif c == 0xED:
				hi = 0x9F
		elif c >= 0xF0 and c <= 0xF4:
			more = 3
			if c == 0xF0:
				lo = 0x90
			elif c == 0xF4:
				hi = 0x8F
		else:
			return i
		if i + more >= n:
			return i
		for k in range(1, more + 1):
			var cc := b[i + k]
			if cc < (lo if k == 1 else 0x80) or cc > (hi if k == 1 else 0xBF):
				return i
		i += more + 1
	return -1


## A --custom argument as a path: absolute paths (and res:// / user:// ones) as given,
## otherwise a file in the levels folder, then one of the examples. "" if none exists.
## ".json" may be left off.
static func resolve(arg: String) -> String:
	var names: Array[String] = [arg]
	if arg.get_extension().to_lower() != "json":
		names.append(arg + ".json")
	for name: String in names:
		if name.is_absolute_path():
			if FileAccess.file_exists(name):
				return name
			continue
		for dir: String in [DIR, EXAMPLES_DIR]:
			if FileAccess.file_exists(dir + name):
				return dir + name
	return ""


## Shows the levels folder in the OS file manager (creating it first).
static func open_folder() -> void:
	ensure_dir()
	OS.shell_open(ProjectSettings.globalize_path(DIR))

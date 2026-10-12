# Meltronome level format (format 1)

Custom levels are JSON files that mirror the level Dictionaries in [`scripts/levels.gd`](../scripts/levels.gd). [`scripts/level_io.gd`](../scripts/level_io.gd) converts between the two and checks files for mistakes.

The six built-in levels are in [`levels/examples/`](../levels/examples/) (`01_allegro.json` to `06_finale.json`). Copy one as a starting point.

The game reads custom levels from its `levels` folder; see [Playing your levels](#playing-your-levels).

## Playing your levels

Put your level files in the game's `levels` folder (`user://levels/`). The game creates it the first time it starts:

| OS | Folder |
| --- | --- |
| Linux | `~/.local/share/godot/app_userdata/Meltronome/levels/` |
| Windows | `%APPDATA%\Godot\app_userdata\Meltronome\levels\` |
| macOS | `~/Library/Application Support/Godot/app_userdata/Meltronome/levels/` |

- If the folder is new or empty, the game puts a `README.txt` and a starter level, `my_first_level.json`, in it. It never overwrites or deletes your files.
- Every `*.json` file directly in the folder counts as one level. Other files and subfolders are ignored.
- To test a level straight away, start the game from a terminal with `--custom` after a lone `--`:

  ```sh
  godot --path . -- --custom my_first_level.json      # from the source folder
  ./Meltronome.x86_64 -- --custom my_first_level.json  # an exported build
  ```

  The argument is a file name in the `levels` folder (`.json` can be left off) or a full path. The names of the built-in examples (for example `01_allegro.json`) also work, in exported builds too.
- Melting restarts your level. Reaching the lemonade shows "Bravo!" and your time, then returns to the main menu. Custom levels never change the best times of the built-in levels.
- If the file has a mistake, the game prints every error (see [Errors and warnings](#errors-and-warnings)) to the terminal and opens the main menu instead. Warnings are printed too, but the level still plays. Files that aren't UTF-8 text, or are over about 4 MB, are refused without being parsed.

## Basics

- The file holds one JSON object. Key order doesn't matter.
- Units are world pixels. `x` grows to the right and `y` grows **downward**: a larger `y` is lower on screen. Normal ground is around `y = 600`.
- A **point** is `[x, y]`.
- A **rect** is `[x, y, w, h]`, where `x, y` is the top-left corner and `w, h` are the width and height. Both must be greater than 0.
- Numbers can be whole or decimal (`600` and `600.0` are the same).
- Jump reach is about 120 px up and 250 px across. Keep gaps at 120 px or less and rises at 90 px or less.
- JSON has no comments. Keys that start with `_` (for example `"_comment"`) are ignored, so you can use them for notes.
- Unknown keys are ignored with a warning, so a file made for a newer version still loads.

## Minimal valid level

```json
{
	"format": 1,
	"name": "My First Level",
	"spawn": [0, 570],
	"goal": [900, 600],
	"solid": [
		[-300, 600, 1300, 200]
	]
}
```

## Keys

**Required:** `format`, `name`, `spawn`, `goal` and `solid` (with at least one rect). Everything else is optional.

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `format` | whole number | (required) | Format version. Must be `1`. |
| `name` | string, 1–64 characters | (required) | Shown when the level starts, for example `"I. Allegro"`. |
| `spawn` | point | (required) | Where the ice cube starts (its centre). |
| `goal` | point | (required) | Where the lemonade glass stands (bottom centre). |
| `solid` | list of rects | (required) | Piano-key ground and walls. Always solid. |
| `bg` | string | `"hall"` | Backdrop theme: `hall`, `syncopation`, `fortissimo`, `dacapo`, `accelerando` or `finale`. `accelerando` has no corner metronome. |
| `bpm` | number, 30–400 | `100` | Starting tempo in beats per minute. Restored on every (re)load. |
| `switch_beats` | whole number, 1–16 | `2` | Beats per turn of the `a` / `b` note blocks. |
| `kill_y` | number | `900` | Falling below this `y` melts the cube. |
| `cam_bottom` | number | `800` | The camera never shows anything below this `y`. Rounded to a whole number. |
| `tempo` | list of `[x, bpm]` | none | The first time the player passes `x`, the tempo eases to `bpm` (30–400) over one bar. |
| `a` | list of rects | none | Blue note blocks. Solid for `switch_beats` beats, then they hand over to `b`. |
| `b` | list of rects | none | Pink note blocks. Solid while `a` is off. |
| `hot` | list of rects | none | Hot notes. Touching one melts the cube. |
| `lamp` | list of rects | none | Heat lamps. The fixture hangs at the top of the rect and its light fills the rect. Inside the light, stillness melts you twice as fast (1 s). |
| `pend` | list of pendulums | none | Swinging platforms; see below. |
| `snow` | list of points | none | Refreezer snowflakes (pickup centres). Holding one cancels the next stillness melt. |
| `notes` | list of `[[x, y], type]` | none | Score notes. `type` is `"eighth"`, `"quarter"`, `"half"` or `"whole"`. |
| `power` | list of `[[x, y], kind]` | none | Power-up pickups. `kind` is a string of 1–32 characters naming the power-up; the game decides which kinds exist. |
| `signs` | list of `[[x, y], text]` | none | Text in the level. `text` is up to 200 characters. |

### Pendulums

Each item in `pend` is `[[x, y], rod_length, width, max_angle, beats_per_side]`:

| Field | Type | Meaning |
| --- | --- | --- |
| `[x, y]` | point | The pivot. The slab hangs `rod_length` below it. |
| `rod_length` | number, > 0 and ≤ 2000 | Rod length in pixels. |
| `width` | number, > 0 and ≤ 2000 | Slab width in pixels. |
| `max_angle` | number, 0–1.5 | Swing angle in radians (about 0.35–0.6 works well). The slab travels `sin(max_angle) * rod_length` to each side. |
| `beats_per_side` | number, > 0 and ≤ 16, optional | Beats per swing from one side to the other. Defaults to `1`; `2` is half speed. |

The pendulum swings with the metronome and reaches an extreme on every beat (or every `beats_per_side` beats).

### Example with every kind of piece

```json
{
	"format": 1,
	"_comment": "A short tour of every piece.",
	"name": "Etude",
	"bg": "fortissimo",
	"bpm": 110,
	"switch_beats": 2,
	"spawn": [0, 570],
	"goal": [2200, 600],
	"tempo": [
		[1200, 130]
	],
	"solid": [
		[-340, 200, 40, 600],
		[-300, 600, 800, 200],
		[1900, 600, 500, 200]
	],
	"a": [
		[600, 560, 140, 24]
	],
	"b": [
		[840, 520, 140, 24]
	],
	"hot": [
		[500, 680, 1400, 120]
	],
	"lamp": [
		[200, 340, 200, 260]
	],
	"pend": [
		[[1200, 300], 200, 160, 0.38, 2],
		[[1500, 300], 200, 160, 0.38]
	],
	"snow": [
		[300, 560]
	],
	"notes": [
		[[660, 520], "eighth"],
		[[1500, 380], "whole"]
	],
	"power": [
		[[100, 560], "grace_note"]
	],
	"signs": [
		[[120, 440], "Keep moving!"]
	]
}
```

## Limits

These limits stop a broken or hostile file from hanging the game. A file that breaks one is refused with an error.

| What | Limit |
| --- | --- |
| File size | 1,000,000 characters |
| Coordinates (`x`, `y`, `kill_y`, `cam_bottom`, tempo `x`) | −100000 to 100000 |
| Rect width and height | greater than 0, at most 100000 |
| Items in one list | 2000 |
| Items in all lists together | 8000 |
| `name` | 1–64 characters |
| Sign text | 200 characters |
| Power-up kind | 1–32 characters |
| Numbers | Must be finite. `NaN` and `Infinity` aren't valid JSON, and numbers with a 3-digit exponent (like `1e300`) are refused. |

## Errors and warnings

The loader returns every problem it finds, each pointing at the key and item, for example:

```
missing required key "goal"
solid[3]: expected [x, y, w, h], got [1, 2]
pend[0] max_angle: 3 is out of range (0 to 1.5)
notes[2] type: unknown note type "sixteenth" (expected eighth, quarter, half or whole)
invalid JSON at line 12: Expected '}'
```

A file with any error isn't loaded. Unknown keys only produce a warning such as `unknown key "sparkles" ignored (made for a newer version?)`.

## For developers

- `LevelIO.to_json_text(level)` writes a level Dictionary as JSON, with keys in a fixed order and one list item per line, so files diff cleanly. `LevelIO.to_json_dict(level)` returns the same data as a Dictionary.
- `LevelIO.from_json_text(text)` returns `{ "ok": bool, "level": Dictionary, "errors": Array[String], "warnings": Array[String] }`. `level` uses the in-game types (`Vector2`, `Rect2`, floats), matches `levels.gd` and is empty unless `ok` is true.
- Load it with `const LevelIO := preload("res://scripts/level_io.gd")`.
- `scripts/custom_levels.gd` reads the files: `scan()` returns one validated entry per file, `{ path, file, name, ok, errors, warnings, level }`, and `load_file(path)` checks a single file. `main.gd`'s `play_custom(level, path)` plays one.
- Every export preset has `include_filter="levels/examples/*.json"`, so the example files are packed into builds and can be read from `res://levels/examples/`.
- When you add a level key, add it to `KEY_ORDER` (and `LISTS` if it's a list) in `level_io.gd`, add its validation, and document it here. If an old file would no longer mean the same thing, bump `FORMAT`.

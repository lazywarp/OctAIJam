# Meltronome

A 2D platformer made in Godot 4 for the OctAIJam (theme: *surreal* — and you can't stop for more than 2 seconds or the level resets).

You are an ice cube at a very strange concert. Hop across giant piano keys while a metronome ticks; every jump plays a note in the song. Stop pressing for 2 seconds and you melt. Note-blocks switch on and off with the beat, red notes are hot, and each level ends in a glass of lemonade.

Design doc: [docs/GDD.md](docs/GDD.md)

## Run it

Install [Godot 4](https://godotengine.org/download) (the standard build, not .NET) on Windows, macOS or Linux, then either:

- open the Godot editor, **Import** this folder's `project.godot`, and press **F5**; or
- from this folder run `godot --path .`

All art and audio are generated in code, so there are no asset files.

## Controls

| Action | Keys | Gamepad |
|---|---|---|
| Move | Arrows / A D | D-pad / left stick |
| Jump | Space / W / Up / Z | A |
| Fullscreen | F11 | |
| Quit | Esc | |

Holding any key counts as input — letting go of everything starts the 2-second melt.

## Layout

- `scripts/main.gd` — beat clock, stillness timer, level flow, camera, music cues
- `scripts/levels.gd` — level data (edit this to make new levels)
- `scripts/player.gd` — the ice cube
- `scripts/platform.gd`, `hazard.gd`, `goal.gd`, `sign.gd` — level pieces
- `scripts/synth.gd` — procedural sound
- `scripts/background.gd`, `hud.gd` — visuals and UI

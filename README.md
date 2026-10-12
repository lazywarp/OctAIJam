# Meltronome

A 2D platformer made in Godot 4 for the OctAIJam (theme: *surreal* — and you can't stop for more than 2 seconds or the level resets).

You are an ice cube at a very strange concert. Hop across giant piano keys while a metronome ticks; every jump plays a note in the song. Stop pressing for 2 seconds and you melt. Note-blocks switch on and off with the beat, red notes are hot, and each level ends in a glass of lemonade.

Design doc: [docs/GDD.md](docs/GDD.md)

## Run it

Install [Godot 4](https://godotengine.org/download) (the standard build, not .NET) on Windows, macOS or Linux, then either:

- open the Godot editor, **Import** this folder's `project.godot`, and press **F5**; or
- from this folder run `godot --path .` (add `-- --level 5` to jump straight to a level)

All art and audio are generated in code, so there are no asset files.

## Builds

Standalone builds for players without Godot. To make them, install the **4.7.2** export templates (Editor → **Manage Export Templates** → Download and Install), then from this folder run:

```sh
godot --headless --path . --export-release "Linux" builds/linux/Meltronome.x86_64
godot --headless --path . --export-release "Windows Desktop" builds/windows/Meltronome.exe
godot --headless --path . --export-release "macOS" builds/macos/Meltronome.zip
```

Outputs land in `builds/` (git-ignored); the presets live in `export_presets.cfg`. Linux and Windows are single files with the game packed inside. The macOS zip is a universal (Intel + Apple Silicon) `.app`. It is ad-hoc signed, not notarized. Universal macOS builds need `import_etc2_astc` turned on in `project.godot`. Windows icon/version editing is off (`application/modify_resources=false`) so exporting doesn't need `rcedit`.

To play:

- **Linux** — `chmod +x Meltronome.x86_64`, then run it.
- **Windows** — run `Meltronome.exe`. If SmartScreen warns, click **More info → Run anyway**.
- **macOS** — unzip, then the first time **right-click `Meltronome.app` → Open** (it isn't notarized, so a double-click is blocked). On macOS 15+, try opening it once, then go to System Settings → Privacy & Security → **Open Anyway**.

## Controls

| Action | Keys | Gamepad |
|---|---|---|
| Move | Arrows / A D | D-pad / left stick |
| Jump | Space / W / Up / Z | A |
| Mute | M | Back |
| Fullscreen | F11 | |
| Quit | Esc | |

Holding any key counts as input — letting go of everything starts the 2-second melt. Drips warn you after 1 second. After a melt, press jump to restart right away.

## Layout

- `scripts/main.gd` — beat clock, stillness timer, level flow, camera, music cues
- `scripts/levels.gd` — level data (edit this to make new levels)
- `scripts/player.gd` — the ice cube
- `scripts/platform.gd`, `hazard.gd`, `goal.gd`, `sign.gd` — level pieces
- `scripts/synth.gd` — procedural sound
- `scripts/background.gd`, `hud.gd` — visuals and UI

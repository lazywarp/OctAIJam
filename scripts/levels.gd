extends RefCounted
## Level data. Rects are Rect2(x, y, width, height) in world pixels; y grows downward.
## Jump reach: ~120 px up, ~250 px across. Keep gaps <= 120 and rises <= 90.
##   solid: piano-key ground   a / b: note blocks that alternate every 2 beats
##   hot: hazards              signs: [position, text]
##   pend: pendulum platforms, [pivot: Vector2, rod_length, width, max_angle (radians, ~0.6),
##         beats_per_side (optional, default 1; 2 = half speed)].
##         The slab hangs rod_length below the pivot and swings with the metronome, at an
##         extreme on every beat; it travels sin(max_angle) * rod_length each side.
## Optional:
##   switch_beats: beats per a/b turn (default 2)
##   bpm: starting tempo (default 100), restored on every (re)load
##   tempo: [[x, bpm], ...] - first time the player passes x, ease to bpm over one bar
##   lamp: [Rect2, ...] - heat lamps. The fixture hangs at the top of the rect and its light
##         fills the rect; while the cube is inside, stillness fills twice as fast (1 s melt).


static func all() -> Array:
	return [
		{
			"name": "I. Allegro",
			"spawn": Vector2(0, 570),
			"goal": Vector2(2760, 600),
			"solid": [
				Rect2(-340, 200, 40, 600),
				Rect2(-300, 600, 1000, 200),
				Rect2(820, 600, 500, 200),
				Rect2(1440, 540, 300, 260),
				Rect2(1860, 470, 260, 330),
				Rect2(2240, 600, 700, 200),
			],
			"signs": [
				[Vector2(120, 440), "Arrows / A D to slide.   Space / W to jump."],
				[Vector2(120, 476), "Stop pressing for 2 seconds and you melt."],
				[Vector2(1070, 500), "Holding a key counts. Letting go doesn't."],
				[Vector2(2560, 500), "Dive into the lemonade."],
			],
		},
		{
			"name": "II. Syncopation",
			"spawn": Vector2(0, 570),
			"goal": Vector2(3020, 420),
			"switch_beats": 4,
			"solid": [
				Rect2(-340, 200, 40, 600),
				Rect2(-300, 600, 800, 200),
				Rect2(1080, 600, 260, 200),
				Rect2(1920, 520, 120, 30),
				Rect2(2620, 420, 500, 380),
			],
			"a": [
				Rect2(600, 560, 160, 30),
				Rect2(840, 520, 160, 30),
				Rect2(2140, 470, 140, 30),
			],
			"b": [
				Rect2(1440, 560, 160, 30),
				Rect2(1680, 520, 140, 30),
				Rect2(2380, 420, 140, 30),
			],
			"signs": [
				[Vector2(120, 440), "Blue notes play for four beats, then pink notes take over."],
				[Vector2(120, 476), "Blinking means it's about to switch. Wait on the keys if you need to."],
				[Vector2(1210, 500), "Hold a key while you wait."],
			],
		},
		{
			"name": "III. Fortissimo",
			"spawn": Vector2(0, 570),
			"goal": Vector2(2700, 420),
			"solid": [
				Rect2(-340, 200, 40, 600),
				Rect2(-300, 600, 700, 200),
				Rect2(520, 520, 140, 30),
				Rect2(1000, 420, 120, 30),
				Rect2(1220, 470, 400, 30),
				Rect2(2180, 420, 600, 380),
			],
			"a": [
				Rect2(760, 470, 140, 30),
				Rect2(1950, 370, 140, 30),
			],
			"b": [
				Rect2(1720, 420, 140, 30),
			],
			"hot": [
				Rect2(400, 680, 1780, 120),
				Rect2(1395, 440, 50, 30),
			],
			"signs": [
				[Vector2(100, 440), "Fortissimo: the red notes are HOT."],
			],
		},
		{
			"name": "IV. Da Capo",
			"spawn": Vector2(0, 570),
			"goal": Vector2(1080, -20),
			"solid": [
				Rect2(-140, -200, 40, 1000),
				Rect2(-100, 600, 700, 200),
				Rect2(400, 500, 160, 24),
				Rect2(160, 410, 160, 24),
				Rect2(380, 140, 160, 24),
				Rect2(860, -20, 300, 24),
			],
			"a": [
				Rect2(380, 320, 140, 24),
				Rect2(620, 60, 140, 24),
			],
			"b": [
				Rect2(140, 230, 140, 24),
			],
			"signs": [
				[Vector2(150, 545), "Da capo: from the top. Climb!"],
			],
		},
		{
			"name": "V. Accelerando",
			"spawn": Vector2(0, 570),
			"goal": Vector2(3080, -100),
			"tempo": [[1100.0, 120.0], [2100.0, 140.0]],
			"solid": [
				Rect2(-340, 200, 40, 600),
				Rect2(-300, 600, 700, 200),
				Rect2(1000, 520, 240, 280),
				Rect2(2060, 300, 200, 30),
				Rect2(2120, 140, 140, 24),
				Rect2(2820, -100, 400, 24),
			],
			"pend": [
				[Vector2(560, 340), 200.0, 140.0, 0.45, 2.0],
				[Vector2(820, 300), 200.0, 140.0, 0.45, 2.0],
				[Vector2(1380, 260), 200.0, 140.0, 0.45, 2.0],
				[Vector2(1640, 200), 200.0, 140.0, 0.45, 2.0],
				[Vector2(1900, 140), 200.0, 140.0, 0.45, 2.0],
				[Vector2(2420, -130), 200.0, 140.0, 0.45, 2.0],
			],
			"a": [
				Rect2(2300, 220, 140, 24),
			],
			"b": [
				Rect2(2600, -20, 140, 24),
			],
			"signs": [
				[Vector2(150, 470), "The metronome came loose. Ride it."],
				[Vector2(1120, 440), "Accelerando: the tempo is rising."],
			],
		},
	]

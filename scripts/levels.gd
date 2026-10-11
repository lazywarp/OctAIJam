extends RefCounted
## Level data. Rects are Rect2(x, y, width, height) in world pixels; y grows downward.
## Jump reach: ~120 px up, ~250 px across. Keep gaps <= 120 and rises <= 90.
##   solid: piano-key ground   a / b: note blocks that alternate every 2 beats
##   hot: hazards              signs: [position, text]


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
			"goal": Vector2(2880, 420),
			"solid": [
				Rect2(-340, 200, 40, 600),
				Rect2(-300, 600, 800, 200),
				Rect2(1380, 600, 300, 200),
				Rect2(2480, 420, 500, 380),
			],
			"a": [
				Rect2(600, 560, 160, 30),
				Rect2(1120, 560, 160, 30),
				Rect2(2010, 480, 140, 30),
			],
			"b": [
				Rect2(860, 520, 160, 30),
				Rect2(1780, 540, 140, 30),
				Rect2(2240, 420, 140, 30),
			],
			"signs": [
				[Vector2(120, 440), "Blue notes play for two beats, then pink notes take over."],
				[Vector2(120, 476), "Follow the tick. Blinking means it's about to switch."],
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
	]

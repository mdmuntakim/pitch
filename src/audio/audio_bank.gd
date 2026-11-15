class_name AudioBank
extends Node
## Match audio: layered crowd ambience with excitement swells, chants, whistle,
## kick and bounce SFX and the goal roar. All streams are original generated
## assets from assets/audio/.

var crowd_a: AudioStreamPlayer
var crowd_b: AudioStreamPlayer
var chants: AudioStreamPlayer
var roar: AudioStreamPlayer
var whistle: AudioStreamPlayer
var kick: AudioStreamPlayer
var bounce: AudioStreamPlayer
var excitement := 0.0
var match_ref: Match = null
var swap_timer := 20.0
var use_a := true


static func attach(parent: Node, match_ref_: Match) -> AudioBank:
	var a := AudioBank.new()
	a.name = "AudioBank"
	a.match_ref = match_ref_
	parent.add_child(a)
	a._build()
	return a


func _build() -> void:
	crowd_a = _player("res://assets/audio/crowd_home.wav", -8.0, true)
	crowd_b = _player("res://assets/audio/crowd_chants.wav", -10.0, true)
	chants = _player("res://assets/audio/crowd_away.wav", -12.0, true)
	roar = _player("res://assets/audio/goal_roar.wav", -4.0, false)
	whistle = _player("res://assets/audio/whistle.wav", -6.0, false)
	kick = _player("res://assets/audio/kick.wav", -8.0, false)
	bounce = _player("res://assets/audio/bounce.wav", -10.0, false)
	for p in [crowd_a, crowd_b, chants]:
		if p != null:
			p.play()


func _player(path: String, db: float, _loop: bool) -> AudioStreamPlayer:
	var stream := load(path)
	if stream == null:
		push_warning("Audio missing: " + path)
		return null
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	p.bus = "Master"
	add_child(p)
	if not _loop:
		return p
	# Loop by hand (imports do not set loop metadata reliably).
	p.finished.connect(func() -> void: p.play())
	return p


func _process(dt: float) -> void:
	if match_ref == null or match_ref.ball == null:
		return
	# Excitement rises when the ball approaches either box.
	var p := match_ref.ball.global_position
	var danger := maxf(0.0, (absf(p.x) - 45.0) / 25.0)
	var target_excitement := clampf(danger, 0.0, 1.0)
	excitement = lerpf(excitement, target_excitement, dt * 0.8)
	var base_db := -10.0 + excitement * 5.0
	if crowd_a != null:
		crowd_a.volume_db = base_db
	if chants != null:
		chants.volume_db = base_db - 3.0
	# Alternate the chant layer in and out.
	swap_timer -= dt
	if swap_timer <= 0.0:
		swap_timer = randf_range(25.0, 45.0)
		if crowd_b != null:
			crowd_b.volume_db = -16.0 if crowd_b.volume_db > -16.0 else -7.0


func whistle_play() -> void:
	if whistle != null:
		whistle.play()


func kick_play(power: float) -> void:
	if kick != null:
		kick.volume_db = lerpf(-14.0, -2.0, clampf(power / 30.0, 0.0, 1.0))
		kick.play()


func bounce_play() -> void:
	if bounce != null:
		bounce.play()


func goal_roar() -> void:
	if roar != null:
		roar.play()
	if crowd_a != null:
		crowd_a.volume_db = -2.0

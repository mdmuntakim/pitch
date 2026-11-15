class_name Replay
extends Node3D
## Goal replay: plays back the recorded snapshots from a behind-goal camera in
## slow motion, with a REPLAY banner handled by the HUD.

signal finished

var match_ref: Match
var camera: Camera3D
var playing := false
var cursor := 0.0
var speed := 0.5   # slow motion factor
var from_camera: Camera3D = null


static func attach(match_ref_: Match) -> Replay:
	var r := Replay.new()
	r.name = "Replay"
	r.match_ref = match_ref_
	r.camera = Camera3D.new()
	r.camera.fov = 38.0
	r.camera.current = false
	r.add_child(r.camera)
	r.match_ref_.add_child(r)
	return r


func start() -> void:
	if match_ref.recorder.size() < 30:
		finished.emit.call_deferred()
		return
	playing = true
	cursor = 0.0
	camera.current = true
	Engine.time_scale = speed


func stop() -> void:
	if not playing:
		return
	playing = false
	Engine.time_scale = 1.0
	if from_camera != null:
		from_camera.current = true
	finished.emit()


func _process(dt: float) -> void:
	if not playing:
		return
	var rec := match_ref.recorder
	cursor += dt / Engine.time_scale  # advance in real seconds
	var frame := int(cursor * 30.0)
	if frame >= rec.size() - 1:
		stop()
		return
	var snap: Dictionary = rec[frame]
	# Position the camera behind the goal that was scored in.
	var ball_at: Vector3 = snap.ball
	var goal_x := signf(ball_at.x) * (Pitch.HALF_LENGTH + 6.0)
	camera.position = Vector3(goal_x, 6.5, ball_at.z * 0.4 + 8.0)
	camera.look_at(ball_at + Vector3(0, 1.0, 0), Vector3.UP)
	# Rewind ball and players.
	match_ref.ball.global_position = ball_at
	var i := 0
	for t in match_ref.teams:
		for p in t.players:
			if i < snap.players.size():
				var entry: Array = snap.players[i]
				(p as Node3D).position = entry[0]
				(p as Node3D).rotation.y = entry[1]
				i += 1

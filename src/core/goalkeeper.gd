class_name Goalkeeper
extends PlayerAgent
## Goalkeeper: positions between the posts, dives at shots, claims loose balls
## in the area and distributes to a full-back or a long kick upfield.

enum GKMode { POSITION, DIVE, CLAIM, DISTRIBUTE }

var gk_mode: int = GKMode.POSITION
var dive_target := Vector3.ZERO
var dive_timer := 0.0
var hold_timer := 0.0
var has_ball := false
var distribute_delay := 0.0

const DIVE_SPEED := 7.5
const REACTION_RADIUS := 16.0


func setup_gk(team_idx_: int, attack_dir_: int, anchor: Vector3) -> void:
	setup(team_idx_, 1, "GK", "goalkeeper", attack_dir_, anchor)
	is_goalkeeper = true
	max_speed = 5.4
	sprint_speed = 7.0


func think(ball: Ball, dt: float, teammates: Array, opponents: Array) -> Dictionary:
	# Returns an intention for Match to act on (e.g. {"kick": {...}}).
	var intentions := {}
	var goal_x := -attack_dir * Pitch.HALF_LENGTH
	var own_goal := Vector3(goal_x, 0.0, 0.0)
	var ball_pos := ball.global_position
	var toward_goal := ball_pos.x * attack_dir < -Pitch.HALF_LENGTH + 24.0

	if has_ball:
		hold_timer -= dt
		halt()
		if hold_timer <= 0.0:
			has_ball = false
			intentions["distribute"] = true
		return intentions

	if dive_timer > 0.0:
		dive_timer -= dt
		move_towards(dive_target, dt, true)
		return intentions

	# Shot coming towards our goal?
	var ball_vel := ball.velocity
	var incoming := ball_vel.dot((own_goal - ball_pos).normalized()) > 6.0 and ball.speed() > 8.0 and toward_goal
	if incoming:
		# Predict where the ball crosses our line; dive to intercept.
		var t := absf((goal_x - ball_pos.x) / (ball_vel.x if absf(ball_vel.x) > 0.5 else 0.5))
		t = clampf(t, 0.0, 1.4)
		var predicted := ball_pos + ball_vel * t
		predicted.z = clampf(predicted.z, -Pitch.GOAL_WIDTH * 0.5 - 1.0, Pitch.GOAL_WIDTH * 0.5 + 1.0)
		predicted.x = clampf(predicted.x, goal_x - 1.0, goal_x + 2.0)
		if position.distance_to(predicted) < REACTION_RADIUS:
			gk_mode = GKMode.DIVE
			dive_target = Vector3(predicted.x + attack_dir * 0.8, 0.0, clampf(predicted.z, -4.4, 4.4))
			dive_timer = 0.9
			return intentions

	# Claim a loose ball inside our penalty area.
	if toward_goal and ball_pos.distance_to(own_goal) < 16.0 and ball.speed() < 9.0 and not ball.is_dribbled:
		gk_mode = GKMode.CLAIM
		move_towards(ball_pos, dt, true)
		return intentions

	# Default: position on an arc between ball and goal centre, off the line.
	gk_mode = GKMode.POSITION
	var dir_ball := (ball_pos - own_goal).normalized()
	var out := clampf(2.2 + absf(ball_pos.x - goal_x) * 0.06, 1.6, 6.5)
	var spot := own_goal + dir_ball * out
	spot.z = clampf(spot.z, -Pitch.GOAL_WIDTH * 0.5, Pitch.GOAL_WIDTH * 0.5)
	move_towards(spot, dt, false)
	return intentions


func catch_ball() -> void:
	has_ball = true
	hold_timer = 1.2


func distribute_ball(ball: Ball, teammates: Array) -> void:
	# Prefer a full-back/wide midfielder in space; else a long kick to a forward.
	var best: PlayerAgent = null
	var best_score := -1e9
	for p in teammates:
		if p == self:
			continue
		var teammate := p as PlayerAgent
		var openness: float = _openness(teammate.position, teammates, [])
		var wide := absf(teammate.position.z) > 14.0
		var score: float = openness + (6.0 if wide else 0.0) - teammate.position.x * attack_dir * 0.05
		if score > best_score:
			best_score = score
			best = teammate
	var target: Vector3 = best.position if best != null else Vector3(-attack_dir * 20.0, 0, 0)
	var dir := target - global_position
	ball.global_position = global_position + Vector3(0, 1.2, 0) + dir.normalized() * 0.5
	ball.kick(dir.normalized(), 18.0, Vector3.ZERO, 0.35)


func _openness(p: Vector3, teammates: Array, opponents: Array) -> float:
	var o := 0.0
	for t in teammates:
		o += clampf((p as Vector3).distance_to((t as Node3D).position) * 0.2, 0.0, 3.0)
	for a in opponents:
		o -= clampf(6.0 - (p as Vector3).distance_to((a as Node3D).position), 0.0, 6.0)
	return o

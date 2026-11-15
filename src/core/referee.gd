class_name Referee
extends RefCounted
## Refereeing decisions: fouls from tackles, cards, the offside approximation
## and restart positioning. Pure logic; the Match orchestrator feeds it state.

var fouls := [0, 0]
var cards := [0, 0]


## Offside approximation: an attacking player is offside if, at the moment the
## pass is played, he is beyond the second-last defender and beyond the ball,
## inside the opponents' half, and closer to the opponents' goal line than both.
static func is_offside(passer_pos: Vector3, attack_dir: int, receivers: Array, defenders: Array, ball_pos: Vector3) -> Dictionary:
	# receivers: positions of players receiving (may be several candidates).
	# defenders: defender positions, sorted deepest-first by the caller.
	var result := {"offside": false, "player_idx": -1}
	if defenders.size() == 0:
		return result
	# Second-last defender line: the two deepest defenders (GK counts).
	var xs := []
	for d in defenders:
		xs.append((d as Node3D if d is Node3D else d).position.x)
	xs.sort()
	var second_last := 0.0
	var n := xs.size()
	if n >= 2:
		# The offside line is the second-last defender (GK counts as one).
		# It sits closest to the defenders' own goal, which is on the side the
		# attacking team is attacking.
		if attack_dir > 0:
			second_last = xs[n - 2]
		else:
			second_last = xs[1]
	else:
		second_last = xs[0]
	for i in receivers.size():
		var rpos: Vector3 = (receivers[i] as Node3D).position if receivers[i] is Node3D else receivers[i]
		var beyond_ball := rpos.x * attack_dir > ball_pos.x * attack_dir
		var beyond_line := rpos.x * attack_dir > second_last * attack_dir
		var in_opponent_half := rpos.x * attack_dir > 0.0
		if beyond_ball and beyond_line and in_opponent_half:
			result.offside = true
			result.player_idx = i
			return result
	return result


## Decide the outcome of a tackle attempt. Returns a decision Dictionary.
## tackle_speed: closing speed of the tackler, from_behind: angle factor,
## ball_first: true when the tackler reached the ball cleanly.
static func decide_tackle(tackle_speed: float, from_behind: float, ball_first: bool) -> Dictionary:
	var d := {"foul": false, "card": "", "advantage": false}
	if ball_first:
		# Clean tackle, but reckless speed from behind can still be a foul.
		if tackle_speed > 9.0 and from_behind > 0.75:
			d.foul = true
			d.card = "yellow"
		return d
	# Missed the ball: foul.
	d.foul = true
	if tackle_speed > 9.5 or from_behind > 0.85:
		d.card = "yellow"
	if tackle_speed > 12.0 and from_behind > 0.9:
		d.card = "red"
	return d


static func penalty_spot_for(attack_dir: int) -> Vector3:
	return Vector3(attack_dir * (Pitch.HALF_LENGTH - Pitch.PENALTY_SPOT_FROM_GOAL), 0.0, 0.0)


## Where to place the ball for a restart given the out/foul position.
static func restart_spot(phase: int, pos: Vector3, attack_dir: int) -> Vector3:
	match phase:
		MatchState.Phase.THROW_IN:
			# Just inside the detection tolerance so the ball is not immediately
			# judged out again while waiting for the throw.
			return Vector3(pos.x, 0.0, signf(pos.z) * (Pitch.HALF_WIDTH + 0.08))
		MatchState.Phase.CORNER:
			var sx := signf(pos.x) if absf(pos.x) > 0.1 else 1.0
			var sz := signf(pos.z) if absf(pos.z) > 0.1 else 1.0
			return Vector3(sx * Pitch.HALF_LENGTH, 0.0, sz * Pitch.HALF_WIDTH)
		MatchState.Phase.GOAL_KICK:
			var gx: float = (signf(pos.x) * Pitch.HALF_LENGTH) if absf(pos.x) > 0.1 else float(attack_dir)
			return Vector3(gx * (Pitch.HALF_LENGTH - Pitch.GOAL_AREA_DEPTH - 1.0), 0.0, 0.0)
		MatchState.Phase.FREE_KICK:
			return Pitch.clamp_to_pitch(pos, 0.05)
		MatchState.Phase.PENALTY:
			return penalty_spot_for(attack_dir)
	return Pitch.clamp_to_pitch(pos, 0.0)

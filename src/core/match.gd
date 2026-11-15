class_name Match
extends Node3D
## Match orchestrator: owns the two teams, the ball and the referee, runs the
## phase state machine (kick-off, play, set pieces, goals, half time, full
## time), the team AI and the local player's actions.

signal score_changed
signal phase_changed(phase: int)
signal possession_changed(team_idx: int)
signal controlled_changed(player_number: int)
signal event_banner(text: String)
signal goal_happened(team_idx: int, scorer_number: int)
signal match_ended(score_a: int, score_b: int)
signal shot_charging(power: float)
signal card_banner(team_idx: int, number: int, card: String)

var state := MatchState.new()
var teams: Array = []
var ball: Ball
var user_team_idx := 0
var controlled: PlayerAgent = null
var night := false
var difficulty := 0.5  # 0..1, scales AI decisiveness

# Input from the touch controls (or keyboard for desktop testing).
var move_vector := Vector2.ZERO
var sprint_held := false
var shoot_charge := -1.0   # -1 = not charging; 0..1 charge power
var shoot_hold_time := 0.0
var shoot_pressed := false

# Internal
var restart_timer := 0.0
var restart_taker: PlayerAgent = null
var auto_restart := false
var pending_offside_check := false
var pass_initiator: PlayerAgent = null
var last_touch_team := -1
var celebration_timer := 0.0
var kickoff_team := 0
var referee := Referee.new()
var recorder := []            # goal-replay ring buffer: {t, ball, players[]}
var recorder_capacity := 120  # ~4s at 30 Hz
var recorder_timer := 0.0
var half_length_seconds := 270.0
var match_seed := 0
var rng := RandomNumberGenerator.new()

const CARRIER_GAIN_RADIUS := 0.75
const STEAL_RADIUS := 1.1


func configure(cfg: Dictionary) -> void:
	half_length_seconds = float(cfg.get("half_length_seconds", 270.0))
	night = bool(cfg.get("night", false))
	difficulty = float(cfg.get("difficulty", 0.5))
	match_seed = int(cfg.get("seed", 0))
	user_team_idx = int(cfg.get("user_team", 0))


func _ready() -> void:
	rng.seed = match_seed if match_seed != 0 else randi()
	state.configure(half_length_seconds)
	state.phase_changed.connect(func(p: int) -> void: phase_changed.emit(p))
	teams = [Team.make(0, 1), Team.make(1, -1)]
	ball = Ball.new()
	ball.name = "Ball"
	add_child(ball)
	teams[0].build_players(self, 0)
	teams[1].build_players(self, 0)
	_apply_second_half_mirroring()
	# Kick-off positions for the very first phase.
	_setup_kickoff(0)
	controlled = teams[0].outfield_players()[7]


func _apply_second_half_mirroring() -> void:
	# attack_dir set by Team.make for half 1; flip for team identity storage is
	# handled at half time by swapping dirs.
	pass


func current_attack_dir(team_idx: int) -> int:
	return 1 if (team_idx == 0) == (state.half == 1 or state.half == 0) else -1


func _setup_kickoff(team_idx: int) -> void:
	kickoff_team = team_idx
	state.possession_team = team_idx
	state.restart_team = team_idx
	state.restart_position = Vector3.ZERO
	ball.global_position = Vector3(0, Pitch.BALL_RADIUS, 0)
	ball.velocity = Vector3.ZERO
	ball.spin = Vector3.ZERO
	ball.release_from_carrier()
	# Arrange both teams in their own halves.
	for ti in 2:
		var dir := current_attack_dir(ti)
		for p in teams[ti].players:
			if p.is_goalkeeper:
				p.position = Vector3(-dir * (Pitch.HALF_LENGTH - 1.6), 0, 0)
			else:
				var a: Vector3 = (p as PlayerAgent).base_anchor
				var pos := Vector3(a.x * 0.85, 0, a.z)
				# Keep everyone in own half; the kicking side gets two players at the spot.
				if ti == team_idx and (p as PlayerAgent).role_group == "attacker" and (p as PlayerAgent).base_anchor.x > 0.6:
					pos = Vector3(-dir * 1.0, 0, 0.6)
				# Clamp into own half.
				if dir > 0:
					pos.x = clampf(pos.x, -Pitch.HALF_LENGTH + 0.5, -0.8)
				else:
					pos.x = clampf(pos.x, 0.8, Pitch.HALF_LENGTH - 0.5)
				p.position = pos
				p.halt()
	restart_taker = _nearest_outfield(teams[team_idx], Vector3(-current_attack_dir(team_idx) * 1.0, 0, 0.6))
	if restart_taker != null:
		restart_taker.position = Vector3(-current_attack_dir(team_idx) * 1.2, 0, 0.6)
	restart_timer = 1.2
	auto_restart = false
	_pick_controlled()
	state.set_phase(MatchState.Phase.KICKOFF)


func _nearest_outfield(team: Team, to_pos: Vector3) -> PlayerAgent:
	var best: PlayerAgent = null
	var bd := 1e9
	for p in team.outfield_players():
		if (p as PlayerAgent).sent_off:
			continue
		var d: float = (p as Node3D).position.distance_to(to_pos)
		if d < bd:
			bd = d
			best = p
	return best


func _pick_controlled() -> void:
	if user_team_idx < 0 or user_team_idx > 1:
		return
	var team: Team = teams[user_team_idx]
	var best := _nearest_outfield(team, ball.global_position)
	if best != null and best != controlled:
		controlled = best
		controlled_changed.emit(controlled.number)


func _physics_process(dt: float) -> void:
	if state.is_over():
		return
	recorder_tick(dt)
	match state.phase:
		MatchState.Phase.PRE_MATCH:
			return
		MatchState.Phase.KICKOFF:
			_tick_kickoff(dt)
		MatchState.Phase.PLAYING:
			_tick_playing(dt)
		MatchState.Phase.THROW_IN, MatchState.Phase.CORNER, MatchState.Phase.GOAL_KICK, MatchState.Phase.FREE_KICK:
			_tick_restart(dt)
		MatchState.Phase.PENALTY:
			_tick_penalty(dt)
		MatchState.Phase.GOAL_SCORED:
			_tick_celebration(dt)
		MatchState.Phase.HALF_TIME:
			_tick_half_time(dt)
	# The clock runs during restarts and kick-off waits (football rules); the
	# state object itself decides which phases the clock may advance in.
	state.tick_gameplay(dt)


func recorder_tick(dt: float) -> void:
	recorder_timer -= dt
	if recorder_timer > 0.0:
		return
	recorder_timer = 1.0 / 30.0
	var snapshot := {"ball": ball.global_position, "players": []}
	for t in teams:
		for p in t.players:
			snapshot.players.append([(p as Node3D).position, (p as Node3D).rotation.y])
	recorder.append(snapshot)
	if recorder.size() > recorder_capacity:
		recorder.pop_front()


# ------------------------------------------------------------------ kick-off

func _tick_kickoff(dt: float) -> void:
	ball.is_dribbled = true
	ball.carrier = restart_taker
	_all_players_hold(dt)
	restart_timer -= dt
	var user_is_taker := restart_taker != null and restart_taker.team_idx == user_team_idx
	if (user_is_taker and _user_pass_requested()) or restart_timer <= 0.0:
		_execute_kickoff_pass()


func _user_pass_requested() -> bool:
	return shoot_pressed or shoot_charge >= 0.0 or move_vector.length() > 0.4


func _execute_kickoff_pass() -> void:
	var dir := current_attack_dir(kickoff_team)
	ball.release_from_carrier()
	shoot_charge = -1.0
	shoot_pressed = false
	var mate: PlayerAgent = null
	for p in teams[kickoff_team].outfield_players():
		if p != restart_taker and p.role_group != "defender":
			mate = p
			break
	var target: Vector3 = mate.position if mate != null else Vector3(dir * 10, 0, 0)
	var d := target - ball.global_position
	ball.kick(d.normalized(), 9.0)
	last_touch_team = kickoff_team
	state.set_phase(MatchState.Phase.PLAYING)
	state.possession_team = kickoff_team
	possession_changed.emit(kickoff_team)
	_pick_controlled()


func _all_players_hold(dt: float) -> void:
	for t in teams:
		for p in t.players:
			if not (p is Goalkeeper):
				(p as PlayerAgent).halt()


# ------------------------------------------------------------------- playing

func _tick_playing(dt: float) -> void:
	if shoot_pressed and shoot_charge < 0.0:
		shoot_charge = 0.0
		shoot_hold_time = 0.0
	if shoot_charge >= 0.0:
		shoot_hold_time += dt
		shoot_charge = clampf(shoot_hold_time / 0.9, 0.0, 1.0)
		shot_charging.emit(shoot_charge)

	_update_possession(dt)
	_update_controlled()
	for ti in 2:
		_update_team_ai(ti, dt)
	_tick_user_actions(dt)
	_check_ball_events()
	_check_goal()


func _update_possession(dt: float) -> void:
	if ball.carrier != null:
		var c := ball.carrier as PlayerAgent
		# Loose the ball if tackled away (handled in tackle) or too far.
		if c.position.distance_to(ball.global_position) > 2.2:
			ball.release_from_carrier()
		else:
			ball.stick_to_carrier()
			last_touch_team = c.team_idx
		return
	# Loose ball: closest player within gain radius gains possession.
	var candidates := []
	for t in teams:
		for p in t.players:
			if (p as PlayerAgent).sent_off:
				continue
			var d: float = (p as Node3D).position.distance_to(ball.global_position)
			if d < (CARRIER_GAIN_RADIUS if ball.speed() < 14.0 else 0.55):
				candidates.append([d, p])
	if candidates.size() > 0:
		candidates.sort_custom(func(a, b): return a[0] < b[0])
		var p: PlayerAgent = candidates[0][1]
		if p.is_goalkeeper:
			var gk := p as Goalkeeper
			if ball.global_position.distance_to(Vector3(-current_attack_dir(p.team_idx) * Pitch.HALF_LENGTH, 0, 0)) < 20.0:
				gk.catch_ball()
				ball.global_position = p.position + Vector3(0, 1.0, 0)
				ball.velocity = Vector3.ZERO
				last_touch_team = p.team_idx
			return
		_gain_possession(p)


func _gain_possession(p: PlayerAgent) -> void:
	ball.carrier = p
	ball.is_dribbled = true
	last_touch_team = p.team_idx
	state.scorer_number = p.number
	state.possession_team = p.team_idx
	possession_changed.emit(p.team_idx)
	if p.team_idx == user_team_idx:
		controlled = p
		controlled_changed.emit(p.number)


func _update_controlled() -> void:
	if controlled == null or controlled.sent_off or controlled.is_goalkeeper:
		_pick_controlled()


func _update_team_ai(ti: int, dt: float) -> void:
	var team: Team = teams[ti]
	var attack_dir := current_attack_dir(ti)
	var has_possession: bool = state.possession_team == ti and ball.carrier != null
	var opponents: Array = teams[1 - ti].players
	var ball_pos := ball.global_position

	for p in team.players:
		if (p as PlayerAgent).sent_off:
			continue
		if p.is_goalkeeper:
			var intentions: Dictionary = (p as Goalkeeper).think(ball, dt, team.players, opponents)
			if intentions.has("distribute"):
				(p as Goalkeeper).distribute_ball(ball, team.players)
				last_touch_team = ti
			continue
		var agent := p as PlayerAgent
		if ball.carrier == agent:
			if ti == user_team_idx and agent == controlled:
				_dribble_user(agent, dt)
			else:
				_ai_carrier(agent, attack_dir, opponents, team, dt)
		elif ball.carrier != null and ball.carrier.team_idx == ti:
			# Team-mate of carrier: off-ball runs and support.
			_ai_off_ball_attack(agent, attack_dir, opponents, team, ball_pos, dt)
		elif ball.carrier == null:
			# Loose ball: nearest one or two chases.
			_ai_loose_ball(agent, team, ball_pos, dt)
		else:
			# Defending.
			_ai_defend(agent, team, opponents, ball_pos, dt)


func _dribble_user(agent: PlayerAgent, dt: float) -> void:
	# The stick moves the carrier; otherwise he shields the ball.
	if move_vector.length() > 0.15:
		var dir := Vector3(move_vector.x, 0, move_vector.y)
		var cam_rel := _camera_relative_dir(dir)
		agent.move_towards(agent.position + cam_rel * 6.0, dt, sprint_held and agent.stamina > 0.15)
		agent.sprinting = sprint_held and move_vector.length() > 0.85
	else:
		agent.halt()
	agent.sprinting = sprint_held and move_vector.length() > 0.85


func _camera_relative_dir(dir: Vector3) -> Vector3:
	# Broadcast camera looks roughly along -Z; keep stick-relative to world with
	# a slight lateral inversion for naturalness.
	return Vector3(dir.x, 0, dir.y)


func _ai_carrier(agent: PlayerAgent, attack_dir: int, opponents: Array, team: Team, dt: float) -> void:
	var goal := Vector3(attack_dir * Pitch.HALF_LENGTH, 0, 0)
	var dist_goal := agent.position.distance_to(goal)
	var pressure := _nearest_opponent_distance(agent, opponents)
	agent.sprinting = agent.stamina > 0.3 and pressure < 3.5

	# Shoot if in range with a partially clear lane.
	if dist_goal < 26.0 and _shot_lane_clear(agent, goal, opponents) and rng.randf() < (0.02 + difficulty * 0.05):
		_ai_shoot(agent, goal, opponents)
		return
	# Pass options.
	var options := _pass_options(agent, team, opponents, attack_dir)
	if pressure < 2.2 and options.size() > 0 and rng.randf() < 0.10 + difficulty * 0.10:
		_execute_ai_pass(agent, options[0], attack_dir)
		return
	if dist_goal < 34.0 and options.size() > 0 and rng.randf() < 0.03 + difficulty * 0.04:
		_execute_ai_pass(agent, options[0], attack_dir)
		return
	# Dribble toward goal, veering away from the nearest defender.
	var dir := (goal - agent.position)
	dir.y = 0.0
	dir = dir.normalized()
	for o in opponents:
		var od: Vector3 = agent.position - (o as Node3D).position
		od.y = 0.0
		if od.length() < 4.0:
			dir += od.normalized() * (4.0 - od.length()) * 0.25
	dir.y = 0.0
	agent.move_towards(agent.position + dir.normalized() * 5.0, dt, agent.sprinting)


func _nearest_opponent_distance(agent: PlayerAgent, opponents: Array) -> float:
	var best := 1e9
	for o in opponents:
		var d: float = agent.position.distance_to((o as Node3D).position)
		if d < best:
			best = d
	return best


func _shot_lane_clear(agent: PlayerAgent, goal: Vector3, opponents: Array) -> bool:
	var dir := (goal - agent.position).normalized()
	for o in opponents:
		var rel: Vector3 = (o as Node3D).position - agent.position
		var along := rel.dot(dir)
		if along > 1.0 and along < agent.position.distance_to(goal):
			var lateral := (rel - dir * along).length()
			if lateral < 1.3:
				return false
	return true


func _pass_options(agent: PlayerAgent, team: Team, opponents: Array, attack_dir: int) -> Array:
	var opts := []
	for m in team.players:
		if m == agent or (m as PlayerAgent).sent_off:
			continue
		var mate := m as PlayerAgent
		var to_mate := mate.position - agent.position
		var advance: float = (mate.position.x - agent.position.x) * attack_dir
		var openness := 0.0
		for o in opponents:
			var rel: Vector3 = mate.position - (o as Node3D).position
			openness += clampf(rel.length() - 3.0, -6.0, 6.0)
		var lane_clear := _pass_lane_clear(agent.position, mate.position, opponents)
		var score := openness * 0.5 + advance * 0.7 + (8.0 if lane_clear else -9.0)
		if to_mate.length() > 45.0:
			score -= 8.0
		opts.append({"player": mate, "score": score, "through": mate.role_group == "attacker" and advance > 8.0})
	opts.sort_custom(func(a, b): return a.score > b.score)
	return opts


func _pass_lane_clear(from: Vector3, to: Vector3, opponents: Array) -> bool:
	var dir := (to - from).normalized()
	var len := from.distance_to(to)
	for o in opponents:
		var rel: Vector3 = (o as Node3D).position - from
		var along := rel.dot(dir)
		if along > 0.5 and along < len - 0.5:
			if (rel - dir * along).length() < 1.1:
				return false
	return true


func _execute_ai_pass(agent: PlayerAgent, option: Dictionary, attack_dir: int) -> void:
	var mate: PlayerAgent = option.player
	var target := mate.position + Vector3(attack_dir * 4.0 if option.through else 0.0, 0, 0)
	# Offside check at the moment of the pass.
	var offside := Referee.is_offside(agent.position, attack_dir, [mate], teams[1 - agent.team_idx].players, ball.global_position)
	var dir := target - agent.position
	dir.y = 0.0
	var d := dir.length()
	var power := clampf(8.0 + d * 0.55, 8.0, 26.0)
	ball.release_from_carrier()
	ball.kick(dir.normalized(), power, Vector3(0, 0, 0) if not option.through else Vector3(0, -0.4, 0), 0.04 + d * 0.002)
	last_touch_team = agent.team_idx
	pass_initiator = agent
	if offside.offside:
		# Flag raised as the ball arrives.
		_schedule_offside_call(agent, mate)


func _schedule_offside_call(offender: PlayerAgent, _mate: PlayerAgent) -> void:
	# Simplified: award the free kick to the opponents after a short delay.
	if get_tree() == null:
		return
	await get_tree().create_timer(0.8).timeout
	if state.phase == MatchState.Phase.PLAYING:
		var text := "Offside - %s %d" % [teams[offender.team_idx].short_name, offender.number]
		event_banner.emit(text)
		_award_free_kick(1 - offender.team_idx, offender.position)


func _ai_shoot(agent: PlayerAgent, goal: Vector3, opponents: Array) -> void:
	var aim := goal + Vector3(0, 0, rng.randf_range(-3.2, 3.2))
	state.scorer_number = agent.number
	var dir := aim - ball.global_position
	var power := clampf(agent.position.distance_to(goal) * 0.75 + 8.0, 14.0, 30.0)
	var curve := Vector3(0, 0, rng.randf_range(-1.2, 1.2)) if rng.randf() < 0.4 else Vector3.ZERO
	ball.release_from_carrier()
	ball.kick(dir.normalized(), power, curve, 0.12)
	last_touch_team = agent.team_idx
	agent.celebrate_timer = 0.0


func _ai_off_ball_attack(agent: PlayerAgent, attack_dir: int, opponents: Array, team: Team, ball_pos: Vector3, dt: float) -> void:
	var anchor := Formation.shifted_anchor(agent.base_anchor, attack_dir, ball_pos, 0.35)
	# Attackers make runs in behind when the carrier is advanced.
	if agent.role_group == "attacker":
		var carrier_advanced: bool = ball.carrier != null and ball.carrier.position.x * attack_dir > 12.0
		if carrier_advanced and agent.stamina > 0.4:
			anchor = Vector3(attack_dir * (Pitch.HALF_LENGTH - 8.0), 0, agent.base_anchor.z + rng.randf_range(-2.0, 2.0))
			anchor.x = clampf(anchor.x, -Pitch.HALF_LENGTH + 3.0, Pitch.HALF_LENGTH - 3.0)
			agent.sprinting = agent.stamina > 0.55
	agent.move_towards(anchor, dt, agent.sprinting)


func _ai_loose_ball(agent: PlayerAgent, team: Team, ball_pos: Vector3, dt: float) -> void:
	# Nearest two players of each team chase a loose ball; others hold shape.
	var rank := _chase_rank(agent, team, ball_pos)
	if rank <= 1:
		agent.sprinting = agent.stamina > 0.25
		# Lead the ball slightly.
		var intercept := ball_pos + ball.velocity * clampf(agent.position.distance_to(ball_pos) * 0.09, 0.0, 0.8)
		agent.move_towards(intercept, dt, agent.sprinting)
	else:
		var anchor := Formation.shifted_anchor(agent.base_anchor, current_attack_dir(team_idx_of(team)), ball_pos, 0.3)
		agent.move_towards(anchor, dt, false)


func team_idx_of(team: Team) -> int:
	return 0 if team == teams[0] else 1


func _chase_rank(agent: PlayerAgent, team: Team, ball_pos: Vector3) -> int:
	var rank := 0
	var my_d := agent.position.distance_to(ball_pos)
	for p in team.outfield_players():
		if p == agent:
			continue
		if (p as PlayerAgent).position.distance_to(ball_pos) < my_d:
			rank += 1
	return rank


func _ai_defend(agent: PlayerAgent, team: Team, opponents: Array, ball_pos: Vector3, dt: float) -> void:
	var attack_dir := current_attack_dir(team_idx_of(team))
	var rank := _chase_rank(agent, team, ball_pos)
	if rank == 0:
		# Press the carrier.
		var carrier := ball.carrier as PlayerAgent
		agent.sprinting = agent.stamina > 0.2
		agent.move_towards(carrier.position, dt, agent.sprinting)
		if agent.position.distance_to(carrier.position) < 1.25 and agent.tackle_cooldown <= 0.0:
			_attempt_tackle(agent, carrier)
	elif rank == 1 and team.secondary_press:
		agent.sprinting = agent.stamina > 0.3
		agent.move_towards(ball_pos, dt, agent.sprinting)
	else:
		# Mark the nearest free opponent attacker, else hold the shifted block.
		var marked := _mark_target(agent, team, opponents)
		if marked != null:
			var between := marked.position + (Vector3(current_attack_dir(team_idx_of(team)) * Pitch.HALF_LENGTH, 0, 0) - marked.position).normalized() * 1.6
			agent.move_towards(between, dt, false)
		else:
			var anchor := Formation.shifted_anchor(agent.base_anchor, current_attack_dir(team_idx_of(team)), ball_pos, 0.45)
			agent.move_towards(anchor, dt, false)


func _mark_target(agent: PlayerAgent, team: Team, opponents: Array) -> PlayerAgent:
	var best: PlayerAgent = null
	var bd := 22.0
	for o in opponents:
		var op := o as PlayerAgent
		if op.sent_off or op.is_goalkeeper:
			continue
		if op.role_group != "attacker" and not (agent.role_group == "defender" and op.role_group == "midfielder"):
			continue
		var d: float = agent.position.distance_to(op.position)
		if d < bd:
			bd = d
			best = op
	return best


func _attempt_tackle(tackler: PlayerAgent, carrier: PlayerAgent) -> void:
	tackler.tackle_cooldown = 1.3
	var closing := tackler.current_speed
	var behind := 0.0
	var to_carrier := (carrier.position - tackler.position).normalized()
	var carrier_facing := Vector3(-cos(carrier.rotation.y), 0, -sin(carrier.rotation.y))
	# from_behind ~ 1 when the tackler approaches from directly behind the carrier.
	behind = clampf(0.5 + 0.5 * to_carrier.dot(carrier_facing), 0.0, 1.0)
	var ball_first := rng.randf() < clampf(0.55 + (1.0 - behind) * 0.35 - closing * 0.01, 0.15, 0.9)
	var decision := Referee.decide_tackle(closing, behind, ball_first)
	if decision.foul:
		var pos := tackler.position
		if decision.card != "":
			referee.cards[tackler.team_idx] += 1
			card_banner.emit(tackler.team_idx, tackler.number, decision.card)
		var dir_of_carrier := current_attack_dir(carrier.team_idx)
		var phase := MatchState.Phase.PENALTY if Pitch.in_penalty_area(pos, dir_of_carrier == 1) else MatchState.Phase.FREE_KICK
		_award_set_piece(phase, 1 - tackler.team_idx, pos)
	else:
		# Clean tackle: ball pops loose.
		ball.release_from_carrier()
		var pop := ball.global_position - tackler.position
		pop.y = 0.0
		ball.kick(pop.normalized() + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4)), rng.randf_range(3.0, 6.0))
		last_touch_team = tackler.team_idx


func _award_free_kick(team_idx: int, pos: Vector3) -> void:
	_award_set_piece(MatchState.Phase.FREE_KICK, team_idx, pos)


# -------------------------------------------------------------- user actions

func _tick_user_actions(dt: float) -> void:
	if controlled == null or controlled.sent_off or ball.carrier != controlled:
		if shoot_charge >= 0.0 and not shoot_pressed:
			shoot_charge = -1.0
			shot_charging.emit(-1.0)
		return
	if shoot_charge >= 0.0 and not shoot_pressed:
		_release_shot()
	shoot_pressed = false


func _release_shot() -> void:
	var power := lerpf(12.0, 30.0, shoot_charge)
	state.scorer_number = controlled.number
	var dir := _camera_relative_dir(Vector3(move_vector.x, 0, move_vector.y)) if move_vector.length() > 0.2 else Vector3(current_attack_dir(controlled.team_idx), 0, 0)
	# Aim at goal when facing it.
	var goal := Vector3(current_attack_dir(controlled.team_idx) * Pitch.HALF_LENGTH, 0, 0)
	if controlled.position.distance_to(goal) < 30.0:
		var to_goal := (goal - controlled.position).normalized()
		dir = (to_goal * 0.65 + dir * 0.35).normalized()
	var curve := Vector3(0, 0, move_vector.x * 0.9) if absf(move_vector.x) > 0.4 else Vector3.ZERO
	ball.release_from_carrier()
	ball.kick(dir, power, curve, lerpf(0.05, 0.3, shoot_charge))
	last_touch_team = controlled.team_idx
	shoot_charge = -1.0
	shot_charging.emit(-1.0)


func action_pass() -> void:
	if controlled == null or controlled.sent_off:
		return
	if ball.carrier == controlled:
		_user_pass(false)
	elif state.phase in [MatchState.Phase.KICKOFF, MatchState.Phase.THROW_IN, MatchState.Phase.CORNER, MatchState.Phase.GOAL_KICK, MatchState.Phase.FREE_KICK] and restart_taker == controlled:
		auto_restart = true


func action_through() -> void:
	if controlled == null or ball.carrier != controlled:
		return
	_user_pass(true)


func action_lob() -> void:
	if controlled == null or ball.carrier != controlled:
		return
	# Cross into the box when wide, else a lofted pass forward.
	var team: Team = teams[controlled.team_idx]
	var target: PlayerAgent = null
	var bd := 1e9
	var box_center := Vector3(current_attack_dir(controlled.team_idx) * (Pitch.HALF_LENGTH - 8.0), 0, 0)
	for p in team.outfield_players():
		if p == controlled:
			continue
		var d: float = (p as PlayerAgent).position.distance_to(box_center)
		if d < bd:
			bd = d
			target = p
	var dir := (target.position - controlled.position) if target != null else Vector3(current_attack_dir(controlled.team_idx), 0, 0)
	dir.y = 0.0
	ball.release_from_carrier()
	ball.kick(dir.normalized(), clampf(dir.length() * 0.5 + 8.0, 10.0, 24.0), Vector3.ZERO, 0.42)
	last_touch_team = controlled.team_idx


func _user_pass(through: bool) -> void:
	var attack_dir := current_attack_dir(controlled.team_idx)
	var team: Team = teams[controlled.team_idx]
	var options := _pass_options(controlled, team, teams[1 - controlled.team_idx].players, attack_dir)
	if options.is_empty():
		return
	var chosen: Dictionary = options[0]
	# Bias to the stick direction when the player points somewhere.
	if move_vector.length() > 0.4:
		var stick := _camera_relative_dir(Vector3(move_vector.x, 0, move_vector.y)).normalized()
		var best_score := -1e9
		for o in options:
			var mate: PlayerAgent = o.player
			var to_mate := (mate.position - controlled.position)
			to_mate.y = 0.0
			if to_mate.length() < 0.5:
				continue
			var align := to_mate.normalized().dot(stick)
			var score: float = align * 10.0 + o.score * 0.1
			if score > best_score:
				best_score = score
				chosen = o
	var mate: PlayerAgent = chosen.player
	var lead := mate.position + (Vector3(attack_dir * 5.0, 0, 0) if through else Vector3.ZERO) + ball.velocity * 0.15
	var offside := Referee.is_offside(controlled.position, attack_dir, [mate], teams[1 - controlled.team_idx].players, ball.global_position)
	var dir := lead - controlled.position
	dir.y = 0.0
	var d := dir.length()
	ball.release_from_carrier()
	ball.kick(dir.normalized(), clampf(8.0 + d * 0.6, 8.0, 26.0), Vector3.ZERO, 0.06 if through else 0.03)
	last_touch_team = controlled.team_idx
	if offside.offside:
		_schedule_offside_call(mate, mate)


func action_shoot_start() -> void:
	shoot_pressed = true


func action_shoot_cancel() -> void:
	shoot_charge = -1.0
	shoot_pressed = false
	shot_charging.emit(-1.0)


func action_sprint(pressed: bool) -> void:
	sprint_held = pressed


func action_tackle() -> void:
	# Contextual: when defending, the controlled player lunges at the ball.
	if controlled == null or controlled.sent_off or state.phase != MatchState.Phase.PLAYING:
		return
	if ball.carrier != null and ball.carrier.team_idx != user_team_idx:
		if controlled.tackle_cooldown <= 0.0 and controlled.position.distance_to((ball.carrier as Node3D).position) < 2.4:
			_attempt_tackle(controlled, ball.carrier as PlayerAgent)
	else:
		# Ball loose or ours: lunge to intercept.
		if controlled.position.distance_to(ball.global_position) < 3.0:
			ball.is_dribbled = false
			ball.kick((ball.global_position - controlled.position).normalized() + Vector3.UP * 0.05, 4.0)


# ------------------------------------------------------------------ restarts

func _award_set_piece(phase: int, team_idx: int, pos: Vector3) -> void:
	state.restart_team = team_idx
	var spot := Referee.restart_spot(phase, pos, current_attack_dir(team_idx))
	state.restart_position = spot
	ball.release_from_carrier()
	ball.velocity = Vector3.ZERO
	ball.spin = Vector3.ZERO
	ball.global_position = spot + Vector3(0, Pitch.BALL_RADIUS, 0)
	restart_taker = _nearest_outfield(teams[team_idx], spot)
	if phase == MatchState.Phase.GOAL_KICK or phase == MatchState.Phase.PENALTY:
		restart_taker = teams[team_idx].goalkeeper() if phase == MatchState.Phase.GOAL_KICK else _best_penalty_taker(teams[team_idx])
	restart_timer = 1.4
	auto_restart = false
	state.set_phase(phase)
	event_banner.emit(_phase_label(phase, team_idx))


func _phase_label(phase: int, team_idx: int) -> String:
	match phase:
		MatchState.Phase.THROW_IN: return "Throw-in - %s" % teams[team_idx].short_name
		MatchState.Phase.CORNER: return "Corner - %s" % teams[team_idx].short_name
		MatchState.Phase.GOAL_KICK: return "Goal kick - %s" % teams[team_idx].short_name
		MatchState.Phase.FREE_KICK: return "Free kick - %s" % teams[team_idx].short_name
		MatchState.Phase.PENALTY: return "Penalty - %s" % teams[team_idx].short_name
	return ""


func _best_penalty_taker(team: Team) -> PlayerAgent:
	var best: PlayerAgent = null
	var best_n := -1
	for p in team.outfield_players():
		var n := int(p.role.substr(2)) if p.role.begins_with("ST") else 0
		if n > best_n:
			best_n = n
			best = p
	return best if best != null else team.outfield_players()[0]


func _tick_restart(dt: float) -> void:
	if restart_taker == null or restart_taker.sent_off:
		restart_taker = _nearest_outfield(teams[state.restart_team], state.restart_position)
		if restart_taker == null:
			return
	restart_taker.move_towards(state.restart_position + Vector3(-current_attack_dir(state.restart_team) * 1.1, 0, 0), dt, false)
	restart_timer -= dt
	var user_is_taker := restart_taker.team_idx == user_team_idx
	ball.global_position = state.restart_position + Vector3(0, Pitch.BALL_RADIUS, 0)
	if (not user_is_taker and restart_timer <= 0.0) or auto_restart or (user_is_taker and restart_timer < -5.0):
		_execute_restart()


func _execute_restart() -> void:
	var team_idx := state.restart_team
	var phase := state.phase
	var dir := current_attack_dir(team_idx)
	ball.release_from_carrier()
	match phase:
		MatchState.Phase.THROW_IN:
			var mate := _nearest_outfield(teams[team_idx], ball.global_position + Vector3(dir * 4, 0, 0))
			var d := (mate.position if mate != null else ball.global_position + Vector3(dir * 6, 0, 0)) - ball.global_position
			d.y = 0.0
			ball.kick(d.normalized(), clampf(d.length() * 0.7 + 4.0, 5.0, 14.0), Vector3.ZERO, 0.35)
		MatchState.Phase.CORNER:
			var target := Vector3(dir * (Pitch.HALF_LENGTH - 6.0), 0, rng.randf_range(-4.0, 4.0))
			var d := target - ball.global_position
			d.y = 0.0
			ball.kick(d.normalized(), clampf(d.length() * 0.55 + 6.0, 12.0, 22.0), Vector3(0, rng.randf_range(-0.6, 0.6), 0), 0.3)
		MatchState.Phase.GOAL_KICK:
			teams[team_idx].goalkeeper().distribute_ball(ball, teams[team_idx].players)
		MatchState.Phase.FREE_KICK:
			var options := _pass_options(restart_taker, teams[team_idx], teams[1 - team_idx].players, dir)
			if restart_taker.position.distance_to(Vector3(dir * Pitch.HALF_LENGTH, 0, 0)) < 30.0 and rng.randf() < 0.5:
				_ai_shoot(restart_taker, Vector3(dir * Pitch.HALF_LENGTH, 0, 0), teams[1 - team_idx].players)
			elif options.size() > 0:
				_execute_ai_pass(restart_taker, options[0], dir)
			else:
				var d := Vector3(dir * 10, 0, 0) - ball.global_position
				d.y = 0.0
				ball.kick(d.normalized(), 12.0)
	last_touch_team = team_idx
	state.set_phase(MatchState.Phase.PLAYING)
	state.possession_team = team_idx
	possession_changed.emit(team_idx)
	if user_team_idx == team_idx:
		_pick_controlled()


func _tick_penalty(dt: float) -> void:
	var taker := restart_taker
	if taker == null:
		return
	ball.global_position = state.restart_position + Vector3(0, Pitch.BALL_RADIUS, 0)
	taker.move_towards(state.restart_position + Vector3(-current_attack_dir(state.restart_team) * 1.4, 0, 0), dt, false)
	restart_timer -= dt
	var user_is_taker := taker.team_idx == user_team_idx
	if shoot_pressed and shoot_charge < 0.0:
		shoot_charge = 0.0
		shoot_hold_time = 0.0
	if shoot_charge >= 0.0:
		shoot_hold_time += dt
		shoot_charge = clampf(shoot_hold_time / 0.9, 0.0, 1.0)
		shot_charging.emit(shoot_charge)
	if shoot_charge >= 0.0 and not shoot_pressed:
		_execute_penalty(taker, lerpf(0.6, 1.0, shoot_charge))
		shoot_pressed = false
	elif (not user_is_taker and restart_timer <= 0.0) or (user_is_taker and restart_timer < -6.0):
		_execute_penalty(taker, rng.randf_range(0.7, 1.0))


func _execute_penalty(taker: PlayerAgent, power_factor: float) -> void:
	var dir := current_attack_dir(taker.team_idx)
	var aim_z := rng.randf_range(-3.0, 3.0) if taker.team_idx != user_team_idx else rng.randf_range(-3.0, 3.0)
	ball.release_from_carrier()
	ball.kick(Vector3(dir, 0.18, aim_z * 0.22).normalized(), 22.0 * power_factor, Vector3.ZERO, 0.12)
	last_touch_team = taker.team_idx
	shoot_charge = -1.0
	shot_charging.emit(-1.0)
	state.set_phase(MatchState.Phase.PLAYING)


# --------------------------------------------------------------------- goals

func _check_goal() -> void:
	var p := ball.global_position
	if absf(p.z) >= Pitch.GOAL_WIDTH * 0.5 - 0.05 and absf(p.x) > Pitch.HALF_LENGTH - 0.05:
		return  # wide of the posts: handled by out-of-play
	if absf(p.x) > Pitch.HALF_LENGTH + 0.3 and absf(p.z) < Pitch.GOAL_WIDTH * 0.5 and p.y < Pitch.GOAL_HEIGHT + 0.1:
		var scoring_side := 0 if p.x > 0 else 1  # team 0 attacks +x in half 1
		var scoring_team := _team_attacking_side(scoring_side)
		var own_goal := last_touch_team != scoring_team
		var scored_team := (1 - scoring_team) if own_goal else scoring_team
		if state.phase == MatchState.Phase.PLAYING:
			state.register_goal(scored_team, state.scorer_number)
			goal_happened.emit(scored_team, state.scorer_number)
			celebration_timer = 6.0
			ball.velocity *= 0.15


func _team_attacking_side(side: int) -> int:
	# side 0 = +x goal, side 1 = -x goal.
	for ti in 2:
		if (current_attack_dir(ti) > 0 and side == 0) or (current_attack_dir(ti) < 0 and side == 1):
			return ti
	return 0


func _tick_celebration(dt: float) -> void:
	celebration_timer -= dt
	ball.velocity *= 0.9
	if celebration_timer <= 0.0:
		_setup_kickoff(1 - state.last_goal_team)


func _check_ball_events() -> void:
	var p := ball.global_position
	if Pitch.inside_pitch(p, 0.1):
		return
	var out_phase := state.ball_out(p, last_touch_team)
	if out_phase < 0:
		return
	if absf(p.x) > Pitch.HALF_LENGTH and absf(p.z) < Pitch.GOAL_WIDTH * 0.5 and p.y < Pitch.GOAL_HEIGHT:
		return  # in the goal
	var team_idx := 0
	match out_phase:
		MatchState.Phase.THROW_IN:
			team_idx = 1 - last_touch_team if last_touch_team >= 0 else 0
		MatchState.Phase.CORNER, MatchState.Phase.GOAL_KICK:
			var defending_side := 0 if p.x > 0 else 1
			var attacking_that_goal := _team_attacking_side(defending_side)
			var defending := 1 - attacking_that_goal
			team_idx = defending if out_phase == MatchState.Phase.GOAL_KICK else attacking_that_goal
	_award_set_piece(out_phase, team_idx, p)


# ----------------------------------------------------------------- half time

func _tick_half_time(_dt: float) -> void:
	pass


func start_second_half() -> void:
	# Mirror attack directions.
	for ti in 2:
		var team: Team = teams[ti]
		team.attack_dir = -team.attack_dir
		for p in team.players:
			(p as PlayerAgent).attack_dir = team.attack_dir
			p.base_anchor.x = -p.base_anchor.x
	state.start_second_half()
	_setup_kickoff(1)
	event_banner.emit("Second half")


func end_match_if_ready() -> void:
	if state.phase == MatchState.Phase.FULL_TIME:
		match_ended.emit(state.score[0], state.score[1])


func score_display() -> String:
	return "%d - %d" % [state.score[0], state.score[1]]

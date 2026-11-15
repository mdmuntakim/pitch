extends SceneTree
## Automated engine-side tests for Matchday Eleven.
## Run: godot --headless -s tests/run_tests.gd
## Exits 0 on success, 1 on failure. No rendering needed.

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	# Give the engine one frame so imports/class cache settle.
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	test_ball_physics()
	test_match_state()
	test_formations()
	test_referee()
	test_offside()
	test_input_mapping()
	await test_match_smoke()
	if failures.is_empty():
		print("ALL TESTS PASSED (%d checks)" % checks)
		quit(0)
	else:
		for f in failures:
			print("FAIL: " + f)
		print("%d checks, %d failures" % [checks, failures.size()])
		quit(1)


func check(cond: bool, label: String) -> void:
	checks += 1
	if not cond:
		failures.append(label)
		print("  fail: " + label)
	else:
		print("  ok: " + label)


# ------------------------------------------------------------------- ball

func test_ball_physics() -> void:
	print("ball physics")
	var b := Ball.new()
	root.add_child(b)
	b.global_position = Vector3(0, 20, 0)
	b.velocity = Vector3(5, 0, 0)
	var y_prev := 20.0
	var fell := false
	for i in 1500:
		b.step(1.0 / 60.0)
		if i > 10 and b.global_position.y < y_prev and absf(b.velocity.y) < 0.02 and b.global_position.y <= Pitch.BALL_RADIUS + 0.05:
			fell = true
		y_prev = b.global_position.y
	check(fell, "ball falls to ground and settles")
	check(b.global_position.y <= Pitch.BALL_RADIUS + 0.02, "ball rests at pitch height")
	# Rolling friction: rolling ball decelerates but does not stop instantly.
	b.velocity = Vector3(10, 0, 0)
	var v0 := 10.0
	for i in 120:
		b.step(1.0 / 60.0)
	check(b.velocity.x > 0.5 and b.velocity.x < v0, "rolling friction decelerates smoothly (%.2f)" % b.velocity.x)
	# Bounce: dropped ball bounces back up at least once.
	b.velocity = Vector3(0, -15, 0)
	var max_after := 0.0
	for i in 120:
		b.step(1.0 / 60.0)
		max_after = maxf(max_after, b.global_position.y)
	check(max_after > Pitch.BALL_RADIUS + 0.3, "ball bounces after impact")
	# Spin curves the ball: two kicks with/without spin diverge.
	var b1 := Ball.new()
	root.add_child(b1)
	var b2 := Ball.new()
	root.add_child(b2)
	b1.global_position = Vector3.ZERO
	b2.global_position = Vector3.ZERO
	b1.kick(Vector3(0, 0, -1), 20.0, Vector3(0, 6, 0), 0.0)
	b2.kick(Vector3(0, 0, -1), 20.0, Vector3.ZERO, 0.0)
	for i in 60:
		b1.step(1.0 / 60.0)
		b2.step(1.0 / 60.0)
	check(b1.global_position.distance_to(b2.global_position) > 0.5, "spin produces lateral curve")
	# Post deflection.
	var b3 := Ball.new()
	root.add_child(b3)
	b3.global_position = Vector3(Pitch.HALF_LENGTH - 0.6, 1.0, Pitch.GOAL_WIDTH * 0.5)
	b3.velocity = Vector3(12, 0, 0)
	for i in 40:
		b3.step(1.0 / 60.0)
	check(b3.velocity.x < 0.0 or absf(b3.global_position.z) > Pitch.GOAL_WIDTH * 0.5, "post deflects the ball")
	b.queue_free()
	b1.queue_free()
	b2.queue_free()
	b3.queue_free()


# ------------------------------------------------------------ match state

func test_match_state() -> void:
	print("match state")
	var s := MatchState.new()
	s.configure(360.0)
	s.start_match()
	check(s.half == 1 and s.phase == MatchState.Phase.KICKOFF, "match starts at kick-off, half 1")
	for i in 400:
		s.tick_gameplay(1.0)
	check(s.phase == MatchState.Phase.PLAYING or s.clock_seconds > 0.0, "clock advances during play")
	s.clock_seconds = 359.0
	s.tick_gameplay(2.0)
	check(s.phase == MatchState.Phase.HALF_TIME, "half time after first half length")
	s.start_second_half()
	check(s.half == 2 and s.phase == MatchState.Phase.KICKOFF, "second half kick-off")
	check(s.minute_display().ends_with("45'") or s.minute_display().ends_with("46'"), "minute display includes first half (%s)" % s.minute_display())
	s.register_goal(0, 9)
	check(s.score[0] == 1 and s.phase == MatchState.Phase.GOAL_SCORED, "goal registered")
	check(s.ball_out(Vector3(0, 0, Pitch.HALF_WIDTH + 1), 0) == MatchState.Phase.THROW_IN, "side line out = throw-in")
	check(s.ball_out(Vector3(Pitch.HALF_LENGTH + 1, 0, 0), 0) == MatchState.Phase.GOAL_KICK, "goal line out by defender = goal kick")
	check(s.ball_out(Vector3(Pitch.HALF_LENGTH + 1, 0, 0), 1) == MatchState.Phase.CORNER, "goal line out by attacker = corner")


# -------------------------------------------------------------- formations

func test_formations() -> void:
	print("formations")
	for fname in ["4-4-2", "4-3-3", "3-5-2"]:
		var slots := Formation.get_positions(fname)
		check(slots.size() == 10, "%s has 10 outfield slots" % fname)
		var valid := true
		for slot in slots:
			var a0 := Formation.anchor_for(0, 1, slot)
			var a1 := Formation.anchor_for(1, -1, slot)
			if a0.x < -Pitch.HALF_LENGTH or a0.x > 0.0 or absf(a0.z) > Pitch.HALF_WIDTH:
				valid = false
			if not a1.is_equal_approx(Vector3(-a0.x, 0, a0.z)):
				valid = false
		check(valid, "%s anchors inside own half and mirror for team 1" % fname)
	var shifted := Formation.shifted_anchor(Vector3(-40, 0, 0), 1, Vector3(30, 0, 10), 0.4)
	check(shifted.x > -40.0, "formation shifts with the ball")


# ----------------------------------------------------------------- referee

func test_referee() -> void:
	print("referee")
	var clean := Referee.decide_tackle(6.0, 0.2, true)
	check(not clean.foul, "clean front tackle is not a foul")
	var reckless := Referee.decide_tackle(13.0, 0.95, false)
	check(reckless.foul and reckless.card == "red", "reckless from-behind lunge is a red card")
	var ordinary := Referee.decide_tackle(5.0, 0.4, false)
	check(ordinary.foul and ordinary.card == "", "ordinary bad tackle is a foul without card")
	test_offside()


func test_offside() -> void:
	print("offside")
	# Team attacks +x. Defenders: GK at 50, second-last at 40.
	var defenders := []
	var gk := Node3D.new()
	gk.position = Vector3(50, 0, 0)
	defenders.append(gk)
	var def2 := Node3D.new()
	def2.position = Vector3(40, 0, 0)
	defenders.append(def2)
	var receiver := Node3D.new()
	# Onside: receiver level with second-last defender.
	receiver.position = Vector3(40, 0, 0)
	var r := Referee.is_offside(Vector3(10, 0, 0), 1, [receiver], defenders, Vector3(10, 0, 0))
	check(not r.offside, "receiver level with second-last defender is onside")
	receiver.position = Vector3(45, 0, 0)
	r = Referee.is_offside(Vector3(10, 0, 0), 1, [receiver], defenders, Vector3(10, 0, 0))
	check(r.offside, "receiver beyond second-last defender is offside")
	receiver.position = Vector3(30, 0, 0)
	r = Referee.is_offside(Vector3(10, 0, 0), 1, [receiver], defenders, Vector3(10, 0, 0))
	check(not r.offside, "receiver behind the ball line is onside")


# ------------------------------------------------------------ match smoke

func test_match_smoke() -> void:
	print("match smoke test")
	var m := Match.new()
	m.name = "SmokeMatch"
	m.configure({"half_length_seconds": 360.0, "seed": 12345})
	root.add_child(m)
	# Views are built by main normally; headless smoke skips them.
	m.state.start_match()
	check(m.state.phase == MatchState.Phase.KICKOFF, "smoke: starts at kick-off")
	check(m.teams[0].players.size() == 11 and m.teams[1].players.size() == 11, "smoke: 11 v 11")
	# Drive the match for 12 simulated seconds.
	for i in 60 * 12:
		m._physics_process(1.0 / 60.0)
	check(m.state.phase == MatchState.Phase.PLAYING, "smoke: reaches PLAYING after kick-off (phase=%d)" % m.state.phase)
	check(m.ball.global_position.distance_to(Vector3.ZERO) < 60.0, "smoke: ball in play")
	# All players remain inside a sane area around the pitch.
	var inside := true
	for t in m.teams:
		for p in t.players:
			var pp: Vector3 = (p as Node3D).position
			if absf(pp.x) > Pitch.HALF_LENGTH + 3.0 or absf(pp.z) > Pitch.HALF_WIDTH + 3.0:
				inside = false
	check(inside, "smoke: players stay near the pitch")
	# Force the ball out on the side line -> throw-in for the other team.
	var last_touch := m.last_touch_team if m.last_touch_team >= 0 else 0
	m.ball.global_position = Vector3(10, Pitch.BALL_RADIUS, Pitch.HALF_WIDTH + 1.0)
	m.ball.velocity = Vector3.ZERO
	for i in 10:
		m._physics_process(1.0 / 60.0)
	check(m.state.phase == MatchState.Phase.THROW_IN, "smoke: side-line out becomes throw-in (phase=%d)" % m.state.phase)
	# Let the throw-in execute (user takers auto-take after ~6 s).
	for i in 60 * 8:
		m._physics_process(1.0 / 60.0)
	check(m.state.phase == MatchState.Phase.PLAYING, "smoke: restart returns to play (phase=%d)" % m.state.phase)
	# Force a goal: put the ball just inside the goal of the +x side.
	var dir0 := m.current_attack_dir(0)
	var goal_x := dir0 * (Pitch.HALF_LENGTH + 0.6)
	m.ball.global_position = Vector3(goal_x, 1.0, 0.0)
	m.ball.velocity = Vector3(dir0 * 8.0, 0, 0)
	m.ball.release_from_carrier()
	m.last_touch_team = 0
	for i in 30:
		m._physics_process(1.0 / 60.0)
	check(m.state.score[0] + m.state.score[1] >= 1 or m.state.phase == MatchState.Phase.GOAL_SCORED, "smoke: goal registers (score=%s phase=%d)" % [str(m.state.score), m.state.phase])
	# User actions do not crash.
	m.action_pass()
	m.action_through()
	m.action_lob()
	m.action_shoot_start()
	m.action_shoot_cancel()
	m.action_tackle()
	m.action_sprint(true)
	m.action_sprint(false)
	check(true, "smoke: all action entry points executed")
	# Drive through the goal celebration and the resulting kick-off.
	for i in 60 * 10:
		m._physics_process(1.0 / 60.0)
	# Drive to full time quickly.
	m.state.clock_seconds = m.state.half_length_seconds + 1.0
	for i in 5:
		m._physics_process(1.0 / 60.0)
	check(m.state.phase == MatchState.Phase.HALF_TIME, "smoke: reaches half time (phase=%d)" % m.state.phase)
	m.start_second_half()
	m.state.clock_seconds = m.state.half_length_seconds + 1.0
	for i in 5:
		m._physics_process(1.0 / 60.0)
	check(m.state.phase == MatchState.Phase.FULL_TIME, "smoke: reaches full time (phase=%d)" % m.state.phase)
	m.queue_free()


# --------------------------------------------------------- input mapping

func test_input_mapping() -> void:
	print("input mapping")
	var c := TouchControls.new()
	c.name = "TestControls"
	root.add_child(c)
	# Button hit test: every button center maps back to its own id.
	var all_hit := true
	for id in c._btn_positions:
		if c._button_at(c._btn_positions[id]) != id:
			all_hit = false
	check(all_hit, "input: every button hit-tests to itself")
	check(c._button_at(Vector2(10, 10)) == "", "input: empty corner does not hit a button")
	# Joystick: touch down creates a floating stick, drag produces a vector.
	c._handle_touch(0, Vector2(300, 800), true)
	check(c.joy_active and c.joy_index == 0, "input: left-zone touch creates the joystick")
	c._handle_drag(0, Vector2(300, 800) + Vector2(60, 0))
	check(c.joy_vector.x > 0.5 and absf(c.joy_vector.y) < 0.2, "input: right drag gives rightward vector (%s)" % str(c.joy_vector))
	c._handle_touch(0, Vector2(300, 800), false)
	check(not c.joy_active and c.joy_vector == Vector2.ZERO, "input: release clears the joystick")
	# Multi-touch: one finger on a button while another holds the stick.
	c._handle_touch(1, Vector2(300, 800), true)
	c._handle_touch(2, c._btn_positions["pass"], true)
	check(c.joy_active and c.pressed_buttons.has(2), "input: joystick + button simultaneously (multi-touch)")
	c._handle_touch(1, Vector2(300, 800), false)
	check(c.joy_active == false and c.pressed_buttons.has(2), "input: button survives joystick release")
	c._handle_touch(2, c._btn_positions["pass"], false)
	# Settings round-trip.
	var old_scale := c.button_scale
	c.set_settings(1.3, 0.4, true, false)
	var c2 := TouchControls.new()
	root.add_child(c2)
	check(absf(c2.button_scale - 1.3) < 0.01 and c2.left_handed, "input: settings persist (scale=%.2f, left=%s)" % [c2.button_scale, str(c2.left_handed)])
	# Left-handed layout mirrors positions.
	var mirrored := true
	for id in c2._btn_positions:
		if c2._btn_positions[id].x >= 1920.0 * 0.5:
			mirrored = false
	check(mirrored, "input: left-handed buttons sit on the left half")
	c2.set_settings(old_scale, 0.55, false, true)
	c.queue_free()
	c2.queue_free()


func _unused_input_test() -> void:
	pass

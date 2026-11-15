class_name MatchState
extends RefCounted
## Pure match logic: clock, halves, score, restart states and match events.
## No scene-tree dependencies, so it is fully unit-testable headlessly.

enum Phase { PRE_MATCH, KICKOFF, PLAYING, THROW_IN, CORNER, GOAL_KICK, FREE_KICK, PENALTY, GOAL_SCORED, HALF_TIME, FULL_TIME }

signal phase_changed(phase: int)
signal goal_scored(team_idx: int, scorer_number: int)
signal card_shown(team_idx: int, player_number: int, card: String)
signal foul_committed(team_idx: int, player_number: int, is_penalty: bool)
signal substitution_made(team_idx: int, out_number: int, in_number: int)

var half := 0                    # 0 = none yet, 1, 2
var half_length_seconds := 270.0 # in-game seconds per half (45' x scale); configurable
var clock_seconds := 0.0         # in-game seconds elapsed in the current half
var score := [0, 0]
var phase: int = Phase.PRE_MATCH
var restart_team := -1           # which team takes the current restart
var restart_position := Vector3.ZERO
var stoppage_seconds := 0.0
var scorer_number := 0
var last_goal_team := -1
var possession_team := 0         # 0 or 1
var added_time_first_half := 0.0
var added_time_second_half := 0.0


func configure(half_length_seconds_: float) -> void:
	half_length_seconds = maxf(60.0, half_length_seconds_)


func minute_display() -> String:
	var total := clock_seconds / half_length_seconds * 45.0
	if half == 2:
		total += 45.0
	return "%d'" % int(total + 1.0)


func clock_display() -> String:
	var shown := int(clock_seconds / half_length_seconds * 45.0) + 1
	if half == 2:
		shown += 45
	return "%02d:%02d" % [shown / 60, shown % 60]


func set_phase(p: int) -> void:
	if phase == p:
		return
	phase = p
	phase_changed.emit(p)


func start_match() -> void:
	half = 1
	clock_seconds = 0.0
	possession_team = 0
	restart_team = 0
	set_phase(Phase.KICKOFF)
	_position_restart(Vector3(0, 0, 0))


func _position_restart(p: Vector3) -> void:
	restart_position = p


func tick_gameplay(dt: float) -> void:
	# The clock runs in every live phase (football: time runs during restarts);
	# it stops for goals, breaks and before kick-off.
	if phase in [Phase.PRE_MATCH, Phase.GOAL_SCORED, Phase.HALF_TIME, Phase.FULL_TIME]:
		return
	clock_seconds += dt
	if clock_seconds >= half_length_seconds + stoppage_seconds:
		_end_half()


func _end_half() -> void:
	if half == 1:
		set_phase(Phase.HALF_TIME)
	else:
		set_phase(Phase.FULL_TIME)


func start_second_half() -> void:
	half = 2
	clock_seconds = 0.0
	stoppage_seconds = 0.0
	# Team B kicks off the second half.
	possession_team = 1
	restart_team = 1
	set_phase(Phase.KICKOFF)
	restart_position = Vector3(0, 0, 0)


func resume_from_halftime_kickoff() -> void:
	set_phase(Phase.PLAYING)


func register_goal(team_idx: int, scorer: int) -> void:
	score[team_idx] += 1
	scorer_number = scorer
	last_goal_team = team_idx
	set_phase(Phase.GOAL_SCORED)
	goal_scored.emit(team_idx, scorer)


func goals(team_idx: int) -> int:
	return score[team_idx]


func is_over() -> bool:
	return phase == Phase.FULL_TIME


## Out-of-play determination. Returns the restart phase and side.
func ball_out(p: Vector3, last_touch_team: int) -> int:
	# Returns -1 if not out, else the resulting restart phase.
	if absf(p.z) > Pitch.HALF_WIDTH:
		return Phase.THROW_IN
	if absf(p.x) > Pitch.HALF_LENGTH:
		# Behind a goal line: the team defending that goal line is the team
		# attacking the OPPOSITE side.
		var goal_line_team := 1 if p.x > 0.0 else 0
		if last_touch_team == goal_line_team:
			return Phase.CORNER
		return Phase.GOAL_KICK
	return -1

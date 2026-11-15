class_name Pitch
## Static pitch dimensions and shared helpers. Coordinates:
## X = length of the pitch (team A attacks +X in the first half),
## Z = width, Y = up. Units are metres.

const LENGTH := 105.0
const WIDTH := 68.0
const HALF_LENGTH := LENGTH * 0.5
const HALF_WIDTH := WIDTH * 0.5
const GOAL_WIDTH := 7.32
const GOAL_HEIGHT := 2.44
const GOAL_DEPTH := 2.0
const PENALTY_AREA_DEPTH := 16.5
const PENALTY_AREA_WIDTH := 40.32
const GOAL_AREA_DEPTH := 5.5
const GOAL_AREA_WIDTH := 18.32
const CENTER_CIRCLE_RADIUS := 9.15
const PENALTY_SPOT_FROM_GOAL := 11.0
const CORNER_ARC_RADIUS := 1.0
const BALL_RADIUS := 0.11


static func inside_pitch(p: Vector3, margin := 0.0) -> bool:
	return absf(p.x) <= HALF_LENGTH + margin and absf(p.z) <= HALF_WIDTH + margin


static func goal_center_x(team_attacks_plus_x: bool) -> float:
	return HALF_LENGTH if team_attacks_plus_x else -HALF_LENGTH


static func in_penalty_area(p: Vector3, attacking_plus_x_goal: bool) -> bool:
	var gx := goal_center_x(attacking_plus_x_goal)
	return (absf(p.x - gx) <= PENALTY_AREA_DEPTH and absf(p.z) <= PENALTY_AREA_WIDTH * 0.5)


static func clamp_to_pitch(p: Vector3, margin := 0.5) -> Vector3:
	p.x = clampf(p.x, -HALF_LENGTH - margin, HALF_LENGTH + margin)
	p.z = clampf(p.z, -HALF_WIDTH - margin, HALF_WIDTH + margin)
	return p

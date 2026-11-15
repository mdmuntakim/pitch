class_name Formation
extends RefCounted
## Formation definitions: normalized positions for the 10 outfield players.
## x in [0, 1] = fraction of own half from own goal (0 = own goal line, 1 = halfway),
## z in [-1, 1] across the pitch width.

const FORMATIONS := {
	"4-4-2": [
		{"role": "RB", "x": 0.16, "z": -0.72},
		{"role": "CB1", "x": 0.12, "z": -0.26},
		{"role": "CB2", "x": 0.12, "z": 0.26},
		{"role": "LB", "x": 0.16, "z": 0.72},
		{"role": "RM", "x": 0.42, "z": -0.68},
		{"role": "CM1", "x": 0.38, "z": -0.2},
		{"role": "CM2", "x": 0.42, "z": 0.22},
		{"role": "LM", "x": 0.42, "z": 0.68},
		{"role": "ST1", "x": 0.72, "z": -0.22},
		{"role": "ST2", "x": 0.72, "z": 0.22},
	],
	"4-3-3": [
		{"role": "RB", "x": 0.18, "z": -0.74},
		{"role": "CB1", "x": 0.12, "z": -0.26},
		{"role": "CB2", "x": 0.12, "z": 0.26},
		{"role": "LB", "x": 0.18, "z": 0.74},
		{"role": "CM1", "x": 0.34, "z": -0.36},
		{"role": "CDM", "x": 0.26, "z": 0.0},
		{"role": "CM2", "x": 0.36, "z": 0.38},
		{"role": "RW", "x": 0.68, "z": -0.74},
		{"role": "ST", "x": 0.76, "z": 0.0},
		{"role": "LW", "x": 0.68, "z": 0.74},
	],
	"3-5-2": [
		{"role": "CB1", "x": 0.12, "z": -0.4},
		{"role": "CB2", "x": 0.10, "z": 0.0},
		{"role": "CB3", "x": 0.12, "z": 0.4},
		{"role": "RWB", "x": 0.44, "z": -0.82},
		{"role": "CM1", "x": 0.34, "z": -0.3},
		{"role": "CDM", "x": 0.26, "z": 0.04},
		{"role": "CM2", "x": 0.36, "z": 0.34},
		{"role": "LWB", "x": 0.44, "z": 0.82},
		{"role": "ST1", "x": 0.72, "z": -0.2},
		{"role": "ST2", "x": 0.72, "z": 0.2},
	],
}

const ROLE_GROUPS := {
	"RB": "defender", "CB1": "defender", "CB2": "defender", "CB3": "defender", "LB": "defender",
	"RWB": "midfielder", "LWB": "midfielder", "RM": "midfielder", "LM": "midfielder",
	"CM1": "midfielder", "CM2": "midfielder", "CDM": "midfielder",
	"RW": "attacker", "LW": "attacker", "ST": "attacker", "ST1": "attacker", "ST2": "attacker",
}


static func get_positions(formation_name: String) -> Array:
	if FORMATIONS.has(formation_name):
		return FORMATIONS[formation_name]
	return FORMATIONS["4-4-2"]


## World-space anchor for a player of the given team, mirroring for team 1.
## attack_dir = +1 when the team attacks +X. slot.x is measured from the own
## goal line (0) to the halfway line (1); own goal sits at -attack_dir * half length.
static func anchor_for(team_idx: int, attack_dir: int, slot: Dictionary) -> Vector3:
	var half_span := Pitch.HALF_LENGTH
	var from_own_goal: float = float(slot.x) * half_span * 0.92
	var x := attack_dir * (-half_span + from_own_goal)
	var z: float = float(slot.z) * Pitch.HALF_WIDTH * 0.86
	return Vector3(x, 0.0, z)


## Shift formation anchors with the ball (team compactness/press behavior).
static func shifted_anchor(base: Vector3, attack_dir: int, ball: Vector3, push: float) -> Vector3:
	# Slide the block along X with ball position, compressed by `push`.
	var along := base.x + (ball.x - base.x) * push
	along = clampf(along, -Pitch.HALF_LENGTH + 2.0, Pitch.HALF_LENGTH - 2.0)
	var z := base.z + ball.z * 0.18
	return Vector3(along, 0.0, clampf(z, -Pitch.HALF_WIDTH + 1.5, Pitch.HALF_WIDTH - 1.5))

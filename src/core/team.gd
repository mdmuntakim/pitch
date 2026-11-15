class_name Team
extends RefCounted
## Team definition: identity (original names, kits), formation, players,
## bench for substitutions, and in-match aggregates.

var name := ""
var short_name := ""
var kit_primary := Color()
var kit_secondary := Color()
var kit_trim := Color()
var formation_name := "4-4-2"
var formation_slots: Array = []
var kit_fabric: Texture2D = null
var players: Array = []   # PlayerAgent list (11)
var bench: Array = []     # numbers available for substitution
var used_subs := 0
var max_subs := 5
var attack_dir := 1
var secondary_press := true


static func make(team_idx: int, attack_dir_: int) -> Team:
	var t := Team.new()
	t.attack_dir = attack_dir_
	if team_idx == 0:
		t.name = "Vale Rovers"
		t.short_name = "VAL"
		t.kit_primary = Color(0.72, 0.09, 0.11)   # claret
		t.kit_secondary = Color(0.92, 0.88, 0.82) # off-white
		t.kit_trim = Color(0.10, 0.08, 0.09)
		t.formation_name = "4-3-3"
	else:
		t.name = "Harbour Athletic"
		t.short_name = "HAR"
		t.kit_primary = Color(0.10, 0.24, 0.55)   # deep blue
		t.kit_secondary = Color(0.90, 0.92, 0.96)
		t.kit_trim = Color(0.85, 0.72, 0.20)
		t.formation_name = "4-4-2"
	t.formation_slots = Formation.get_positions(t.formation_name)
	var fabric := load("res://assets/textures/kit_fabric.png")
	if fabric != null:
		t.kit_fabric = fabric
	return t


## Build the 11 players (GK + formation) for this team.
func build_players(parent: Node, ball_view_layer: int) -> void:
	for p in players:
		p.queue_free()
	players.clear()
	var gk := Goalkeeper.new()
	gk.name = "P%d_T%d" % [1, attack_dir]
	parent.add_child(gk)
	gk.setup_gk(0 if attack_dir == 1 else 1, attack_dir, Vector3(-attack_dir * (Pitch.HALF_LENGTH - 1.6), 0.0, 0.0))
	players.append(gk)
	var numbers := [1, 2, 4, 5, 3, 7, 6, 8, 11, 9, 10]
	for i in formation_slots.size():
		var slot: Dictionary = formation_slots[i]
		var a := PlayerAgent.new()
		a.name = "P%d_T%d" % [numbers[i + 1], attack_dir]
		parent.add_child(a)
		a.setup(0 if attack_dir == 1 else 1, numbers[i + 1], slot.role, Formation.ROLE_GROUPS.get(slot.role, "midfielder"), attack_dir, Formation.anchor_for(i, attack_dir, slot))
		players.append(a)
	bench = [12, 14, 16, 18, 20]


func field_players() -> Array:
	return players


func outfield_players() -> Array:
	return players.slice(1)


func goalkeeper() -> Goalkeeper:
	return players[0]


func defenders_sorted_by_goal(attack_dir_of_team: int) -> Array:
	# Players sorted deepest (closest to own goal) first.
	var arr := players.duplicate()
	arr.sort_custom(func(a: Node3D, b: Node3D):
		return a.position.x * attack_dir_of_team < b.position.x * attack_dir_of_team)
	return arr


func can_substitute() -> bool:
	return used_subs < max_subs and bench.size() > 0


## Replace the most tired outfield player with a fresh bench player.
func substitute() -> Dictionary:
	if not can_substitute():
		return {}
	var most_tired: PlayerAgent = null
	var worst := 2.0
	for p in outfield_players():
		if p.stamina < worst:
			worst = p.stamina
			most_tired = p
	if most_tired == null:
		return {}
	var in_number: int = bench.pop_front()
	used_subs += 1
	var out_number := most_tired.number
	most_tired.stamina = 1.0
	most_tired.number = in_number
	most_tired.name = "P%d_T%d" % [in_number, attack_dir]
	return {"team": 0 if attack_dir == 1 else 1, "out": out_number, "in": in_number}

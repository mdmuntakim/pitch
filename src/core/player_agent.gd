class_name PlayerAgent
extends Node3D
## A single on-pitch player: agent state (role, stamina, discipline) plus
## movement. Visual body is attached by PlayerView; this node owns position,
## facing and locomotion.

signal stamina_changed(value: float)

var team_idx := 0
var number := 7
var role := "CM1"
var role_group := "midfielder"
var attack_dir := 1
var base_anchor := Vector3.ZERO
var stamina := 1.0
var max_speed := 6.6          # m/s jogging; sprint multiplies
var sprint_speed := 8.6
var card := ""                # "", "yellow", "red"
var sent_off := false
var is_goalkeeper := false
var move_target := Vector3.ZERO
var move_speed_factor := 1.0
var current_speed := 0.0
var sprinting := false
var tackle_cooldown := 0.0
var celebrate_timer := 0.0
var view: Node3D = null       # PlayerView instance
var run_phase := 0.0

const STAMINA_DRAIN := 0.030  # per second at full sprint
const STAMINA_REGEN := 0.012


func setup(team_idx_: int, number_: int, role_: String, role_group_: String, attack_dir_: int, anchor: Vector3) -> void:
	team_idx = team_idx_
	number = number_
	role = role_
	role_group = role_group_
	attack_dir = attack_dir_
	base_anchor = anchor
	position = anchor
	max_speed = 6.2 + randf() * 0.5
	if role_group == "attacker":
		max_speed += 0.5
	elif role_group == "defender":
		max_speed -= 0.1


func _physics_process(dt: float) -> void:
	tackle_cooldown = maxf(0.0, tackle_cooldown - dt)
	if celebrate_timer > 0.0:
		celebrate_timer -= dt
	if sent_off:
		return
	if current_speed > 0.05:
		var dir := move_target - position
		dir.y = 0.0
		if dir.length() > 0.01:
			dir = dir.normalized()
			var eff := _effective_speed() * move_speed_factor
			var step := dir * eff * dt
			# Simple inter-player separation.
			position += step + _separation() * dt
			_face(dir, dt, eff)
			run_phase += dt * eff * 1.25
		else:
			current_speed = 0.0
	# Stamina model.
	if sprinting and current_speed > 4.0:
		stamina = maxf(0.0, stamina - STAMINA_DRAIN * dt)
	else:
		stamina = minf(1.0, stamina + STAMINA_REGEN * dt)
	# Stay on the pitch (with a small sideline allowance for throw-ins).
	position.x = clampf(position.x, -Pitch.HALF_LENGTH - 1.5, Pitch.HALF_LENGTH + 1.5)
	position.z = clampf(position.z, -Pitch.HALF_WIDTH - 1.5, Pitch.HALF_WIDTH + 1.5)
	position.y = 0.0


func _effective_speed() -> float:
	var s := sprint_speed if sprinting else max_speed
	return s * (0.55 + 0.45 * stamina) if stamina < 0.35 else s


func move_towards(target: Vector3, dt: float, sprint := false) -> void:
	move_target = target
	sprinting = sprint
	var d := (target - position)
	d.y = 0.0
	current_speed = clampf(d.length() * 2.0, 0.0, _effective_speed()) if d.length() > 0.15 else 0.0


func halt() -> void:
	move_target = position
	current_speed = 0.0
	sprinting = false


func _separation() -> Vector3:
	var push := Vector3.ZERO
	var parent := get_parent()
	if parent == null:
		return push
	for other in parent.get_children():
		if other == self or not (other is PlayerAgent) or (other as PlayerAgent).sent_off:
			continue
		var delta: Vector3 = position - (other as Node3D).position
		delta.y = 0.0
		var d := delta.length()
		if d > 0.001 and d < 1.4:
			push += delta / d * (1.4 - d) * 2.2
	return push


func _face(dir: Vector3, dt: float, eff: float) -> void:
	var target_angle := atan2(dir.x, dir.z)
	var cur := rotation.y
	var diff := wrapf(target_angle - cur, -PI, PI)
	var rate := clampf(9.0 * dt, 0.0, absf(diff))
	rotation.y = cur + signf(diff) * minf(rate, absf(diff))


func distance_to(p: Vector3) -> float:
	var d := position - p
	d.y = 0.0
	return d.length()


func show_card(card_type: String) -> void:
	if card_type == "yellow":
		if card == "yellow":
			_send_off()
		else:
			card = "yellow"
	elif card_type == "red":
		_send_off()


func _send_off() -> void:
	card = "red"
	sent_off = true
	halt()


func celebrate(duration := 4.0) -> void:
	celebrate_timer = duration

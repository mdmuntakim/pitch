class_name Ball
extends Node3D
## Custom, deterministic ball physics: gravity, air drag, Magnus (spin) force,
## ground bounce and rolling friction, post/crossbar collision and net catch.
## Deliberately not using the physics engine: identical results on every device
## and unit-testable headlessly.

var velocity := Vector3.ZERO
var spin := Vector3.ZERO                  # angular velocity rad/s (axis = spin direction)
var last_touch_team := -1
var last_touch_number := 0
var is_dribbled := false
var carrier: Node3D = null                # player agent currently dribbling
var alive := true

const AIR_DRAG := 0.14                    # per-second proportional drag
const MAGNUS_COEFF := 0.055
const RESTITUTION := 0.62
const ROLL_FRICTION := 0.55               # m/s^2 while rolling on grass
const GROUND_SPIN_DECAY := 2.4            # spin decay per second on ground
const MAX_SPEED := 38.0


func _ready() -> void:
	set_as_top_level(true)


func _physics_process(dt: float) -> void:
	step(dt)


func step(dt: float) -> void:
	if carrier != null and is_dribbled:
		stick_to_carrier()
		return
	# Gravity
	velocity.y -= 9.81 * dt
	# Air drag
	velocity -= velocity * AIR_DRAG * dt
	# Magnus force: F = k * (spin x velocity)
	if spin.length() > 0.05:
		var magnus := MAGNUS_COEFF * spin.cross(velocity)
		velocity += magnus * dt * 60.0 * 0.016  # frame-rate stable-ish scaling
		spin = spin.move_toward(Vector3.ZERO, 0.25 * dt * 60.0 * 0.016)
	if velocity.length() > MAX_SPEED:
		velocity = velocity.normalized() * MAX_SPEED
	translate(velocity * dt)
	_ground_and_bounce(dt)
	_collide_goals()


func stick_to_carrier() -> void:
	if carrier == null:
		is_dribbled = false
		return
	var fwd := -carrier.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var target := carrier.global_position + fwd * 0.55
	target.y = Pitch.BALL_RADIUS
	var old := global_position
	global_position = global_position.lerp(target, 0.35)
	velocity = (global_position - old) / get_physics_process_delta_time() if get_physics_process_delta_time() > 0.0 else Vector3.ZERO
	velocity.y = 0.0
	spin = Vector3.ZERO


func _ground_and_bounce(dt: float) -> void:
	if global_position.y < Pitch.BALL_RADIUS:
		global_position.y = Pitch.BALL_RADIUS
		if velocity.y < -0.6:
			velocity.y = -velocity.y * RESTITUTION
			# Bounce eats some horizontal speed and spin.
			velocity.x *= 0.86
			velocity.z *= 0.86
			spin *= 0.7
		else:
			velocity.y = 0.0
			# Rolling friction decelerates the horizontal motion.
			var horiz := Vector2(velocity.x, velocity.z)
			var speed := horiz.length()
			if speed > 0.0:
				var new_speed := maxf(0.0, speed - ROLL_FRICTION * dt * (1.0 + speed * 0.08))
				horiz = horiz / speed * new_speed
				velocity.x = horiz.x
				velocity.z = horiz.y
			spin = spin.move_toward(Vector3.ZERO, GROUND_SPIN_DECAY * dt * 10.0)


func _collide_goals() -> void:
	for sx in [-1.0, 1.0]:
		var gx: float = sx * Pitch.HALF_LENGTH
		if absf(global_position.x - gx) < Pitch.BALL_RADIUS + 0.08 and absf(global_position.z) < Pitch.GOAL_WIDTH * 0.5 and global_position.y < Pitch.GOAL_HEIGHT:
			# Ball is inside the goal mouth: it has crossed the line (goal).
			continue
		# Posts: two vertical cylinders at z = +/- GOAL_WIDTH/2 on each goal line.
		for sz in [-1.0, 1.0]:
			var post := Vector3(gx, global_position.y, sz * Pitch.GOAL_WIDTH * 0.5)
			if global_position.distance_to(post) < Pitch.BALL_RADIUS + 0.06 and global_position.y < Pitch.GOAL_HEIGHT + 0.1:
				_deflect(post)
				return
		# Crossbar.
		var bar := Vector3(gx, Pitch.GOAL_HEIGHT, global_position.z)
		if absf(global_position.z) < Pitch.GOAL_WIDTH * 0.5 and global_position.distance_to(bar) < Pitch.BALL_RADIUS + 0.06 and velocity.y > -8.0 and velocity.x * sx < 2.0:
			if absf(global_position.y - Pitch.GOAL_HEIGHT) < Pitch.BALL_RADIUS + 0.08:
				_deflect(bar)
				return


func _deflect(surface_point: Vector3) -> void:
	var normal := (global_position - surface_point).normalized()
	velocity = velocity.bounce(normal) * 0.55
	spin *= 0.5
	translate(normal * 0.05)


func kick(direction: Vector3, power: float, spin_vector := Vector3.ZERO, loft := 0.0) -> void:
	is_dribbled = false
	carrier = null
	var dir := direction
	dir.y = 0.0
	if dir.length() < 0.001:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	dir.y = clampf(loft, 0.0, 0.9)
	velocity = dir.normalized() * clampf(power, 1.0, MAX_SPEED)
	spin = spin_vector


func release_from_carrier() -> void:
	is_dribbled = false
	carrier = null


func speed() -> float:
	return velocity.length()


func grounded() -> bool:
	return global_position.y <= Pitch.BALL_RADIUS + 0.02

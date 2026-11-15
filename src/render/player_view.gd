class_name PlayerView
extends Node3D
## Articulated humanoid body built from primitives, with script-driven pose
## animation (idle sway, jog/sprint cycle, kick swing, tackle slide, celebrate,
## goalkeeper dive). Kit materials come from the team identity.

var team: Team
var agent: PlayerAgent
var kick_timer := 0.0

var torso: MeshInstance3D
var head: MeshInstance3D
var pelvis: MeshInstance3D
var arm_l: MeshInstance3D
var arm_r: MeshInstance3D
var thigh_l: MeshInstance3D
var thigh_r: MeshInstance3D
var shin_l: MeshInstance3D
var shin_r: MeshInstance3D

const SHOULDER_Y := 1.32
const HIP_Y := 0.92


static func build(agent_: PlayerAgent, team_: Team) -> PlayerView:
	var v := PlayerView.new()
	v.agent = agent_
	v.team = team_
	agent_.add_child(v)
	v.name = "View"
	v._build_body()
	return v


func _build_body() -> void:
	var shirt := StandardMaterial3D.new()
	shirt.albedo_color = team.kit_primary
	shirt.roughness = 0.85
	if team.kit_fabric != null:
		shirt.albedo_texture = team.kit_fabric
		shirt.uv1_scale = Vector3(2, 2, 1)
	var shorts := StandardMaterial3D.new()
	shorts.albedo_color = team.kit_secondary
	shorts.roughness = 0.9
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.78, 0.58, 0.46).lerp(Color(0.35, 0.24, 0.18), agent.number % 4 as float / 4.0)
	skin.roughness = 0.7
	var socks := StandardMaterial3D.new()
	socks.albedo_color = team.kit_trim
	var boots := StandardMaterial3D.new()
	boots.albedo_color = Color(0.05, 0.05, 0.06)
	boots.metallic = 0.2
	boots.roughness = 0.4

	pelvis = _part(0.0, HIP_Y - 0.06, 0.0, Vector3(0.30, 0.20, 0.20), shorts, CapsuleMesh.new())
	torso = _part(0.0, HIP_Y + 0.28, 0.0, Vector3(0.34, 0.52, 0.22), shirt, CapsuleMesh.new())
	head = _part(0.0, SHOULDER_Y + 0.20, 0.0, Vector3(0.22, 0.24, 0.22), skin, SphereMesh.new())
	arm_l = _part(-0.26, SHOULDER_Y - 0.04, 0.0, Vector3(0.10, 0.50, 0.10), skin, CapsuleMesh.new())
	arm_r = _part(0.26, SHOULDER_Y - 0.04, 0.0, Vector3(0.10, 0.50, 0.10), skin, CapsuleMesh.new())
	thigh_l = _part(-0.10, HIP_Y - 0.22, 0.0, Vector3(0.14, 0.44, 0.14), shorts, CapsuleMesh.new())
	thigh_r = _part(0.10, HIP_Y - 0.22, 0.0, Vector3(0.14, 0.44, 0.14), shorts, CapsuleMesh.new())
	shin_l = _part(-0.10, HIP_Y - 0.58, 0.0, Vector3(0.11, 0.40, 0.11), socks, CapsuleMesh.new())
	shin_r = _part(0.10, HIP_Y - 0.58, 0.0, Vector3(0.11, 0.40, 0.11), socks, CapsuleMesh.new())
	# Sock/leg split: upper shin skin, lower sock is approximated with socks material.
	# Boots: small boxes at the feet.
	var foot_l := _part(-0.10, 0.05, 0.06, Vector3(0.10, 0.08, 0.26), boots, BoxMesh.new())
	foot_l.name = "FootL"
	var foot_r := _part(0.10, 0.05, 0.06, Vector3(0.10, 0.08, 0.26), boots, BoxMesh.new())
	foot_r.name = "FootR"
	# Shirt number on the back: small quad with a generated number texture.
	var num := StandardMaterial3D.new()
	num.albedo_color = team.kit_secondary
	num.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	num.albedo_texture = _number_texture(agent.number)
	var back := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.24, 0.28)
	back.mesh = quad
	back.material_override = num
	back.position = Vector3(0, HIP_Y + 0.30, -0.115)
	back.rotation_degrees = Vector3(0, 180, 0)
	add_child(back)


func _part(px: float, py: float, pz: float, size: Vector3, mat: Material, mesh_mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if mesh_mesh is CapsuleMesh:
		var c := mesh_mesh as CapsuleMesh
		c.radius = minf(size.x, size.z) * 0.5
		c.height = size.y
	elif mesh_mesh is SphereMesh:
		var s := mesh_mesh as SphereMesh
		s.radius = size.x * 0.5
		s.height = size.y
	elif mesh_mesh is BoxMesh:
		(mesh_mesh as BoxMesh).size = size
	mi.mesh = mesh_mesh
	mi.material_override = mat
	mi.position = Vector3(px, py, pz)
	add_child(mi)
	return mi


func _number_texture(n: int) -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Crude bitmap digits drawn as bar segments (seven-segment style).
	var seg := [[0, 0, 1, 0], [1, 1, 0, 0], [0, 1, 0, 1], [1, 0, 0, 1], [1, 0, 0, 1], [0, 0, 0, 0]]
	# Draw the number as horizontal bars count = digits.
	var bars := n % 8
	for b in bars:
		var y := 6 + b * 7
		img.fill_rect(Rect2i(14, y, 36, 4), Color(1, 1, 1, 1))
	if n % 8 == 0:
		img.fill_rect(Rect2i(14, 6, 4, 46), Color(1, 1, 1, 1))
		img.fill_rect(Rect2i(46, 6, 4, 46), Color(1, 1, 1, 1))
		img.fill_rect(Rect2i(14, 6, 36, 4), Color(1, 1, 1, 1))
		img.fill_rect(Rect2i(14, 48, 36, 4), Color(1, 1, 1, 1))
	var tex := ImageTexture.create_from_image(img)
	return tex


func _process(dt: float) -> void:
	if agent == null:
		return
	kick_timer = maxf(0.0, kick_timer - dt)
	var speed := agent.current_speed
	var phase := agent.run_phase
	var celebrating := agent.celebrate_timer > 0.0
	var tackling := agent.tackle_cooldown > 1.05
	var kicking := kick_timer > 0.0

	# Reset rotations to rest, then apply pose deltas each frame.
	var rest_pelvis := 0.0
	var rest_thigh_l := 0.0
	var rest_thigh_r := 0.0
	var rest_shin_l := 0.0
	var rest_shin_r := 0.0
	var rest_arm_l := 0.0
	var rest_arm_r := 0.0
	var bounce := 0.0

	if celebrating:
		rest_arm_l = -2.6
		rest_arm_r = 2.6
		bounce = absf(sin(Time.get_ticks_msec() as float / 1000.0 * 6.0)) * 0.12
	elif tackling:
		# Slide tackle: lean back, legs forward.
		rest_pelvis = -0.9
		rest_thigh_l = 1.1
		rest_thigh_r = 0.8
		rest_shin_l = -0.2
		rest_shin_r = -0.5
		rest_arm_l = 1.2
		rest_arm_r = -1.0
	elif kicking:
		var k := 1.0 - kick_timer / 0.35
		rest_thigh_r = lerpf(-0.9, 1.3, k)
		rest_shin_r = lerpf(-1.2, 0.1, k)
		rest_arm_l = 0.6
		rest_arm_r = -0.6
		rest_pelvis = 0.15
	elif speed > 0.3:
		var amp := clampf(speed * 0.10, 0.25, 0.95)
		var s := sin(phase * 2.0)
		var c := cos(phase * 2.0)
		rest_thigh_l = s * amp
		rest_thigh_r = -s * amp
		rest_shin_l = clampf(-c * amp * 1.2, -1.6, -0.05)
		rest_shin_r = clampf(c * amp * 1.2, -1.6, -0.05)
		rest_arm_l = -s * amp * 0.8
		rest_arm_r = s * amp * 0.8
		rest_pelvis = 0.08
		bounce = absf(s) * 0.035 * clampf(speed * 0.2, 0.4, 1.4)
	else:
		# Idle sway.
		var t := Time.get_ticks_msec() as float / 1000.0
		rest_pelvis = sin(t * 1.4 + agent.number) * 0.02
		rest_arm_l = sin(t * 1.1 + 1.0) * 0.05
		rest_arm_r = -sin(t * 1.1) * 0.05

	apply_pose(rest_pelvis, rest_thigh_l, rest_thigh_r, rest_shin_l, rest_shin_r, rest_arm_l, rest_arm_r, bounce)


func apply_pose(pelvis_rot: float, tl: float, tr: float, sl: float, sr: float, al: float, ar: float, bounce: float) -> void:
	if pelvis == null:
		return
	pelvis.rotation.x = pelvis_rot
	pelvis.position.y = HIP_Y - 0.06 - bounce
	torso.rotation.x = pelvis_rot * 0.4
	head.rotation.x = -pelvis_rot * 0.5
	thigh_l.rotation.x = tl
	thigh_r.rotation.x = tr
	shin_l.rotation.x = sl
	shin_r.rotation.x = sr
	arm_l.rotation.x = al
	arm_r.rotation.x = ar
	arm_l.rotation.z = 0.18
	arm_r.rotation.z = -0.18

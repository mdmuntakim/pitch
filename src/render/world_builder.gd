class_name WorldBuilder
extends Node3D
## Builds the whole stadium procedurally: pitch surface with the grass shader,
## white line markings, goals with nets, ad boards, stands with instanced crowd,
## floodlights, corner flags, sun/sky and the broadcast environment settings.

var night := false
var ads_textures: Array = []
var crowd_texture: Texture2D = null
var net_texture: Texture2D = null
var detail_texture: Texture2D = null
var ball_texture: Texture2D = null
var scoreboard_texture: Texture2D = null

const CROWD_INSTANCES_PER_STAND := 3200


static func build(parent: Node, night_: bool, textures: Dictionary) -> WorldBuilder:
	var w := WorldBuilder.new()
	w.name = "World"
	w.night = night_
	w.ads_textures = textures.get("ads", [])
	w.crowd_texture = textures.get("crowd", null)
	w.net_texture = textures.get("net", null)
	w.detail_texture = textures.get("grass_detail", null)
	w.ball_texture = textures.get("ball", null)
	w.scoreboard_texture = textures.get("scoreboard", null)
	parent.add_child(w)
	w._build_all()
	return w


func _build_all() -> void:
	_build_environment()
	_build_pitch()
	_build_lines()
	_build_goals()
	_build_ads()
	_build_stands()
	_build_floodlights()
	_build_flags()


# ------------------------------------------------------------------ lighting

func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52 if not night else -38, -35, 0)
	sun.light_energy = 1.25 if not night else 0.35
	sun.light_color = Color(1.0, 0.96, 0.88) if not night else Color(0.72, 0.82, 1.0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 120.0
	sun.shadow_bias = 0.35
	sun.shadow_normal_bias = 3.0
	sun.shadow_blur = 1.4
	add_child(sun)

	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	if night:
		sky_mat.sky_top_color = Color(0.02, 0.03, 0.08)
		sky_mat.sky_horizon_color = Color(0.05, 0.07, 0.12)
		sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.03)
		sky_mat.ground_horizon_color = Color(0.06, 0.07, 0.10)
		sky_mat.sun_angle_max = 8.0
	else:
		sky_mat.sky_top_color = Color(0.18, 0.38, 0.70)
		sky_mat.sky_horizon_color = Color(0.62, 0.74, 0.88)
		sky_mat.ground_bottom_color = Color(0.2, 0.25, 0.3)
		sky_mat.ground_horizon_color = Color(0.55, 0.62, 0.70)
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.0 if not night else 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.65, 0.72, 0.82) if not night else Color(0.08, 0.10, 0.16)
	env.fog_density = 0.004 if not night else 0.006
	env.fog_sky_affect = 0.0
	env.fxaa_enabled = true
	env.ssao_enabled = not night  # mobile renderer: SSAO is ignored; blob shadows cover contact darkening
	env.sdfgi_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


# --------------------------------------------------------------------- pitch

func _build_pitch() -> void:
	var pitch_mesh := PlaneMesh.new()
	pitch_mesh.size = Vector2(Pitch.LENGTH, Pitch.WIDTH)
	var mat := ShaderMaterial.new()
	var sh := load("res://src/render/grass.gdshader") as Shader
	mat.shader = sh
	mat.set_shader_parameter("detail_tex", detail_texture)
	add_child(_mesh_node(pitch_mesh, mat, "Pitch"))
	# Surrounding apron (darker grass).
	var apron := PlaneMesh.new()
	apron.size = Vector2(Pitch.LENGTH + 26.0, Pitch.WIDTH + 22.0)
	var apron_mat := StandardMaterial3D.new()
	apron_mat.albedo_color = Color(0.10, 0.30, 0.08)
	apron_mat.roughness = 1.0
	add_child(_mesh_node(apron, apron_mat, "Apron", -0.02))


func _build_lines() -> void:
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.92, 0.94, 0.92)
	white.roughness = 0.8
	var lines := Node3D.new()
	lines.name = "Lines"
	add_child(lines)
	var L := Pitch.HALF_LENGTH
	var W := Pitch.HALF_WIDTH
	var lw := 0.12
	# Perimeter.
	_quad(lines, Vector3(0, 0.011, -W), Vector2(2 * L + lw, lw))
	_quad(lines, Vector3(0, 0.011, W), Vector2(2 * L + lw, lw))
	_quad(lines, Vector3(-L, 0.011, 0), Vector2(lw, 2 * W + lw))
	_quad(lines, Vector3(L, 0.011, 0), Vector2(lw, 2 * W + lw))
	# Halfway line + centre circle + spot.
	_quad(lines, Vector3(0, 0.011, 0), Vector2(lw, 2 * W))
	_ring(lines, Vector3(0, 0.011, 0), Pitch.CENTER_CIRCLE_RADIUS, lw, 48)
	_quad(lines, Vector3(0, 0.011, 0), Vector2(0.3, 0.3))
	for sx in [-1.0, 1.0]:
		# Penalty area + goal area + spot + arc.
		var px: float = sx * L
		_quad(lines, Vector3(px - sx * Pitch.PENALTY_AREA_DEPTH * 0.5, 0.011, 0), Vector2(Pitch.PENALTY_AREA_DEPTH, Pitch.PENALTY_AREA_WIDTH))
		_quad(lines, Vector3(px - sx * Pitch.GOAL_AREA_DEPTH * 0.5, 0.011, 0), Vector2(Pitch.GOAL_AREA_DEPTH, Pitch.GOAL_AREA_WIDTH))
		_quad(lines, Vector3(px - sx * Pitch.PENALTY_SPOT_FROM_GOAL, 0.011, 0), Vector2(0.25, 0.25))
		# Penalty arc: portion of circle radius 9.15 around the spot outside the box.
		_arc(lines, Vector3(px - sx * Pitch.PENALTY_SPOT_FROM_GOAL, 0.011, 0), 9.15, lw, 24, sx)
		# Corner arcs at both corners on this side.
		for sz in [-1.0, 1.0]:
			_corner_arc(lines, Vector3(px, 0.011, sz * W), sx, sz)


func _quad(parent: Node3D, pos: Vector3, size: Vector2) -> void:
	var m := PlaneMesh.new()
	m.size = size
	var mi := _mesh_node(m, _white_mat(), "line")
	mi.position = pos
	parent.add_child(mi)


func _white_mat() -> StandardMaterial3D:
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.92, 0.94, 0.92)
	white.roughness = 0.8
	return white


func _ring(parent: Node3D, center: Vector3, radius: float, width: float, segments: int) -> void:
	var st := SurfaceTool.new()
	_st(st, center, radius, width, segments, 0.0, TAU)
	parent.add_child(_finish_st(st))


func _arc(parent: Node3D, center: Vector3, radius: float, width: float, segments: int, side_x: float) -> void:
	# Draw the half of the circle that bulges away from the goal line.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := PI
	for i in segments:
		var a0 := -half * 0.5 + i / float(segments) * half
		var a1 := -half * 0.5 + (i + 1) / float(segments) * half
		var dir0 := Vector3(cos(a0) * side_x, 0, sin(a0))
		var dir1 := Vector3(cos(a1) * side_x, 0, sin(a1))
		_ring_segment(st, center, dir0, dir1, radius, width)
	parent.add_child(_finish_st(st))


func _corner_arc(parent: Node3D, corner: Vector3, sx: float, sz: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 10
	for i in segments:
		var a0 := i / float(segments) * (PI * 0.5)
		var a1 := (i + 1) / float(segments) * (PI * 0.5)
		# Arc opens toward the pitch interior.
		var dir0 := Vector3(-sx * cos(a0), 0, -sz * sin(a0))
		var dir1 := Vector3(-sx * cos(a1), 0, -sz * sin(a1))
		_ring_segment(st, corner, dir0, dir1, Pitch.CORNER_ARC_RADIUS, 0.1)
	parent.add_child(_finish_st(st))


func _st(st: SurfaceTool, center: Vector3, radius: float, width: float, segments: int, a_start: float, a_end: float) -> void:
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var a0 := a_start + i / float(segments) * (a_end - a_start)
		var a1 := a_start + (i + 1) / float(segments) * (a_end - a_start)
		_ring_segment(st, center, Vector3(cos(a0), 0, sin(a0)), Vector3(cos(a1), 0, sin(a1)), radius, width)


func _ring_segment(st: SurfaceTool, center: Vector3, dir0: Vector3, dir1: Vector3, radius: float, width: float) -> void:
	var p0i := center + dir0 * (radius - width * 0.5)
	var p0o := center + dir0 * (radius + width * 0.5)
	var p1i := center + dir1 * (radius - width * 0.5)
	var p1o := center + dir1 * (radius + width * 0.5)
	var y := 0.011
	st.set_uv(Vector2(0, 0))
	st.add_vertex(Vector3(p0i.x, y, p0i.z))
	st.add_vertex(Vector3(p1i.x, y, p1i.z))
	st.add_vertex(Vector3(p1o.x, y, p1o.z))
	st.add_vertex(Vector3(p0i.x, y, p0i.z))
	st.add_vertex(Vector3(p1o.x, y, p1o.z))
	st.add_vertex(Vector3(p0o.x, y, p0o.z))


func _finish_st(st: SurfaceTool) -> MeshInstance3D:
	st.generate_normals(false)
	var mesh := st.commit()
	return _mesh_node(mesh, _white_mat(), "arc")


func _mesh_node(mesh: Mesh, mat: Material, name_: String, y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.name = name_
	mi.position.y = y
	return mi


# --------------------------------------------------------------------- goals

func _build_goals() -> void:
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.95, 0.95, 0.95)
	post_mat.roughness = 0.4
	post_mat.metallic = 0.2
	for sx in [-1.0, 1.0]:
		var gx: float = sx * Pitch.HALF_LENGTH
		var goal := Node3D.new()
		goal.name = "Goal" + ("L" if sx < 0 else "R")
		add_child(goal)
		for sz in [-1.0, 1.0]:
			var post := CylinderMesh.new()
			post.top_radius = 0.06
			post.bottom_radius = 0.06
			post.height = Pitch.GOAL_HEIGHT
			var mi := _mesh_node(post, post_mat, "post")
			mi.position = Vector3(gx, Pitch.GOAL_HEIGHT * 0.5, sz * Pitch.GOAL_WIDTH * 0.5)
			goal.add_child(mi)
		var bar := CylinderMesh.new()
		bar.top_radius = 0.06
		bar.bottom_radius = 0.06
		bar.height = Pitch.GOAL_WIDTH + 0.12
		var barmi := _mesh_node(bar, post_mat, "bar")
		barmi.rotation_degrees = Vector3(90, 0, 0)
		barmi.position = Vector3(gx, Pitch.GOAL_HEIGHT, 0)
		goal.add_child(barmi)
		# Net: three planes (back, two sides, roof) with a grid texture.
		if net_texture != null:
			var net_mat := StandardMaterial3D.new()
			net_mat.albedo_texture = net_texture
			net_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			net_mat.albedo_color = Color(1, 1, 1, 0.35)
			net_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			net_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			var back := PlaneMesh.new()
			back.size = Vector2(Pitch.GOAL_WIDTH, Pitch.GOAL_HEIGHT)
			var backmi := _mesh_node(back, net_mat, "net_back")
			backmi.position = Vector3(gx + sx * Pitch.GOAL_DEPTH, Pitch.GOAL_HEIGHT * 0.5, 0)
			backmi.rotation_degrees = Vector3(0, 90, 0)
			goal.add_child(backmi)
			for sz in [-1.0, 1.0]:
				var side := PlaneMesh.new()
				side.size = Vector2(Pitch.GOAL_DEPTH, Pitch.GOAL_HEIGHT)
				var sidemi := _mesh_node(side, net_mat, "net_side")
				sidemi.position = Vector3(gx + sx * Pitch.GOAL_DEPTH * 0.5, Pitch.GOAL_HEIGHT * 0.5, sz * Pitch.GOAL_WIDTH * 0.5)
				goal.add_child(sidemi)
			var roof := PlaneMesh.new()
			roof.size = Vector2(Pitch.GOAL_DEPTH, Pitch.GOAL_WIDTH)
			var roofmi := _mesh_node(roof, net_mat, "net_roof")
			roofmi.position = Vector3(gx + sx * Pitch.GOAL_DEPTH * 0.5, Pitch.GOAL_HEIGHT, 0)
			roofmi.rotation_degrees = Vector3(90, 0, 0)
			goal.add_child(roofmi)


# ----------------------------------------------------------------- ad boards

func _build_ads() -> void:
	if ads_textures.is_empty():
		return
	var y := 0.55
	var boards := Node3D.new()
	boards.name = "AdBoards"
	add_child(boards)
	var board_len := 14.0
	var count := 0
	for side in 4:
		var along_z := side < 2
		var sign_dir := -1.0 if side % 2 == 0 else 1.0
		for i in 8:
			var tex: Texture2D = ads_textures[count % ads_textures.size()]
			count += 1
			var mat := StandardMaterial3D.new()
			mat.albedo_texture = tex
			mat.roughness = 0.35
			mat.emission_enabled = true
			mat.emission_energy_multiplier = 0.25 if not night else 0.9
			mat.emission = Color(0.6, 0.6, 0.6)
			var m := BoxMesh.new()
			var board_len_x := board_len if along_z else 1.0
			var board_len_z := 1.0 if along_z else board_len
			m.size = Vector3(board_len_x, 1.1, board_len_z)
			var mi := _mesh_node(m, mat, "ad")
			var offset := -Pitch.HALF_LENGTH + 4.0 + i * board_len
			if along_z:
				mi.position = Vector3(offset * 0.5 + 26.0 - 52.0 * (i / 8.0) + i * 0.0, y, sign_dir * (Pitch.HALF_WIDTH + 2.2))
				mi.position.x = -Pitch.HALF_LENGTH + 4.0 + i * board_len
			else:
				mi.position = Vector3(sign_dir * (Pitch.HALF_LENGTH + 2.2), y, -Pitch.HALF_WIDTH + 4.0 + i * board_len)
				mi.rotation_degrees = Vector3(0, 90 * sign_dir * -1.0 + 0.0, 0)
				mi.rotation.y = deg_to_rad(90.0 * sign_dir)
			boards.add_child(mi)


# -------------------------------------------------------------------- stands

func _build_stands() -> void:
	var stand_mat := StandardMaterial3D.new()
	if crowd_texture != null:
		stand_mat.albedo_texture = crowd_texture
		stand_mat.uv1_scale = Vector3(14, 5, 1)
		stand_mat.roughness = 0.95
	stand_mat.albedo_color = Color(0.9, 0.9, 0.9) if crowd_texture == null else Color(1, 1, 1, 1)

	var stands := Node3D.new()
	stands.name = "Stands"
	add_child(stands)
	var dist_x := Pitch.HALF_LENGTH + 14.0
	var dist_z := Pitch.HALF_WIDTH + 12.0
	for side in 4:
		var stand := MeshInstance3D.new()
		var m := BoxMesh.new()
		if side < 2:
			m.size = Vector3(128.0, 16.0, 22.0)
		else:
			m.size = Vector3(22.0, 16.0, 96.0)
		stand.mesh = m
		stand.material_override = stand_mat
		var tilt := 32.0
		match side:
			0:
				stand.position = Vector3(0, 2.0, -dist_z - 4.0)
				stand.rotation_degrees = Vector3(-tilt, 0, 0)
			1:
				stand.position = Vector3(0, 2.0, dist_z + 4.0)
				stand.rotation_degrees = Vector3(tilt, 0, 0)
			2:
				stand.position = Vector3(-dist_x - 4.0, 2.0, 0)
				stand.rotation_degrees = Vector3(0, 0, tilt)
			3:
				stand.position = Vector3(dist_x + 4.0, 2.0, 0)
				stand.rotation_degrees = Vector3(0, 0, -tilt)
		stands.add_child(stand)
	_build_instanced_crowd(stands, dist_x, dist_z)


func _build_instanced_crowd(stands: Node3D, dist_x: float, dist_z: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3(0.38, 0.55, 0.30)
	mm.mesh = box
	var total := CROWD_INSTANCES_PER_STAND * 4
	mm.instance_count = total
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var idx := 0
	var crowd_cols := [Color(0.75, 0.2, 0.2), Color(0.2, 0.3, 0.7), Color(0.85, 0.8, 0.7), Color(0.2, 0.6, 0.3), Color(0.9, 0.7, 0.2), Color(0.5, 0.5, 0.55), Color(0.8, 0.3, 0.5), Color(0.25, 0.25, 0.3)]
	for side in 4:
		for i in CROWD_INSTANCES_PER_STAND:
			var row := int(rng.randf_range(0, 14))
			var col := int(rng.randf_range(0, 42))
			var t := Transform3D(Basis.IDENTITY, Vector3.ZERO)
			var seat_y := 3.2 + row * 0.95
			match side:
				0:
					t.origin = Vector3(-60.0 + col * 2.9 + rng.randf_range(-0.5, 0.5), seat_y, -dist_z - 2.0 - row * 1.35)
				1:
					t.origin = Vector3(-60.0 + col * 2.9 + rng.randf_range(-0.5, 0.5), seat_y, dist_z + 2.0 + row * 1.35)
				2:
					t.origin = Vector3(-dist_x - 2.0 - row * 1.35, seat_y, -44.0 + col * 2.1 + rng.randf_range(-0.5, 0.5))
				3:
					t.origin = Vector3(dist_x + 2.0 + row * 1.35, seat_y, -44.0 + col * 2.1 + rng.randf_range(-0.5, 0.5))
			t.basis = Basis(Vector3.UP, rng.randf_range(-0.2, 0.2))
			mm.set_instance_transform(idx, t)
			mm.set_instance_color(idx, crowd_cols[rng.randi() % crowd_cols.size()])
			idx += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mmi.material_override = mat
	mmi.name = "Crowd"
	stands.add_child(mmi)


# --------------------------------------------------------------- floodlights

func _build_floodlights() -> void:
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.9, 0.9, 0.95)
	head_mat.emission_enabled = true
	head_mat.emission = Color(1.0, 0.98, 0.9)
	head_mat.emission_energy_multiplier = 0.4 if not night else 4.0
	for corner in [[-1.0, -1.0], [1.0, -1.0], [-1.0, 1.0], [1.0, 1.0]]:
		var px: float = corner[0] * (Pitch.HALF_LENGTH + 20.0)
		var pz: float = corner[1] * (Pitch.HALF_WIDTH + 20.0)
		var pole := CylinderMesh.new()
		pole.top_radius = 0.5
		pole.bottom_radius = 0.9
		pole.height = 34.0
		var pole_mat := StandardMaterial3D.new()
		pole_mat.albedo_color = Color(0.35, 0.37, 0.4)
		var polemi := _mesh_node(pole, pole_mat, "pole")
		polemi.position = Vector3(px, 17.0, pz)
		add_child(polemi)
		var head := BoxMesh.new()
		head.size = Vector3(6.0, 3.0, 1.2)
		var headmi := _mesh_node(head, head_mat, "floodlight_head")
		headmi.position = Vector3(px, 34.0, pz)
		headmi.look_at_from_position(headmi.position, Vector3(0, 0, 0), Vector3.UP)
		add_child(headmi)
		if night:
			var spot := SpotLight3D.new()
			spot.spot_range = 90.0
			spot.spot_angle = 42.0
			spot.light_energy = 3.2
			spot.light_color = Color(1.0, 0.97, 0.88)
			spot.shadow_enabled = false
			spot.position = Vector3(px, 33.5, pz)
			spot.look_at_from_position(spot.position, Vector3(0, 0, 0), Vector3.UP)
			add_child(spot)


func _build_flags() -> void:
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.9, 0.9, 0.9)
	var flag_mat := StandardMaterial3D.new()
	flag_mat.albedo_color = Color(0.9, 0.15, 0.2)
	flag_mat.albedo_texture = null
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var pole := CylinderMesh.new()
			pole.top_radius = 0.02
			pole.bottom_radius = 0.02
			pole.height = 1.5
			var mi := _mesh_node(pole, pole_mat, "flag_pole")
			mi.position = Vector3(sx * Pitch.HALF_LENGTH, 0.75, sz * Pitch.HALF_WIDTH)
			add_child(mi)
			var flag := BoxMesh.new()
			flag.size = Vector3(0.02, 0.25, 0.4)
			var fmi := _mesh_node(flag, flag_mat, "flag")
			fmi.position = Vector3(sx * Pitch.HALF_LENGTH, 1.35, sz * (Pitch.HALF_WIDTH - 0.2))
			add_child(fmi)

extends Node3D
## Matchday Eleven - main scene wiring.
## Builds menu -> match (world, teams, HUD, controls, audio, camera, replay),
## handles half-time/full-time overlays and the broadcast camera.

var menu: Menu
var world: WorldBuilder
var match_node: Match
var hud: HUD
var controls: TouchControls
var audio: AudioBank
var replay: Replay
var camera: Camera3D
var kick_overlay: Control
var frame_accum := 0.0
var frames := 0
var perf_samples := []
var match_config := {}

const SAVE_CFG := "user://settings.cfg"


func _ready() -> void:
	# Load textures and hand them to whoever needs them.
	var textures := _load_textures()
	# Menu first.
	controls = TouchControls.attach(null)
	controls.visible = false
	add_child(controls)
	menu = Menu.attach(controls)
	add_child(menu)
	menu.start_requested.connect(_start_match)
	# Boot straight into the menu; the match is built on demand.
	camera = Camera3D.new()
	camera.fov = 30.0
	add_child(camera)
	# Menu backdrop camera: slow orbit over the pitch.
	var backdrop_world := WorldBuilder.build(self, false, textures, false)
	backdrop_world.name = "MenuWorld"
	menu_backdrop_world = backdrop_world
	_load_saved_settings()


var menu_backdrop_world: Node3D = null


func _load_saved_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_CFG) == OK:
		menu.half_minutes = cfg.get_value("match", "half_minutes", 6)
		menu.night = cfg.get_value("match", "night", false)
		menu.difficulty = cfg.get_value("match", "difficulty", 0.5)
		menu.formation_idx = cfg.get_value("match", "formation_idx", 0)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("match", "half_minutes", menu.half_minutes)
	cfg.set_value("match", "night", menu.night)
	cfg.set_value("match", "difficulty", menu.difficulty)
	cfg.set_value("match", "formation_idx", menu.formation_idx)
	cfg.save(SAVE_CFG)


func _load_textures() -> Dictionary:
	var d := {}
	for key in ["ads", "crowd", "net", "grass_detail", "ball", "scoreboard", "kit_fabric"]:
		var paths: Array = []
		match key:
			"ads":
				for i in 6:
					paths.append("res://assets/textures/ad_%d.png" % i)
			_:
				paths.append("res://assets/textures/%s.png" % key)
		var loaded := []
		for p in paths:
			var tex := load(p)
			if tex != null:
				loaded.append(tex)
		if loaded.size() == 1:
			d[key] = loaded[0]
		elif loaded.size() > 1:
			d[key] = loaded
	return d


func _start_match(cfg: Dictionary) -> void:
	match_config = cfg
	_save_settings()
	menu.hide_menu()
	menu_backdrop_world.visible = false
	controls.visible = true
	# Build match world.
	world = WorldBuilder.build(self, cfg.get("night", false), _load_textures())
	match_node = Match.new()
	match_node.name = "Match"
	match_node.configure({
		"half_length_seconds": cfg.get("half_length_seconds", 360.0),
		"night": cfg.get("night", false),
		"difficulty": cfg.get("difficulty", 0.5),
		"seed": randi(),
	})
	add_child(match_node)
	# Views for every player.
	var teams: Array = match_node.teams
	for t in teams:
		var team: Team = t
		for p in team.players:
			var v := PlayerView.build(p, team)
			p.view = v
	# Blob shadows.
	_attach_blob_shadows(teams)
	hud = HUD.attach(match_node)
	add_child(hud)
	hud.match_ref = match_node
	match_node.event_banner.connect(hud.show_banner)
	match_node.card_banner.connect(hud.show_card)
	match_node.shot_charging.connect(func(power: float) -> void:
		hud.set_charging(power)
		controls._redraw())
	match_node.goal_happened.connect(_on_goal)
	match_node.match_ended.connect(_on_match_ended)
	controls.match_ref = match_node
	controls._layout_buttons()
	audio = AudioBank.attach(self, match_node)
	replay = Replay.attach(match_node)
	replay.from_camera = camera
	_apply_ball_texture()
	match_node.state.start_match()
	audio.whistle_play()
	_camera_update(0.0, true)


func _attach_blob_shadows(teams: Array) -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.4))
	grad.set_color(1, Color(0, 0, 0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 1.0)
	gt.width = 64
	gt.height = 64
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = gt
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for t in teams:
		for p in t.players:
			var blob := MeshInstance3D.new()
			var q := PlaneMesh.new()
			q.size = Vector2(0.9, 0.9)
			blob.mesh = q
			blob.material_override = mat
			blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(p as Node3D).add_child(blob)
			blob.position.y = 0.012
			blob.name = "BlobShadow"


func _on_goal(_team_idx: int, _scorer: int) -> void:
	audio.goal_roar()
	hud.show_banner("GOAL!")
	# Celebrate scorers briefly, then replay.
	for t in match_node.teams:
		for p in t.players:
			if (p as PlayerAgent).role_group == "attacker" and not (p as PlayerAgent).sent_off:
				(p as PlayerAgent).celebrate(4.0)
	hud.set_replay_visible(true)
	replay.finished.connect(_replay_done, CONNECT_ONE_SHOT)
	replay.start()


func _replay_done() -> void:
	hud.set_replay_visible(false)
	Engine.time_scale = 1.0


func _apply_ball_texture() -> void:
	var tex := load("res://assets/textures/ball.png")
	if tex == null:
		return
	var sphere := SphereMesh.new()
	sphere.radius = Pitch.BALL_RADIUS
	sphere.height = Pitch.BALL_RADIUS * 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.roughness = 0.35
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	match_node.ball.add_child(mi)


func _on_match_ended(a: int, b: int) -> void:
	controls.visible = false
	hud.show_banner("FULL TIME  %d - %d" % [a, b])
	_show_kick_overlay("FULL TIME\n%d - %d\n\nBack to menu" % [a, b])


func _process(dt: float) -> void:
	# Performance sampling for the frame-time report.
	frame_accum += dt
	frames += 1
	if frame_accum >= 1.0:
		var ms := 1000.0 * frame_accum / frames
		perf_samples.append(ms)
		frame_accum = 0.0
		frames = 0
		if hud != null:
			hud.fps_label.visible = true
	# Menu backdrop: slow orbit.
	if menu != null and menu._panel.visible and menu_backdrop_world != null:
		var t := Time.get_ticks_msec() as float / 1000.0
		camera.position = Vector3(sin(t * 0.08) * 55.0, 26.0, cos(t * 0.08) * 55.0)
		camera.look_at(Vector3(0, 0, 0), Vector3.UP)
	elif match_node != null:
		_camera_update(dt, false)
	# Half-time continuation.
	if match_node != null and match_node.state.phase == MatchState.Phase.HALF_TIME and kick_overlay == null:
		_show_kick_overlay("HALF TIME\n%s\n\nTap to continue" % match_node.score_display())
		match_node.state.set_phase(MatchState.Phase.HALF_TIME)  # hold state


func _input(event: InputEvent) -> void:
	if kick_overlay != null and (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed):
		get_tree().create_timer(0.1).timeout.connect(_kick_overlay_continue)


func _kick_overlay_continue() -> void:
	if kick_overlay == null:
		return
	var was_halftime := match_node.state.phase == MatchState.Phase.HALF_TIME
	kick_overlay.queue_free()
	kick_overlay = null
	if was_halftime:
		match_node.start_second_half()
		audio.whistle_play()
	else:
		# Back to menu: free the match world.
		_back_to_menu()


func _back_to_menu() -> void:
	for n in [world, match_node, hud, audio, replay]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	world = null
	match_node = null
	hud = null
	audio = null
	replay = null
	menu_backdrop_world.visible = true
	menu.show_menu()
	controls.visible = false
	controls.match_ref = null


func _show_kick_overlay(text: String) -> void:
	if kick_overlay != null:
		return
	kick_overlay = Control.new()
	kick_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	layer.add_child(kick_overlay)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	kick_overlay.add_child(bg)
	var lbl := Label.new()
	lbl.text = text
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 40)
	lbl.position = Vector2(-300, -80)
	lbl.size = Vector2(600, 200)
	kick_overlay.add_child(lbl)


func _camera_update(dt: float, snap: bool) -> void:
	if match_node == null or match_node.ball == null:
		return
	var ball_pos: Vector3 = match_node.ball.global_position
	var target_x := clampf(ball_pos.x * 0.82, -34.0, 34.0)
	var target_pos := Vector3(target_x, 21.0, 44.0)
	if snap:
		camera.position = target_pos
	else:
		camera.position = camera.position.lerp(target_pos, clampf(dt * 2.2, 0.0, 1.0))
	var look := ball_pos + match_node.ball.velocity * 0.35
	look.y = 1.0
	camera.look_at(look, Vector3.UP)
	# Gentle zoom with ball height/distance from touchline.
	camera.fov = lerpf(camera.fov, clampf(34.0 - absf(ball_pos.z) * 0.08, 26.0, 34.0), clampf(dt * 1.5, 0, 1))

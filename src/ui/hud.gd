class_name HUD
extends CanvasLayer
## Match HUD: scoreboard, clock, event banners, charge bar, radar/minimap,
## card indicator and the REPLAY flag. All drawn with Controls; minimap uses
## _draw() for cheap rendering.

signal continue_requested

var match_ref: Match
var scoreboard: Label
var clock_label: Label
var banner: Label
var banner_timer := 0.0
var charge_bar: ProgressBar
var charge_panel: PanelContainer
var minimap: Control
var replay_flag: Label
var fps_label: Label
var half_label: Label
var card_label: Label

const MINIMAP_W := 220.0
const MINIMAP_H := 150.0


static func attach(match_ref_: Match) -> HUD:
	var h := HUD.new()
	h.name = "HUD"
	h.match_ref = match_ref_
	h._build()
	return h


func _build() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var sb_panel := PanelContainer.new()
	var sb_style := StyleBoxFlat.new()
	sb_style.bg_color = Color(0, 0, 0, 0.65)
	sb_style.corner_radius_bottom_right = 6
	sb_style.corner_radius_bottom_left = 6
	sb_style.content_margin_left = 10
	sb_style.content_margin_right = 10
	sb_style.content_margin_top = 4
	sb_style.content_margin_bottom = 4
	sb_panel.add_theme_stylebox_override("panel", sb_style)
	sb_panel.position = Vector2(14, 0)
	sb_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(sb_panel)
	var sb_row := HBoxContainer.new()
	sb_row.add_theme_constant_override("separation", 10)
	sb_panel.add_child(sb_row)
	var home := Label.new()
	home.text = match_ref.teams[0].short_name
	home.add_theme_color_override("font_color", Color(1, 0.75, 0.75))
	sb_row.add_child(home)
	scoreboard = Label.new()
	scoreboard.text = "0 - 0"
	scoreboard.add_theme_font_size_override("font_size", 22)
	sb_row.add_child(scoreboard)
	var away := Label.new()
	away.text = match_ref.teams[1].short_name
	away.add_theme_color_override("font_color", Color(0.75, 0.82, 1))
	sb_row.add_child(away)
	clock_label = Label.new()
	clock_label.text = "00:00"
	clock_label.add_theme_color_override("font_color", Color(0.85, 1, 0.85))
	sb_row.add_child(clock_label)
	half_label = Label.new()
	half_label.text = "1st"
	sb_row.add_child(half_label)

	banner = Label.new()
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.position = Vector2(0, 70)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 26)
	banner.add_theme_color_override("font_color", Color(1, 1, 1))
	banner.add_theme_constant_override("outline_size", 8)
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	banner.size = Vector2(1200, 40)
	banner.anchors_preset = Control.PRESET_TOP_WIDE
	banner.offset_top = 70.0
	banner.visible = false
	root.add_child(banner)

	replay_flag = Label.new()
	replay_flag.text = "REPLAY"
	replay_flag.add_theme_font_size_override("font_size", 34)
	replay_flag.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	replay_flag.add_theme_constant_override("outline_size", 10)
	replay_flag.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	replay_flag.anchors_preset = Control.PRESET_TOP_WIDE
	replay_flag.offset_top = 120.0
	replay_flag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	replay_flag.visible = false
	root.add_child(replay_flag)

	card_label = Label.new()
	card_label.anchors_preset = Control.PRESET_TOP_WIDE
	card_label.offset_top = 34.0
	card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_label.add_theme_font_size_override("font_size", 20)
	card_label.visible = false
	root.add_child(card_label)

	# Charge bar (shot power) bottom-right.
	charge_panel = PanelContainer.new()
	var cp_style := StyleBoxFlat.new()
	cp_style.bg_color = Color(0, 0, 0, 0.5)
	cp_style.content_margin_left = 4
	cp_style.content_margin_right = 4
	cp_style.content_margin_top = 4
	cp_style.content_margin_bottom = 4
	charge_panel.add_theme_stylebox_override("panel", cp_style)
	charge_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	charge_panel.position = Vector2(-320, -86)
	charge_panel.size = Vector2(220, 22)
	charge_panel.visible = false
	root.add_child(charge_panel)
	charge_bar = ProgressBar.new()
	charge_bar.min_value = 0
	charge_bar.max_value = 1.0
	charge_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.2, 1.0, 0.3)
	charge_bar.add_theme_stylebox_override("fill", fill)
	charge_bar.custom_minimum_size = Vector2(200, 14)
	charge_panel.add_child(charge_bar)

	# Minimap radar, bottom-center.
	minimap = Control.new()
	minimap.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	minimap.position = Vector2(-MINIMAP_W * 0.5, -MINIMAP_H - 12)
	minimap.size = Vector2(MINIMAP_W, MINIMAP_H)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.draw.connect(_draw_minimap)
	root.add_child(minimap)

	# FPS / frame time readout, top-right (part of the performance evidence).
	fps_label = Label.new()
	fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	fps_label.position = Vector2(-150, 10)
	fps_label.text = ""
	fps_label.add_theme_font_size_override("font_size", 14)
	fps_label.add_theme_color_override("font_color", Color(0.7, 1, 0.7))
	root.add_child(fps_label)


func _process(dt: float) -> void:
	scoreboard.text = match_ref.score_display()
	clock_label.text = match_ref.state.clock_display()
	half_label.text = "1st" if match_ref.state.half <= 1 else "2nd"
	if banner_timer > 0.0:
		banner_timer -= dt
		if banner_timer <= 0.0:
			banner.visible = false
	var fps := Engine.get_frames_per_second()
	if fps > 0:
		fps_label.text = "%d fps  %.1f ms" % [fps, 1000.0 / fps]
	if minimap != null:
		minimap.queue_redraw()


func show_banner(text: String) -> void:
	banner.text = text
	banner.visible = true
	banner_timer = 2.4


func show_card(team_idx: int, number: int, card: String) -> void:
	var col := Color(1, 0.85, 0.2) if card == "yellow" else Color(1, 0.2, 0.2)
	card_label.text = "%s  %s  #%d" % [card.capitalize(), match_ref.teams[team_idx].short_name, number]
	card_label.add_theme_color_override("font_color", col)
	card_label.visible = true
	var t := get_tree().create_timer(2.5)
	t.timeout.connect(func() -> void: card_label.visible = false)


func set_charging(power: float) -> void:
	if power < 0.0:
		charge_panel.visible = false
	else:
		charge_panel.visible = true
		charge_bar.value = power


func set_replay_visible(v: bool) -> void:
	replay_flag.visible = v


func _draw_minimap() -> void:
	if match_ref == null:
		return
	var m := minimap
	var w := m.size.x
	var h := m.size.y
	# Pitch background.
	m.draw_rect(Rect2(0, 0, w, h), Color(0.05, 0.35, 0.08, 0.75))
	m.draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.8), false, 1.5)
	m.draw_line(Vector2(w * 0.5, 0), Vector2(w * 0.5, h), Color(1, 1, 1, 0.6), 1.0)
	m.draw_circle(Vector2(w * 0.5, h * 0.5), 12.0, Color(1, 1, 1, 0), false, 0.6, true)
	m.draw_arc(Vector2(w * 0.5, h * 0.5), 12.0, 0, TAU, 24, Color(1, 1, 1, 0.6), 0.6, true)
	var to_map := func(p: Vector3) -> Vector2:
		return Vector2(w * 0.5 + p.x / Pitch.LENGTH * w, h * 0.5 + p.z / Pitch.WIDTH * h)
	for ti in 2:
		var col := Color(1, 0.4, 0.4) if ti == 0 else Color(0.4, 0.55, 1)
		for p in match_ref.teams[ti].players:
			if (p as PlayerAgent).sent_off:
				continue
			var mp: Vector2 = to_map.call((p as Node3D).position)
			m.draw_circle(mp, 2.6, col)
			if p == match_ref.controlled:
				m.draw_circle(mp, 4.6, Color(1, 1, 0.2), false, 1.4, true)
	var ballp: Vector2 = to_map.call(match_ref.ball.global_position)
	m.draw_circle(ballp, 2.2, Color(1, 1, 1))

class_name Menu
extends CanvasLayer
## Main menu: kick off a match (half length, formation, day/night, difficulty)
## and the control settings panel (button size, opacity, handedness, haptics).

signal start_requested(cfg: Dictionary)

var controls: TouchControls = null
var half_minutes := 6
var formation_idx := 0
var night := false
var difficulty := 0.5

var _panel: Control


static func attach(controls_ref: TouchControls) -> Menu:
	var m := Menu.new()
	m.name = "Menu"
	m.controls = controls_ref
	m._build()
	return m


func _build() -> void:
	layer = 30
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.09, 0.04)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(bg)
	# Pitch stripe backdrop drawn with rects.
	for i in 12:
		var stripe := ColorRect.new()
		stripe.color = Color(0.03, 0.13, 0.05) if i % 2 == 0 else Color(0.0, 0, 0, 0)
		stripe.position = Vector2(i * 160, 0)
		stripe.size = Vector2(160, 1080)
		_panel.add_child(stripe)

	var title := Label.new()
	title.text = "MATCHDAY ELEVEN"
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 110.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "An original 11v11 football simulation"
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.set_anchors_preset(Control.PRESET_TOP_WIDE)
	subtitle.offset_top = 190.0
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.8, 0.85, 0.8))
	_panel.add_child(subtitle)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-260, -160)
	box.custom_minimum_size = Vector2(520, 320)
	box.add_theme_constant_override("separation", 14)
	_panel.add_child(box)

	box.add_child(_button("KICK OFF", func() -> void: _emit_start()))
	var formations := ["4-4-2", "4-3-3", "3-5-2"]
	var fbtn: Button = null
	var hbtn: Button = null
	var tbtn: Button = null
	var dbtn: Button = null
	fbtn = _chooser(box, "Formation", formations[formation_idx], func() -> void:
		formation_idx = (formation_idx + 1) % formations.size()
		fbtn.text = formations[formation_idx] + " >"
	)
	hbtn = _chooser(box, "Half length", "%d min" % half_minutes, func() -> void:
		var choices := [3, 5, 6, 10, 20]
		var i := choices.find(half_minutes)
		half_minutes = choices[(i + 1) % choices.size()]
		hbtn.text = "%d min >" % half_minutes
	)
	tbtn = _chooser(box, "Time", "Day" if not night else "Night", func() -> void:
		night = not night
		tbtn.text = ("Night" if night else "Day") + " >"
	)
	dbtn = _chooser(box, "Difficulty", "Pro", func() -> void:
		difficulty = fmod(difficulty + 0.34, 1.01)
		dbtn.text = "Difficulty lvl %d >" % int(difficulty * 3.0)
	)

	var settings_btn := _button("CONTROLS SETTINGS", func() -> void: _open_settings())
	box.add_child(settings_btn)

	var note := Label.new()
	note.text = "Original game and assets. Keyboard: WASD move, J pass, SPACE shoot (hold), K through, L lob, I sprint, U tackle."
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", Color(0.6, 0.7, 0.6))
	note.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	note.offset_top = -60.0
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(note)


func _chooser(parent: Control, label_text: String, value_text: String, on_cycle: Callable) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(180, 0)
	row.add_child(lbl)
	var btn := _button(value_text + " >", on_cycle)
	btn.custom_minimum_size = Vector2(240, 0)
	row.add_child(btn)
	parent.add_child(row)
	return btn


func _button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(520, 54)
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(on_pressed)
	return b


func _open_settings() -> void:
	var dlg := Window.new()
	dlg.title = "Controls Settings"
	dlg.size = Vector2(560, 380)
	dlg.position = Vector2(680, 350)
	_panel.add_child(dlg)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	dlg.add_child(v)
	if controls == null:
		var l := Label.new()
		l.text = "Controls not attached yet."
		v.add_child(l)
		return
	var scale_row := HBoxContainer.new()
	scale_row.add_child(_mklabel("Button size"))
	var s := HSlider.new()
	s.min_value = 0.7
	s.max_value = 1.6
	s.step = 0.05
	s.value = controls.button_scale
	s.custom_minimum_size = Vector2(300, 24)
	s.value_changed.connect(func(val: float) -> void:
		controls.set_settings(val, controls.opacity, controls.left_handed, controls.haptics))
	scale_row.add_child(s)
	v.add_child(scale_row)
	var op_row := HBoxContainer.new()
	op_row.add_child(_mklabel("Opacity"))
	var o := HSlider.new()
	o.min_value = 0.2
	o.max_value = 0.9
	o.step = 0.05
	o.value = controls.opacity
	o.custom_minimum_size = Vector2(300, 24)
	o.value_changed.connect(func(val: float) -> void:
		controls.set_settings(controls.button_scale, val, controls.left_handed, controls.haptics))
	op_row.add_child(o)
	v.add_child(op_row)
	var hand := CheckButton.new()
	hand.text = "Left-handed layout"
	hand.button_pressed = controls.left_handed
	hand.toggled.connect(func(on: bool) -> void:
		controls.set_settings(controls.button_scale, controls.opacity, on, controls.haptics))
	v.add_child(hand)
	var hap := CheckButton.new()
	hap.text = "Haptic feedback"
	hap.button_pressed = controls.haptics
	hap.toggled.connect(func(on: bool) -> void:
		controls.set_settings(controls.button_scale, controls.opacity, controls.left_handed, on))
	v.add_child(hap)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(dlg.queue_free)
	v.add_child(close)


func _mklabel(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.custom_minimum_size = Vector2(180, 0)
	return l


func _emit_start() -> void:
	var cfg := {
		"half_length_seconds": half_minutes * 60.0,
		"night": night,
		"difficulty": difficulty,
		"formation_user": ["4-4-2", "4-3-3", "3-5-2"][formation_idx],
	}
	start_requested.emit(cfg)


func hide_menu() -> void:
	_panel.visible = false


func show_menu() -> void:
	_panel.visible = true

class_name TouchControls
extends CanvasLayer
## eFootball-style on-screen controls:
##  - Left thumb: floating virtual joystick (appears where the thumb lands).
##  - Right thumb: action cluster - pass, shoot (hold to charge), through ball,
##    lob/cross, sprint (hold), pressure/tackle (contextual label).
##  - True multi-touch: every finger is tracked independently, actions fire in
##    _input() (not polled) so latency stays well under a frame budget.
##  - Button size, opacity, layout side and haptics are adjustable and saved.

signal settings_changed

var match_ref: Match
var enabled := true

# Live input state.
var joy_active := false
var joy_index := -1
var joy_center := Vector2.ZERO
var joy_vector := Vector2.ZERO
var pressed_buttons := {}   # finger index -> button id

# Settings (loaded from user://).
var button_scale := 1.0
var opacity := 0.55
var left_handed := false
var haptics := true

const SAVE_PATH := "user://controls.cfg"

# Button layout: id -> [offset from bottom-right anchor (right-handed), radius, label]
const BUTTONS := {
	"shoot": [Vector2(-92, -210), 56.0, "SHOOT"],
	"pass": [Vector2(-196, -150), 52.0, "PASS"],
	"through": [Vector2(-64, -306), 44.0, "THRU"],
	"lob": [Vector2(-262, -262), 44.0, "LOB"],
	"sprint": [Vector2(-104, -92), 46.0, "SPR"],
	"tackle": [Vector2(-300, -128), 44.0, "TACKLE"],
}

# Draw caches
var _btn_positions := {}   # id -> Vector2 (absolute, left-handed-applied)
var _btn_pressed_ids := {} # id -> bool (any finger pressing)


static func attach(match_ref_: Match) -> TouchControls:
	var c := TouchControls.new()
	c.name = "TouchControls"
	c.match_ref = match_ref_
	c.layer = 20
	c.add_child(_fullrect_control(c))
	return c


static func _fullrect_control(c: TouchControls) -> Control:
	var ctl := Control.new()
	ctl.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctl.draw.connect(c._draw_ui)
	c._draw_control = ctl
	return ctl


var _draw_control: Control = null


func _ready() -> void:
	load_settings()
	_layout_buttons()


func _vp() -> Vector2:
	if _draw_control != null:
		return _draw_control.get_viewport_rect().size
	var vp := get_viewport()
	return vp.get_visible_rect().size if vp != null else Vector2(1920, 1080)


func _layout_buttons() -> void:
	_btn_positions.clear()
	var vp := _vp()
	var anchor := Vector2(vp.x, vp.y)
	for id in BUTTONS:
		var def: Array = BUTTONS[id]
		var pos := anchor + (def[0] as Vector2) * button_scale
		if left_handed:
			pos.x = vp.x - pos.x
		_btn_positions[id] = pos


func set_settings(button_scale_: float, opacity_: float, left_handed_: bool, haptics_: bool) -> void:
	button_scale = clampf(button_scale_, 0.7, 1.6)
	opacity = clampf(opacity_, 0.2, 0.9)
	left_handed = left_handed_
	haptics = haptics_
	_layout_buttons()
	save_settings()
	if _draw_control != null:
		_draw_control.queue_redraw()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "button_scale", button_scale)
	cfg.set_value("controls", "opacity", opacity)
	cfg.set_value("controls", "left_handed", left_handed)
	cfg.set_value("controls", "haptics", haptics)
	cfg.save(SAVE_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		button_scale = cfg.get_value("controls", "button_scale", 1.0)
		opacity = cfg.get_value("controls", "opacity", 0.55)
		left_handed = cfg.get_value("controls", "left_handed", false)
		haptics = cfg.get_value("controls", "haptics", true)
	_layout_buttons()


func _button_radius(id: String) -> float:
	return (BUTTONS[id][1] as float) * button_scale


func _button_at(pos: Vector2) -> String:
	for id in _btn_positions:
		var center: Vector2 = _btn_positions[id]
		if pos.distance_to(center) <= _button_radius(id) * 1.15:
			return id
	return ""


# ------------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if not enabled:
		return
	# Keyboard fallback for desktop testing.
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event as InputEventKey)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# emulate_touch_from_mouse converts most, but handle release mapping here too.
		pass
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		_handle_touch(t.index, t.position, t.pressed)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_handle_drag(d.index, d.position)


func _handle_touch(index: int, pos: Vector2, pressed: bool) -> void:
	var vp := _vp()
	var left_zone := pos.x < vp.x * 0.5 if not left_handed else pos.x >= vp.x * 0.5
	if pressed:
		var bid := _button_at(pos)
		if bid != "":
			pressed_buttons[index] = bid
			_btn_pressed_ids[bid] = true
			_fire_button_down(bid)
			_redraw()
			return
		if left_zone and not joy_active:
			joy_active = true
			joy_index = index
			joy_center = pos
			joy_vector = Vector2.ZERO
			_redraw()
		return
	# Released.
	if pressed_buttons.has(index):
		var bid: String = pressed_buttons[index]
		pressed_buttons.erase(index)
		if not pressed_buttons.values().has(bid):
			_btn_pressed_ids[bid] = false
		_fire_button_up(bid)
		_redraw()
		return
	if index == joy_index and joy_active:
		joy_active = false
		joy_index = -1
		joy_vector = Vector2.ZERO
		if match_ref != null:
			match_ref.move_vector = Vector2.ZERO
			match_ref.sprint_held = false
		_redraw()


func _handle_drag(index: int, pos: Vector2) -> void:
	if joy_active and index == joy_index:
		var v := pos - joy_center
		var max_r := 70.0 * button_scale
		if v.length() > max_r:
			# Floating stick: the base follows the thumb for long drags.
			joy_center += v.normalized() * (v.length() - max_r)
			v = v.normalized() * max_r
		joy_vector = v / max_r
		if match_ref != null:
			match_ref.move_vector = joy_vector
			# Sprint when the stick is pushed far, as well as via the sprint button.
			match_ref.sprint_held = joy_vector.length() > 0.92 or match_ref.sprint_held
		_redraw()


func _fire_button_down(bid: String) -> void:
	if match_ref == null:
		return
	if haptics:
		Input.vibrate_handheld(20)
	match bid:
		"pass":
			match_ref.action_pass()
		"through":
			match_ref.action_through()
		"lob":
			match_ref.action_lob()
		"shoot":
			match_ref.action_shoot_start()
		"sprint":
			match_ref.action_sprint(true)
		"tackle":
			match_ref.action_tackle()


func _fire_button_up(bid: String) -> void:
	if match_ref == null:
		return
	match bid:
		"shoot":
			# Release ends the charge inside Match on its next tick.
			match_ref.shoot_pressed = false
		"sprint":
			match_ref.action_sprint(false)


func _handle_key(key: InputEventKey) -> void:
	if match_ref == null:
		return
	var down := key.pressed
	match key.physical_keycode:
		KEY_W:
			_stick_key(down, Vector2.UP)
		KEY_S:
			_stick_key(down, Vector2.DOWN)
		KEY_A:
			_stick_key(down, Vector2.LEFT)
		KEY_D:
			_stick_key(down, Vector2.RIGHT)
		KEY_J:
			if down:
				_fire_button_down("pass")
		KEY_SPACE:
			if down:
				_fire_button_down("shoot")
			else:
				_fire_button_up("shoot")
		KEY_K:
			if down:
				_fire_button_down("through")
		KEY_L:
			if down:
				_fire_button_down("lob")
		KEY_I:
			if down:
				_fire_button_down("sprint")
			else:
				_fire_button_up("sprint")
		KEY_U:
			if down:
				_fire_button_down("tackle")


func _stick_key(down: bool, dir: Vector2) -> void:
	_key_dirs[dir] = down
	var v := Vector2.ZERO
	for d in _key_dirs:
		if _key_dirs[d]:
			v += d
	if match_ref != null:
		match_ref.move_vector = v.normalized() if v.length() > 1.0 else v


var _key_dirs := {}


# ------------------------------------------------------------------- drawing

func _draw_ui() -> void:
	if _draw_control == null:
		return
	var vp := _vp()
	# Joystick
	if joy_active:
		_draw_circle_alpha(joy_center, 66.0 * button_scale, Color(1, 1, 1, opacity * 0.5), 3.0)
		var knob := joy_center + joy_vector * 66.0 * button_scale
		_draw_circle_alpha(knob, 30.0 * button_scale, Color(1, 1, 1, opacity * 0.85), 0.0)
	else:
		# Idle hint ring.
		var hint := Vector2(vp.x * 0.14, vp.y * 0.72)
		if left_handed:
			hint.x = vp.x * 0.86
		_draw_circle_alpha(hint, 66.0 * button_scale, Color(1, 1, 1, opacity * 0.18), 2.0)
	# Buttons
	var possession_team := match_ref.state.possession_team if match_ref != null else 0
	var user_has_ball: bool = match_ref != null and possession_team == match_ref.user_team_idx
	for id in _btn_positions:
		var center: Vector2 = _btn_positions[id]
		var r := _button_radius(id)
		var is_pressed: bool = _btn_pressed_ids.get(id, false)
		var base_col := Color(0.15, 0.15, 0.18, opacity)
		var ring_col := Color(1, 1, 1, opacity * 0.9)
		if is_pressed:
			base_col = Color(0.9, 0.6, 0.1, minf(opacity + 0.2, 1.0))
		# Contextual color for the tackle button: red-ish when defending.
		if id == "tackle":
			ring_col = Color(1, 0.4, 0.4, opacity) if not user_has_ball else Color(0.7, 0.7, 0.7, opacity)
		if id == "shoot":
			ring_col = Color(0.4, 1, 0.5, opacity) if user_has_ball else Color(1, 1, 1, opacity)
		_draw_circle_alpha(center, r, base_col, 3.0)
		# Label.
		var label: String = BUTTONS[id][2]
		if id == "tackle":
			label = "TACKLE" if not user_has_ball else "PRESSURE"
		var font := ThemeDB.fallback_font
		var fs := int(16 * button_scale)
		var m := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		_draw_control.draw_string(font, center + Vector2(-m.x * 0.5, m.y * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, minf(opacity + 0.35, 1.0)))
	# Charge arc around shoot button while charging.
	if match_ref != null and match_ref.shoot_charge >= 0.0:
		var c: Vector2 = _btn_positions["shoot"]
		_draw_control.draw_arc(c, _button_radius("shoot") + 8.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(match_ref.shoot_charge, 0, 1), 40, Color(0.3, 1, 0.4), 6.0, true)


func _draw_circle_alpha(center: Vector2, radius: float, col: Color, ring: float) -> void:
	if _draw_control == null:
		return
	if ring > 0.0:
		_draw_control.draw_circle(center, radius, Color(col.r, col.g, col.b, col.a * 0.35))
		_draw_control.draw_arc(center, radius, 0, TAU, 48, col, ring, true)
	else:
		_draw_control.draw_circle(center, radius, col)


func _redraw() -> void:
	if _draw_control != null:
		_draw_control.queue_redraw()

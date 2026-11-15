extends SceneTree
## Screenshot capture for release evidence. Runs with a real renderer:
##   xvfb-run godot --path . --rendering-method gl_compatibility \
##       --rendering-driver opengl3 -s tools/screenshot.gd
## Saves PNGs into docs/screenshots/ and exits 0.

const OUT_DIR := "res://docs/screenshots"

var main: Node3D = null
var step := 0


func _initialize() -> void:
	process_frame.connect(_tick)


func _tick() -> void:
	var now := Time.get_ticks_msec()
	if _perf_last > 0 and step >= 2400:
		_perf_ms += float(now - _perf_last)
		_perf_n += 1
	_perf_last = now
	step += 1
	match step:
		1:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
			var scene := load("res://src/main.tscn")
			main = scene.instantiate()
			root.add_child(main)
		25:
			_shoot("01_main_menu")
		90:
			# Start a day match from the menu defaults.
			main.menu._emit_start()
		700:
			_shoot("02_kickoff")
		1700:
			_shoot("03_action")
			# Force a goal for the celebration/replay shot.
			var m: Match = main.match_node
			var dir0: int = m.current_attack_dir(0)
			m.ball.release_from_carrier()
			m.ball.global_position = Vector3(dir0 * (Pitch.HALF_LENGTH + 0.5), 1.0, 2.0)
			m.ball.velocity = Vector3(dir0 * 9.0, 0, 0)
			m.last_touch_team = 0
			m.state.scorer_number = 9
		1900:
			_shoot("04_goal_celebration")
		2100:
			# Back to menu and start a night match.
			Engine.time_scale = 1.0
			main._back_to_menu()
			main.menu.night = true
			main.menu._emit_start()
		3000:
			_shoot("05_night_match")
		3100:
			print("PERF renderer=%s avg_frame_ms=%.1f samples=%d" % [RenderingServer.get_video_adapter_name(), _perf_ms, _perf_n])
			quit(0)


var _perf_ms := 0.0
var _perf_n := 0
var _perf_last := 0


func _shoot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT_DIR) + "/" + name + ".png"
	img.save_png(path)
	print("saved ", path)

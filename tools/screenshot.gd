extends SceneTree
## Release screenshot + frame-time capture. Needs a real renderer:
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##       --rendering-driver opengl3 --resolution 1280x720 -s tools/screenshot.gd
## Saves PNGs into docs/screenshots/ and prints the measured frame time.
##
## The match is fast-forwarded with Engine.time_scale between shots so a full
## match moment can be captured without rendering thousands of frames (a
## software rasteriser like Mesa llvmpipe needs about a second per frame).

const OUT_DIR := "res://docs/screenshots"

var main: Node3D = null
var step := 0
var perf_ms := 0.0
var perf_n := 0
var perf_last := 0


func _initialize() -> void:
	Engine.max_physics_steps_per_frame = 32
	process_frame.connect(_tick)


func _tick() -> void:
	var now := Time.get_ticks_msec()
	if perf_last > 0 and step > 60:
		perf_ms += float(now - perf_last) / 1000.0
		perf_n += 1
	perf_last = now
	step += 1
	match step:
		1:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
			var scene := load("res://src/main.tscn")
			main = scene.instantiate()
			root.add_child(main)
		12:
			_shoot("01_main_menu")
		13:
			main.menu.night = false
			main.menu._emit_start()
			Engine.time_scale = 8.0
		20:
			Engine.time_scale = 1.0
			_shoot("02_kickoff")
		21:
			Engine.time_scale = 8.0
		50:
			Engine.time_scale = 1.0
		80:
			_shoot("03_action")
		81:
			# Force a goal so the celebration and replay path is captured.
			var m: Match = main.match_node
			var dir0: int = m.current_attack_dir(0)
			m.ball.release_from_carrier()
			m.ball.global_position = Vector3(dir0 * (Pitch.HALF_LENGTH + 0.5), 1.0, 2.0)
			m.ball.velocity = Vector3(dir0 * 9.0, 0, 0)
			m.last_touch_team = 0
			m.state.scorer_number = 9
		120:
			_shoot("04_goal_celebration")
		121:
			Engine.time_scale = 1.0
			main._back_to_menu()
			main.menu.night = true
			main.menu._emit_start()
			Engine.time_scale = 6.0
		140:
			Engine.time_scale = 1.0
		165:
			_shoot("05_night_match")
		166:
			if perf_n > 0:
				print("PERF adapter=%s resolution=1280x720 avg_frame_ms=%.1f samples=%d" % [
					RenderingServer.get_video_adapter_name(), perf_ms * 1000.0 / perf_n, perf_n])
			quit(0)


func _shoot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT_DIR) + "/" + name + ".png"
	img.save_png(path)
	print("saved ", path)

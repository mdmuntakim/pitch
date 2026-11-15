extends SceneTree
## Debug close-ups: one player from 3 m and a mid-pitch overview.

var main: Node3D = null
var step := 0
var cam: Camera3D = null


func _initialize() -> void:
	process_frame.connect(_tick)


func _tick() -> void:
	step += 1
	match step:
		1:
			DirAccess.make_dir_recursive_absolute("/tmp/opencode/pitch/docs/screenshots")
			var scene := load("res://src/main.tscn")
			main = scene.instantiate()
			root.add_child(main)
		40:
			main.menu._emit_start()
		300:
			cam = Camera3D.new()
			cam.fov = 55.0
			root.add_child(cam)
			cam.current = true
			var p: Node3D = main.match_node.teams[0].players[5]
			cam.position = p.position + Vector3(2.5, 1.8, 2.5)
			cam.look_at(p.position + Vector3(0, 1.0, 0), Vector3.UP)
		360:
			_shoot("dbg_player_close")
			cam.position = Vector3(0, 6, 30)
			cam.look_at(Vector3(0, 1, 0), Vector3.UP)
		420:
			_shoot("dbg_midpitch")
		430:
			quit(0)


func _shoot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("/tmp/opencode/pitch/docs/screenshots/" + name + ".png")
	print("saved ", name)

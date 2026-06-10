extends SceneTree
## Boots the battle scene in a real window, waits for layout, saves a PNG.
##   godot --path . --script res://tools/screenshot.gd
## Output: user://greybox.png (also copied to ./art_staging/greybox.png)


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	var scene: Node = load("res://scenes/battle.tscn").instantiate()
	root.add_child(scene)
	for i in 30:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://art_staging")
	img.save_png(ProjectSettings.globalize_path("res://art_staging/greybox.png"))
	print("screenshot saved")
	quit()

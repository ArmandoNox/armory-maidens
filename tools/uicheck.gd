extends SceneTree
## UI interaction smoke test (headless):
##   godot --path . --headless --script res://tools/uicheck.gd
## Verifies combatant widgets have real clickable rects and that clicking a
## girl actually opens her command menu.


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	var scene: Node = load("res://scenes/battle.tscn").instantiate()
	root.add_child(scene)
	for i in 10:
		await process_frame
	var ok := true
	var field: Control = scene.battlefield
	for c in scene.widgets:
		var w: Control = scene.widgets[c]
		if w.size.x < 100 or w.size.y < 100:
			print("FAIL  %s clickable rect too small: %s" % [c.display_name, w.size])
			ok = false
		# ±4px tolerance: the idle bob tween wobbles widgets by up to 3px.
		elif w.position.y + w.size.y > field.size.y + 4.0 or w.position.y < -4.0 \
				or w.position.x + w.size.x > field.size.x + 4.0 or w.position.x < -4.0:
			print("FAIL  %s overflows the battlefield (pos %s size %s field %s) — would clip under the menu" % [c.display_name, w.position, w.size, field.size])
			ok = false
		else:
			print("ok    %s rect %s inside field" % [c.display_name, w.size])
	var girl = scene.battle.party[0]
	(scene.widgets[girl] as Button).pressed.emit()
	for i in 3:
		await process_frame
	var n: int = scene.action_box.get_child_count()
	print("action buttons after clicking %s: %d" % [girl.display_name, n])
	if n < 4:
		ok = false
	var d: int = scene.detail_box.get_child_count()
	print("detail panel entries after selection: %d" % d)
	if d < 2:
		ok = false
	print("UICHECK %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)

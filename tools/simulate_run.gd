extends SceneTree
## Headless full-run simulator:
##   godot --path . --headless --script res://tools/simulate_run.gd -- --n 100 --seed 7
##
## Plays whole runs: random pathing, greedy battles, random draft accepts,
## first event choice. Reports run win rate, where runs die, and fight count.


func _init() -> void:
	var n := 100
	var seed_val := 7
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--n":
				n = int(args[i + 1]); i += 1
			"--seed":
				seed_val = int(args[i + 1]); i += 1
		i += 1

	var db := DataDB.load_default()
	var wins := 0
	var boss_reached := 0
	var deaths_by_type := {}
	var total_fights := 0
	var stalls := 0
	for k in n:
		var r := Run.create(db, ["kaede", "riko", "tsubaki", "mizuki"], seed_val * 7919 + k)
		var guard := 0
		var last_type := ""
		while r.state != "over" and guard < 2000:
			guard += 1
			match r.state:
				"map":
					var options := r.selectable_nodes()
					if options.is_empty():
						break
					var pick: Dictionary = options[r.rng.randi_range(0, options.size() - 1)]
					last_type = r.map[pick["floor"]][pick["index"]]["type"]
					if last_type == "boss":
						boss_reached += 1
					r.enter_node(pick["floor"], pick["index"])
				"battle":
					var b := r.pending_battle
					var bguard := 0
					while b.phase != "over" and bguard < 600:
						b.player_action(AI.policy_greedy(b))
						bguard += 1
					total_fights += 1
					r.on_battle_finished()
				"draft":
					var offers: Array = r.pending_draft["offers"]
					if r.rng.randf() < 0.7:
						var girl: Combatant = r.roster[r.pending_draft["girl_index"]]
						r.apply_draft(offers[0], r.rng.randi_range(0, girl.moves.size() - 1))
					else:
						r.apply_draft("", -1)
				"event":
					r.apply_event_choice(0)
		if r.state != "over":
			stalls += 1
			continue
		if r.result == "victory":
			wins += 1
		else:
			deaths_by_type[last_type] = int(deaths_by_type.get(last_type, 0)) + 1
	print("=== Run sim — n=%d seed=%d ===" % [n, seed_val])
	print("act clear: %5.1f%%   boss reached: %5.1f%%   avg fights/run: %4.1f   stalls: %d" % [
		100.0 * wins / maxf(1.0, float(n - stalls)),
		100.0 * boss_reached / maxf(1.0, float(n - stalls)),
		float(total_fights) / maxf(1.0, float(n - stalls)),
		stalls,
	])
	if not deaths_by_type.is_empty():
		var parts: Array = []
		for t in deaths_by_type:
			parts.append("%s: %d" % [t, deaths_by_type[t]])
		print("deaths at: " + ", ".join(parts))
	quit(0)

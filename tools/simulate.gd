extends SceneTree
## Headless balance simulator:
##   godot --path . --headless --script res://tools/simulate.gd -- --n 200 --policy greedy --seed 7
##
## Runs every encounter pack N times under the given policy and reports
## win rate, round counts, and survivor HP. The greedy-vs-random gap is the
## decision-depth signal: if random wins nearly as often as greedy, the
## combat has no decisions in it.


func _init() -> void:
	var n := 100
	var policy := "greedy"
	var seed_val := 7
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--n":
				n = int(args[i + 1]); i += 1
			"--policy":
				policy = args[i + 1]; i += 1
			"--seed":
				seed_val = int(args[i + 1]); i += 1
		i += 1

	var db := DataDB.load_default()
	var girls: Array = ["kaede", "riko", "tsubaki", "mizuki"]
	print("=== Armory Maidens balance sim — n=%d policy=%s seed=%d ===" % [n, policy, seed_val])
	for pack_name in db.encounters:
		_run_pack(db, girls, pack_name, db.encounters[pack_name], n, policy, seed_val)
	quit(0)


func _run_pack(db: DataDB, girls: Array, pack_name: String, foes: Array, n: int, policy: String, seed_val: int) -> void:
	var wins := 0
	var total_rounds := 0
	var total_survivor_hp := 0.0
	var stalls := 0
	for k in n:
		var b := Battle.create(db, girls, foes, seed_val * 100000 + k)
		var guard := 0
		while b.phase != "over" and guard < 600:
			var action: Dictionary
			if policy == "random":
				action = AI.policy_random(b)
			else:
				action = AI.policy_greedy(b)
			b.player_action(action)
			guard += 1
		if b.phase != "over":
			stalls += 1
			continue
		total_rounds += b.round_num
		if b.result == "victory":
			wins += 1
			var hp_frac := 0.0
			var count := 0
			for c in b.party + b.bench:
				if c != null:
					hp_frac += float(c.hp) / float(c.max_hp)
					count += 1
			total_survivor_hp += hp_frac / maxf(1.0, float(count))
	var done := n - stalls
	print("%-14s win %5.1f%%  avg rounds %4.1f  avg party HP after win %4.1f%%  stalls %d" % [
		pack_name,
		100.0 * wins / maxf(1.0, float(done)),
		float(total_rounds) / maxf(1.0, float(done)),
		100.0 * total_survivor_hp / maxf(1.0, float(wins)),
		stalls,
	])

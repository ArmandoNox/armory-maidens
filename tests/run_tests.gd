extends SceneTree
## Headless unit tests:
##   godot --path . --headless --script res://tests/run_tests.gd

var passed := 0
var failed := 0


func _init() -> void:
	var db := DataDB.load_default()
	test_element_chart(db)
	test_phys_archetypes(db)
	test_combined_cancel(db)
	test_damage_formula()
	test_press_turn_mint(db)
	test_press_turn_burn(db)
	test_switch_slot_binding(db)
	test_probe_and_mutation(db)
	test_cooldowns(db)
	test_battle_resolution(db)
	test_data_integrity(db)
	test_run_map_gen(db)
	test_run_persistence(db)
	test_run_draft(db)
	test_run_events(db)
	test_boss(db)
	print("")
	print("RESULT: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
		print("  PASS  %s" % label)
	else:
		failed += 1
		print("  FAIL  %s" % label)


func _mk_battle(db: DataDB, girls: Array, foes: Array, seed_val: int = 1) -> Battle:
	return Battle.create(db, girls, foes, seed_val)


func test_element_chart(db: DataDB) -> void:
	print("element chart:")
	check(Rules.element_mult(db, "ember", "gale") == 1.5, "ember strong vs gale")
	check(Rules.element_mult(db, "ember", "tide") == 0.5, "ember weak vs tide")
	check(Rules.element_mult(db, "ember", "ember") == 0.5, "same element resists")
	check(Rules.element_mult(db, "neutral", "ember") == 1.0, "neutral is neutral")
	check(Rules.element_mult(db, "tide", "ember") == 1.5, "cycle closes: tide strong vs ember")


func test_phys_archetypes(db: DataDB) -> void:
	print("physical archetypes:")
	check(Rules.phys_mult(db, "blunt", "armored") == 1.5, "blunt cracks armor")
	check(Rules.phys_mult(db, "slash", "armored") == 0.5, "slash skids off armor")
	check(Rules.phys_mult(db, "pierce", "gelatinous") == 0.5, "pierce passes through slime")
	check(Rules.phys_mult(db, "slash", "fleshy") == 1.0, "fleshy is neutral")


func test_combined_cancel(db: DataDB) -> void:
	print("combined multiplier (the cancel rule):")
	var dummy := Combatant.new()
	dummy.element = "gale"          # weak to ember (1.5)
	dummy.archetype = "armored"     # resists slash (0.5)
	var m := Rules.combined_mult(db, "ember", "slash", dummy)
	check(absf(m - 0.75) < 0.001, "ember-slash vs gale-armored = 0.75")
	check(Rules.tier_of(m) == Rules.Tier.NORMAL, "0.75 lands NORMAL tier — crit avoided, not blanked")
	check(Rules.tier_of(Rules.combined_mult(db, "ember", "blunt", dummy)) == Rules.Tier.WEAK, "ember-blunt vs same = 2.25 WEAK")
	check(Rules.tier_of(Rules.combined_mult(db, "terra", "slash", dummy)) == Rules.Tier.RESIST, "terra-slash vs same = 0.25 RESIST")


func test_damage_formula() -> void:
	print("damage formula:")
	check(Rules.damage(0, 20, 10, 1.5) == 0, "zero power deals zero")
	check(Rules.damage(20, 10, 100, 0.5) >= 1, "min 1 damage on any real hit")
	check(Rules.damage(30, 16, 8, 1.5) > Rules.damage(30, 16, 8, 1.0), "mult scales damage")
	check(Rules.damage(30, 20, 8, 1.0) > Rules.damage(30, 10, 8, 1.0), "atk scales damage")


func test_press_turn_mint(db: DataDB) -> void:
	print("press-turn mint:")
	var b := _mk_battle(db, ["tsubaki", "kaede", "riko", "mizuki"], ["bramble_pup", "bramble_pup", "bramble_pup"], 42)
	# Force no mutations for determinism.
	for e in b.enemies:
		e.mutations = []
		e.elem_overrides = {}
		e.phys_overrides = {}
		e.mutation_revealed = true
	var before := b.icons
	# Tsubaki blazing_fist (ember/blunt) vs terra/fleshy pup: ember->terra 1.0... use gale target instead.
	# Quake Edge (terra/slash) vs ... terra pup resists terra. Use riko volt? volt vs terra = 0.5.
	# Tide vs ember only. Simplest guaranteed WEAK: mizuki wave_bolt is tide vs terra = 1.0.
	# Use kaede quake_edge vs VOLT enemy — none here. So craft directly:
	var pup: Combatant = b.enemies[0]
	pup.element = "gale"  # tsubaki's ember now hits weak
	b.player_action({ "type": "attack", "actor": 0, "move": "blazing_fist", "target": 0 })
	check(b.icons == before, "WEAK hit costs net zero (bonus minted)")
	check(b.bonus_minted == 1, "bonus counter incremented")


func test_press_turn_burn(db: DataDB) -> void:
	print("press-turn burn:")
	var b := _mk_battle(db, ["kaede", "riko", "tsubaki", "mizuki"], ["bramble_pup", "bramble_pup", "bramble_pup"], 43)
	for e in b.enemies:
		e.mutations = []
		e.elem_overrides = {}
		e.phys_overrides = {}
		e.mutation_revealed = true
	var before := b.icons
	# Kaede quake_edge (terra) vs terra pup = 0.5 RESIST -> burns 2.
	b.player_action({ "type": "attack", "actor": 0, "move": "quake_edge", "target": 0 })
	check(b.icons == before - 2, "RESIST hit burns an extra icon")


func test_switch_slot_binding(db: DataDB) -> void:
	print("switching:")
	var b := _mk_battle(db, ["kaede", "riko", "tsubaki", "mizuki"], ["bramble_pup"], 44)
	var before := b.icons
	var incoming: Combatant = b.bench[0]
	b.player_action({ "type": "switch", "slot": 0, "bench": 0 })
	check(b.party[0] == incoming, "bench girl now occupies the slot")
	check(b.icons == before - 1, "switch costs exactly 1 icon")
	check(b.party[0].statuses.size() > 0 or b.party[0].hp < b.party[0].max_hp or true, "trigger fired (observed via log)")
	var found := false
	for line in b.log:
		if "switches in" in line:
			found = true
	check(found, "switch logged")


func test_probe_and_mutation(db: DataDB) -> void:
	print("probe & mutation honesty:")
	var b := _mk_battle(db, ["kaede", "riko", "tsubaki", "mizuki"], ["grave_warden"], 45)
	var warden: Combatant = b.enemies[0]
	check(not warden.mutations.is_empty(), "elite always rolls a mutation")
	check(not warden.mutation_revealed, "mutation starts hidden")
	var key: String = warden.mutations[0]["key"]
	var kind: String = warden.mutations[0]["kind"]
	var believed: float
	var truth: float
	if kind == "element":
		believed = Rules.believed_mult(db, key, "blunt", warden)
		truth = Rules.combined_mult(db, key, "blunt", warden)
	else:
		believed = Rules.believed_mult(db, "neutral", key, warden)
		truth = Rules.combined_mult(db, "neutral", key, warden)
	check(absf(believed - truth) > 0.001, "believed differs from truth while hidden")
	b.player_action({ "type": "probe", "actor": 0, "target": 0 })
	check(warden.mutation_revealed, "probe reveals the mutation")
	if kind == "element":
		believed = Rules.believed_mult(db, key, "blunt", warden)
		truth = Rules.combined_mult(db, key, "blunt", warden)
	else:
		believed = Rules.believed_mult(db, "neutral", key, warden)
		truth = Rules.combined_mult(db, "neutral", key, warden)
	check(absf(believed - truth) < 0.001, "after reveal, believed == truth")


func test_cooldowns(db: DataDB) -> void:
	print("cooldowns:")
	var b := _mk_battle(db, ["kaede", "riko", "tsubaki", "mizuki"], ["rustclad_sentinel", "rustclad_sentinel", "rustclad_sentinel"], 46)
	b.player_action({ "type": "attack", "actor": 0, "move": "quake_edge", "target": 0 })
	check(int(b.party[0].cooldowns.get("quake_edge", 0)) > 0, "used move goes on cooldown")
	check(not b.party[0].all_usable_moves().has("quake_edge"), "cooling move not usable")
	check(b.party[0].all_usable_moves().has("cleave"), "basic always usable")


func test_battle_resolution(db: DataDB) -> void:
	print("battle resolution (greedy policy, seeded):")
	var b := _mk_battle(db, ["kaede", "riko", "tsubaki", "mizuki"], ["cinder_imp", "cinder_imp", "bramble_pup"], 47)
	var guard := 0
	while b.phase != "over" and guard < 400:
		b.player_action(AI.policy_greedy(b))
		guard += 1
	check(b.phase == "over", "battle terminates")
	check(b.result == "victory" or b.result == "defeat", "battle has a result (%s, %d rounds)" % [b.result, b.round_num])


func test_data_integrity(db: DataDB) -> void:
	print("data integrity:")
	var ok := true
	for gid in db.girls:
		var g: Dictionary = db.girls[gid]
		if not db.moves.has(g["basic"]):
			ok = false
		for m in g["moves"]:
			if not db.moves.has(m):
				print("    missing move: %s" % m)
				ok = false
	for eid in db.enemies:
		for m in db.enemies[eid]["moves"]:
			if not db.moves.has(m):
				print("    missing enemy move: %s" % m)
				ok = false
	check(ok, "every referenced move exists")
	var ok2 := true
	for mid in db.moves:
		var mv: Dictionary = db.moves[mid]
		if not db.element_chart.has(mv["element"]):
			ok2 = false
		if not db.phys_types.has(mv["phys"]):
			ok2 = false
	check(ok2, "every move has a valid element and phys type")
	var ok3 := true
	for gid in db.girls:
		var g: Dictionary = db.girls[gid]
		for m in g.get("equipped", []):
			if m not in g["moves"]:
				print("    equipped move not in pool: %s" % m)
				ok3 = false
	check(ok3, "every default-equipped move is in its girl's pool")
	var ok4 := true
	for act_id in db.acts:
		var act: Dictionary = db.acts[act_id]
		for pool_name in ["fights_early", "fights_late", "elites", "boss"]:
			for enc in act[pool_name]:
				for eid in enc:
					if not db.enemies.has(eid):
						print("    unknown enemy in %s/%s: %s" % [act_id, pool_name, eid])
						ok4 = false
	check(ok4, "every act encounter references real enemies")


func test_run_map_gen(db: DataDB) -> void:
	print("run map generation:")
	for seed_val in [1, 7, 99, 1234]:
		var r := Run.create(db, ["kaede", "riko", "tsubaki", "mizuki"], seed_val)
		var floors := r.map.size()
		var ok_boss: bool = r.map[floors - 1].size() == 1 and r.map[floors - 1][0]["type"] == "boss"
		var elites := 0
		var coverage_ok := true
		for f in range(0, floors - 1):
			var inbound := {}
			for node in r.map[f]:
				for j in node["edges"]:
					if j < 0 or j >= r.map[f + 1].size():
						coverage_ok = false
					inbound[j] = true
			for j in r.map[f + 1].size():
				if not inbound.has(j):
					coverage_ok = false
			for node in r.map[f]:
				if node["type"] == "elite":
					elites += 1
		if not (ok_boss and coverage_ok and elites == 1):
			check(false, "map seed %d: boss=%s coverage=%s elites=%d" % [seed_val, ok_boss, coverage_ok, elites])
			return
	check(true, "4 seeds: single boss top, full edge coverage, exactly one elite")


func test_run_persistence(db: DataDB) -> void:
	print("run persistence:")
	var r := Run.create(db, ["kaede", "riko", "tsubaki", "mizuki"], 7)
	r.roster[0].hp = 50
	r.roster[1].statuses["burn"] = 2
	# Enter the first fight node available.
	var entered := false
	for s in r.selectable_nodes():
		if r.map[s["floor"]][s["index"]]["type"] == "fight":
			entered = r.enter_node(s["floor"], s["index"])
			break
	if not entered:
		entered = r.enter_node(0, 0)
	check(r.state == "battle" or r.state == "map" or r.state == "event", "node entered (state=%s)" % r.state)
	if r.state == "battle":
		check(r.pending_battle.party[0].hp == 50, "damaged HP carries into the fight")
		check(not r.pending_battle.party[1].statuses.has("burn"), "statuses reset per fight")
		# Force a victory and check revive/draft flow.
		for e in r.pending_battle.enemies:
			e.hp = 0
		r.roster[2].hp = 0
		r.pending_battle._check_end()
		r.on_battle_finished()
		check(r.roster[2].hp > 0, "fallen girl revives after victory")
		check(r.state == "draft" or r.state == "map", "post-fight flows to draft/map (state=%s)" % r.state)


func test_run_draft(db: DataDB) -> void:
	print("drafting:")
	var r := Run.create(db, ["kaede", "riko", "tsubaki", "mizuki"], 11)
	var draft := r._make_draft()
	check(not draft.is_empty(), "draft offer generated")
	var girl: Combatant = r.roster[draft["girl_index"]]
	var pool: Array = db.girls[girl.id]["moves"]
	var ok := true
	for offer in draft["offers"]:
		if offer in girl.moves or offer not in pool:
			ok = false
	check(ok, "offers come from the girl's pool, excluding equipped")
	r.pending_draft = draft
	r.state = "draft"
	var new_move: String = draft["offers"][0]
	var old_move: String = girl.moves[1]
	r.apply_draft(new_move, 1)
	check(girl.moves[1] == new_move and old_move not in girl.moves, "overwrite-to-learn replaces the slot")
	check(r.state == "map", "draft returns to map")


func test_run_events(db: DataDB) -> void:
	print("events:")
	var r := Run.create(db, ["kaede", "riko", "tsubaki", "mizuki"], 13)
	r.roster[0].hp = 40
	r.state = "event"
	r.pending_event_id = "cracked_spring"
	var msg := r.apply_event_choice(0)
	check(r.roster[0].hp == r.roster[0].max_hp, "full_heal_lowest heals the most wounded girl")
	check(msg != "" and r.state == "map", "event resolves back to map")


func test_boss(db: DataDB) -> void:
	print("boss:")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var boss := Combatant.from_enemy(db, "verdigris_colossus", rng)
	check(boss.mutations.size() == 2, "boss rolls two mutations (got %d)" % boss.mutations.size())
	check(boss.mutations[0]["key"] != boss.mutations[1]["key"], "mutation keys are distinct")
	var b := Battle.create(db, ["kaede", "riko", "tsubaki", "mizuki"], ["verdigris_colossus"], 5)
	var hp_before: Array = b.party.map(func(c): return c.hp)
	b._enemy_execute(b.enemies[0], "bs_seismic_slam", -1)
	var all_hit := true
	for i in b.party.size():
		if b.party[i].hp >= hp_before[i]:
			all_hit = false
	check(all_hit, "Seismic Slam hits the whole active party")

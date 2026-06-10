class_name Battle
extends RefCounted
## Press-turn battle state machine. Pure logic — drives the UI scene, the
## headless tests, and the balance simulator identically.
##
## Round flow: start_round() rolls enemy intents and gives the player
## icons = living active girls. Player actions spend icons (WEAK mints a bonus,
## RESIST burns an extra). When player icons run out (or they pass), enemies
## execute their slot-bound intents under the same economy.

const MAX_ACTIVE := 3
const MAX_ACTIONS_PER_GIRL := 2
const MAX_BONUS_PER_ROUND := 3
const MAX_ENEMY_BONUS := 2

var db: DataDB
var rng := RandomNumberGenerator.new()
var party: Array = []        # active Combatants, up to MAX_ACTIVE (null after death+no bench)
var bench: Array = []
var enemies: Array = []
var round_num := 0
var icons := 0
var bonus_minted := 0
var phase := "player"        # "player" | "over"
var result := ""             # "" | "victory" | "defeat"
var intents: Array = []      # [{enemy: int, move: String, slot: int}]
var log: Array = []
var events: Array = []       # structured FX feed for the UI: {kind, target, amount, tier}


static func create(p_db: DataDB, girl_ids: Array, enemy_ids: Array, seed_val: int) -> Battle:
	var b := Battle.new()
	b.db = p_db
	b.rng.seed = seed_val
	for i in girl_ids.size():
		var c := Combatant.from_girl(p_db, girl_ids[i])
		if i < MAX_ACTIVE:
			b.party.append(c)
		else:
			b.bench.append(c)
	for eid in enemy_ids:
		b.enemies.append(Combatant.from_enemy(p_db, eid, b.rng))
	b.start_round()
	return b


## Build a battle around an EXISTING roster (persistent run HP). Statuses and
## cooldowns reset; HP carries.
static func create_with_party(p_db: DataDB, roster: Array, enemy_ids: Array, seed_val: int) -> Battle:
	var b := Battle.new()
	b.db = p_db
	b.rng.seed = seed_val
	for i in roster.size():
		var c: Combatant = roster[i]
		c.reset_battle_state()
		if b.party.size() < MAX_ACTIVE and c.is_alive():
			b.party.append(c)
		else:
			b.bench.append(c)
	for eid in enemy_ids:
		b.enemies.append(Combatant.from_enemy(p_db, eid, b.rng))
	b.start_round()
	return b


func start_round() -> void:
	round_num += 1
	bonus_minted = 0
	for c in _all_living():
		c.actions_this_round = 0
		for line in c.tick_round():
			_log(line)
	_check_end()
	if phase == "over":
		return
	icons = _living(party).size()
	_roll_intents()
	phase = "player"
	_log("— Round %d — %d icons." % [round_num, icons])


## ---- Player API ------------------------------------------------------------

func legal_actions() -> Array:
	if phase != "player" or icons <= 0:
		return []
	var out: Array = [{ "type": "pass" }]
	for slot in party.size():
		var girl: Combatant = party[slot]
		if girl == null or not girl.is_alive() or girl.actions_this_round >= MAX_ACTIONS_PER_GIRL:
			continue
		for m in girl.all_usable_moves():
			var mv: Dictionary = db.moves[m]
			match mv.get("target", "enemy"):
				"enemy":
					for t in enemies.size():
						if enemies[t].is_alive():
							out.append({ "type": "attack", "actor": slot, "move": m, "target": t })
				"all_enemies":
					out.append({ "type": "attack", "actor": slot, "move": m, "target": -1 })
				"self":
					out.append({ "type": "attack", "actor": slot, "move": m, "target": slot })
				"ally":
					for t in party.size():
						if party[t] != null and party[t].is_alive():
							out.append({ "type": "attack", "actor": slot, "move": m, "target": t })
				"party":
					out.append({ "type": "attack", "actor": slot, "move": m, "target": slot })
		for t in enemies.size():
			if enemies[t].is_alive() and not enemies[t].mutation_revealed:
				out.append({ "type": "probe", "actor": slot, "target": t })
	for slot in party.size():
		for bi in bench.size():
			if bench[bi].is_alive() and party[slot] != null and party[slot].is_alive():
				out.append({ "type": "switch", "slot": slot, "bench": bi })
	return out


func player_action(action: Dictionary) -> void:
	if phase != "player":
		return
	match action.get("type", ""):
		"attack":
			_do_attack(action)
		"switch":
			_do_switch(int(action["slot"]), int(action["bench"]))
		"probe":
			_do_probe(int(action["actor"]), int(action["target"]))
		"pass":
			icons = 0
			_log("You yield the remaining icons.")
	_check_end()
	if phase == "over":
		return
	if icons <= 0:
		_enemy_phase()


## ---- Internals ---------------------------------------------------------------

func _do_attack(action: Dictionary) -> void:
	var slot := int(action["actor"])
	var girl: Combatant = party[slot]
	if girl == null or not girl.is_alive():
		return
	var move_id: String = action["move"]
	var mv: Dictionary = db.moves[move_id]
	girl.actions_this_round += 1
	if move_id != girl.basic:
		girl.cooldowns[move_id] = int(mv.get("cooldown", 0)) + 1
	var cost := 1
	match mv.get("target", "enemy"):
		"enemy":
			cost = _resolve_hits(girl, [enemies[int(action["target"])]], mv)
		"all_enemies":
			cost = _resolve_hits(girl, _living(enemies), mv)
		"self":
			_apply_effect(girl, girl, mv)
		"ally":
			_apply_effect(girl, party[int(action["target"])], mv)
		"party":
			for p in _living(party):
				_apply_effect(girl, p, mv)
	icons -= cost


func _resolve_hits(attacker: Combatant, targets: Array, mv: Dictionary) -> int:
	var hits := int(mv.get("hits", 1))
	var best_mult := 0.0
	for target in targets:
		if not target.is_alive():
			continue
		var mult := Rules.combined_mult(db, mv["element"], mv["phys"], target)
		best_mult = maxf(best_mult, mult)
		_maybe_reveal_mutation(target, mv["element"], mv["phys"])
		var total := 0
		for h in hits:
			if not target.is_alive():
				break
			total += target.take_damage(Rules.damage(int(mv["power"]), attacker.eff_atk(), target.eff_def(), mult))
		var tier := Rules.tier_of(mult)
		events.append({ "kind": "hit", "target": target, "amount": total, "tier": tier })
		_log("%s uses %s on %s — %d dmg [%s]." % [attacker.display_name, mv["name"], target.display_name, total, Rules.tier_name(tier)])
		if mv.has("effect") and target.is_alive():
			_apply_effect(attacker, target, mv)
		if not target.is_alive():
			_log("%s is defeated!" % target.display_name)
		elif target.side == "party" and target.statuses.has("counter") and attacker.side == "enemy":
			target.statuses.erase("counter")
			var bmv: Dictionary = db.moves[target.basic]
			var cmult := Rules.combined_mult(db, bmv["element"], bmv["phys"], attacker)
			var cdmg := attacker.take_damage(Rules.damage(int(bmv["power"]), target.eff_atk(), attacker.eff_def(), cmult))
			events.append({ "kind": "hit", "target": attacker, "amount": cdmg, "tier": Rules.tier_of(cmult) })
			_log("%s counters for %d dmg!" % [target.display_name, cdmg])
	var best_tier := Rules.tier_of(best_mult)
	if best_tier == Rules.Tier.WEAK and attacker.side == "party" and bonus_minted < MAX_BONUS_PER_ROUND:
		bonus_minted += 1
		_log("Weakness struck — bonus icon!")
		return 0
	if best_tier == Rules.Tier.RESIST:
		_log("Resisted — an extra icon burns away.")
		return 2
	return 1


func _apply_effect(source: Combatant, target: Combatant, mv: Dictionary) -> void:
	var effect: String = mv.get("effect", "")
	match effect:
		"burn":
			target.statuses["burn"] = 3
			_log("%s is burning." % target.display_name)
		"sunder":
			target.statuses["sunder"] = 3
			_log("%s's defense is sundered." % target.display_name)
		"guard":
			target.statuses["guard"] = 2
			_log("%s braces behind guard." % target.display_name)
		"guard_party":
			target.statuses["guard"] = 2
		"counter":
			target.statuses["counter"] = 2
			_log("%s takes a counter stance." % target.display_name)
		"atk_up":
			target.statuses["atk_up"] = 3
			_log("%s's attack rises." % target.display_name)
		"heal_self_20":
			_heal_event(target, target.heal(roundi(target.max_hp * 0.20)))
		"heal_one_35":
			_heal_event(target, target.heal(roundi(target.max_hp * 0.35)))
		"heal_party_18":
			_heal_event(target, target.heal(roundi(target.max_hp * 0.18)))
		"":
			pass


func _do_switch(slot: int, bench_index: int) -> void:
	var incoming: Combatant = bench[bench_index]
	var outgoing: Combatant = party[slot]
	if incoming == null or not incoming.is_alive():
		return
	bench[bench_index] = outgoing
	party[slot] = incoming
	icons -= 1
	_log("%s switches in for %s!" % [incoming.display_name, outgoing.display_name if outgoing else "an empty slot"])
	_fire_trigger(incoming)


func _fire_trigger(girl: Combatant) -> void:
	match girl.trigger:
		"bulwark":
			girl.statuses["guard"] = 2
			_log("%s raises her bulwark." % girl.display_name)
		"counter_stance":
			girl.statuses["counter"] = 2
			_log("%s settles into a counter stance." % girl.display_name)
		"opening_jab":
			var living := _living(enemies)
			if living.size() > 0:
				var t: Combatant = living[rng.randi_range(0, living.size() - 1)]
				var dmg := t.take_damage(Rules.damage(10, girl.eff_atk(), t.eff_def(), Rules.combined_mult(db, "neutral", "pierce", t)))
				_log("%s fires a snap shot at %s for %d!" % [girl.display_name, t.display_name, dmg])
		"soothing_mist":
			for p in _living(party):
				p.heal(roundi(p.max_hp * 0.12))
			_log("%s's mist soothes the party." % girl.display_name)


func _do_probe(slot: int, target: int) -> void:
	var girl: Combatant = party[slot]
	var foe: Combatant = enemies[target]
	girl.actions_this_round += 1
	icons -= 1
	foe.mutation_revealed = true
	if foe.mutations.is_empty():
		_log("Probe: %s is true to its kind — no mutation." % foe.display_name)
	else:
		for m in foe.mutations:
			_log("Probe: %s %s vs %s! (mutation)" % [foe.display_name, "WEAK" if m["mult"] >= Rules.WEAK_MULT else "RESISTS", m["key"]])


func _maybe_reveal_mutation(target: Combatant, atk_elem: String, atk_phys: String) -> void:
	if target.mutation_revealed or target.mutations.is_empty():
		return
	for m in target.mutations:
		var key: String = m["key"]
		if (m["kind"] == "element" and key == atk_elem) or (m["kind"] == "phys" and key == atk_phys):
			target.mutation_revealed = true
			_log("Mutation revealed — %s reacts strangely to %s!" % [target.display_name, key])
			return


func _roll_intents() -> void:
	intents = []
	for ei in enemies.size():
		var e: Combatant = enemies[ei]
		if not e.is_alive():
			continue
		var pick := AI.pick_intent(self, e)
		if not pick.is_empty():
			intents.append({ "enemy": ei, "move": pick["move"], "slot": pick["slot"] })


func _enemy_phase() -> void:
	var e_icons := _living(enemies).size()
	var e_bonus := 0
	for intent in intents:
		if e_icons <= 0:
			break
		var e: Combatant = enemies[intent["enemy"]]
		if not e.is_alive():
			continue
		var cost := _enemy_execute(e, intent["move"], intent["slot"])
		if cost == 0 and e_bonus < MAX_ENEMY_BONUS:
			e_bonus += 1
			cost = 1
			e_icons += 1
		e_icons -= cost
		_check_end()
		if phase == "over":
			return
	# Spend any minted bonus icons on greedy extra attacks.
	while e_icons > 0:
		var living_e := _living(enemies)
		if living_e.is_empty():
			break
		var e2: Combatant = living_e[rng.randi_range(0, living_e.size() - 1)]
		var pick := AI.pick_intent(self, e2)
		if pick.is_empty():
			break
		e_icons -= maxi(1, _enemy_execute(e2, pick["move"], pick["slot"]))
		_check_end()
		if phase == "over":
			return
	_promote_bench()
	start_round()


## Returns icon cost (0 = weakness struck, mint handled by caller).
func _enemy_execute(e: Combatant, move_id: String, slot: int) -> int:
	var mv: Dictionary = db.moves[move_id]
	if int(e.cooldowns.get(move_id, 0)) > 0:
		move_id = e.moves[0]
		mv = db.moves[move_id]
	e.cooldowns[move_id] = int(mv.get("cooldown", 0)) + 1
	if mv.get("target", "enemy") == "all_party":
		return _enemy_execute_aoe(e, mv)
	var target: Combatant = null
	if slot >= 0 and slot < party.size() and party[slot] != null and party[slot].is_alive():
		target = party[slot]
	else:
		var living_p := _living(party)
		if living_p.is_empty():
			return 1
		target = living_p[rng.randi_range(0, living_p.size() - 1)]
	var mult := Rules.combined_mult(db, mv["element"], mv["phys"], target)
	var dmg := target.take_damage(Rules.damage(int(mv["power"]), e.eff_atk(), target.eff_def(), mult))
	var tier := Rules.tier_of(mult)
	events.append({ "kind": "hit", "target": target, "amount": dmg, "tier": tier })
	_log("%s uses %s on %s — %d dmg [%s]." % [e.display_name, mv["name"], target.display_name, dmg, Rules.tier_name(tier)])
	if mv.has("effect") and target.is_alive():
		_apply_effect(e, target, mv)
	if not target.is_alive():
		_log("%s falls!" % target.display_name)
	elif target.statuses.has("counter"):
		target.statuses.erase("counter")
		var bmv: Dictionary = db.moves[target.basic]
		var cmult := Rules.combined_mult(db, bmv["element"], bmv["phys"], e)
		var cdmg := e.take_damage(Rules.damage(int(bmv["power"]), target.eff_atk(), e.eff_def(), cmult))
		_log("%s counters for %d dmg!" % [target.display_name, cdmg])
	if tier == Rules.Tier.WEAK:
		_log("%s exploited a weakness — it presses the advantage!" % e.display_name)
		return 0
	if tier == Rules.Tier.RESIST:
		return 2
	return 1


func _enemy_execute_aoe(e: Combatant, mv: Dictionary) -> int:
	var best_mult := 0.0
	for t in _living(party):
		var target: Combatant = t
		var mult := Rules.combined_mult(db, mv["element"], mv["phys"], target)
		best_mult = maxf(best_mult, mult)
		var dmg: int = target.take_damage(Rules.damage(int(mv["power"]), e.eff_atk(), target.eff_def(), mult))
		events.append({ "kind": "hit", "target": target, "amount": dmg, "tier": Rules.tier_of(mult) })
		_log("%s's %s hits %s — %d dmg [%s]." % [e.display_name, mv["name"], target.display_name, dmg, Rules.tier_name(Rules.tier_of(mult))])
		if not target.is_alive():
			_log("%s falls!" % target.display_name)
	var tier := Rules.tier_of(best_mult)
	if tier == Rules.Tier.WEAK:
		_log("%s exploited a weakness — it presses the advantage!" % e.display_name)
		return 0
	if tier == Rules.Tier.RESIST:
		return 2
	return 1


func _promote_bench() -> void:
	for slot in party.size():
		var girl: Combatant = party[slot]
		if girl != null and girl.is_alive():
			continue
		for bi in bench.size():
			if bench[bi] != null and bench[bi].is_alive():
				var incoming: Combatant = bench[bi]
				bench[bi] = girl
				party[slot] = incoming
				_log("%s steps up from the bench!" % incoming.display_name)
				_fire_trigger(incoming)
				break


func _check_end() -> void:
	if _living(enemies).is_empty():
		phase = "over"
		result = "victory"
		_log("VICTORY!")
	elif _living(party).is_empty() and _living(bench).is_empty():
		phase = "over"
		result = "defeat"
		_log("The party has fallen...")


func _living(group: Array) -> Array:
	var out: Array = []
	for c in group:
		if c != null and c.is_alive():
			out.append(c)
	return out


func _all_living() -> Array:
	var out := _living(party)
	out.append_array(_living(bench))
	out.append_array(_living(enemies))
	return out


func _heal_event(target: Combatant, amount: int) -> void:
	events.append({ "kind": "heal", "target": target, "amount": amount, "tier": Rules.Tier.NORMAL })
	_log("%s recovers %d HP." % [target.display_name, amount])


func _log(line: String) -> void:
	log.append(line)

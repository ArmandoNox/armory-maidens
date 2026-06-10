class_name AI
extends RefCounted
## Enemy intent selection + scripted player policies for the balance simulator.


## Greedy enemy intent: best (multiplier x power) against the best slot,
## with a 20% seeded wobble so packs don't tunnel one girl forever.
static func pick_intent(b: Battle, e: Combatant) -> Dictionary:
	var options: Array = []
	for m in e.moves:
		if int(e.cooldowns.get(m, 0)) > 0:
			continue
		var mv: Dictionary = b.db.moves[m]
		for slot in b.party.size():
			var girl: Combatant = b.party[slot]
			if girl == null or not girl.is_alive():
				continue
			var mult := Rules.combined_mult(b.db, mv["element"], mv["phys"], girl)
			options.append({ "move": m, "slot": slot, "score": mult * float(mv["power"]) })
	if options.is_empty():
		return {}
	options.sort_custom(func(a, c): return a["score"] > c["score"])
	if options.size() > 1 and b.rng.randf() < 0.2:
		return options[b.rng.randi_range(1, mini(3, options.size() - 1))]
	return options[0]


## Random legal action — the balance floor. A game where random wins often
## has no decisions in it.
static func policy_random(b: Battle) -> Dictionary:
	var actions := b.legal_actions()
	var attacks := actions.filter(func(a): return a["type"] == "attack")
	if attacks.is_empty():
		return { "type": "pass" }
	return attacks[b.rng.randi_range(0, attacks.size() - 1)]


## Greedy player: best BELIEVED (mult x power) damage action. Uses public
## knowledge only — mutations stay honest. Probes unrevealed elites first.
static func policy_greedy(b: Battle) -> Dictionary:
	var actions := b.legal_actions()
	# Probe elite-tier unknowns early when we have icons to spare.
	if b.icons >= 2:
		for a in actions:
			if a["type"] == "probe":
				var foe: Combatant = b.enemies[a["target"]]
				if b.db.enemies[foe.id].get("tier", "normal") == "elite":
					return a
	var best: Dictionary = {}
	var best_score := -1.0
	for a in actions:
		if a["type"] != "attack":
			continue
		var mv: Dictionary = b.db.moves[a["move"]]
		if int(mv["power"]) <= 0:
			# Value heals when someone is hurt; small flat score otherwise skip.
			var effect: String = mv.get("effect", "")
			if effect.begins_with("heal") and _party_hurt(b):
				if best_score < 25.0:
					best = a
					best_score = 25.0
			continue
		var score := 0.0
		var hits := float(mv.get("hits", 1))
		if int(a["target"]) == -1:
			for t in b.enemies:
				if t.is_alive():
					score += Rules.believed_mult(b.db, mv["element"], mv["phys"], t) * float(mv["power"]) * hits
		else:
			var t: Combatant = b.enemies[int(a["target"])]
			score = Rules.believed_mult(b.db, mv["element"], mv["phys"], t) * float(mv["power"]) * hits
			# Prefer finishing wounded targets.
			if t.hp < t.max_hp / 3:
				score *= 1.3
		if score > best_score:
			best_score = score
			best = a
	if best.is_empty():
		return { "type": "pass" }
	return best


static func _party_hurt(b: Battle) -> bool:
	for p in b.party:
		if p != null and p.is_alive() and p.hp < p.max_hp * 0.55:
			return true
	return false

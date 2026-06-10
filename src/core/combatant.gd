class_name Combatant
extends RefCounted
## Runtime state for one fighter (girl or enemy). Built from data tables.

var id: String
var display_name: String
var side: String                      # "party" | "enemy"
var element: String
var archetype: String
var max_hp: int
var hp: int
var atk: int
var def: int
var spd: int
var basic: String = ""                # always-available 0-cooldown move id
var moves: Array = []                 # equipped move ids (excluding basic)
var trigger: String = ""              # switch-in trigger key (girls only)
var cooldowns: Dictionary = {}        # move_id -> rounds remaining
var statuses: Dictionary = {}         # key -> rounds remaining (guard/counter/burn/sunder/atk_up)
var elem_overrides: Dictionary = {}   # mutations: atk element -> true mult
var phys_overrides: Dictionary = {}   # mutations: atk phys -> true mult
var mutations: Array = []             # [{"kind","key","mult"}], usually 0-1; bosses roll more
var mutation_revealed: bool = true
var actions_this_round: int = 0


static func from_girl(db: DataDB, girl_id: String) -> Combatant:
	var g: Dictionary = db.girls[girl_id]
	var c := Combatant.new()
	c.id = girl_id
	c.display_name = g["name"]
	c.side = "party"
	c.element = g["element"]
	c.archetype = g["archetype"]
	c._set_stats(g["stats"])
	c.basic = g["basic"]
	c.moves = (g.get("equipped", g["moves"]) as Array).duplicate()
	c.trigger = g.get("trigger", "")
	return c


static func from_enemy(db: DataDB, enemy_id: String, rng: RandomNumberGenerator) -> Combatant:
	var e: Dictionary = db.enemies[enemy_id]
	var c := Combatant.new()
	c.id = enemy_id
	c.display_name = e["name"]
	c.side = "enemy"
	c.element = e["element"]
	c.archetype = e["archetype"]
	c._set_stats(e["stats"])
	c.moves = (e["moves"] as Array).duplicate()
	if rng.randf() < float(e.get("mutation_chance", 0.0)):
		for i in int(e.get("mutation_count", 1)):
			c._roll_mutation(db, rng)
	return c


func _set_stats(s: Dictionary) -> void:
	max_hp = int(s["hp"])
	hp = max_hp
	atk = int(s["atk"])
	def = int(s["def"])
	spd = int(s["spd"])


## One hidden affinity flip vs the public species chart. Tier flips:
## weak->resist, resist->weak, normal->randomly weak or resist.
## Repeat calls (bosses) pick distinct keys.
func _roll_mutation(db: DataDB, rng: RandomNumberGenerator) -> void:
	mutation_revealed = false
	var taken: Array = mutations.map(func(m): return m["key"])
	var keys: Array = []
	for el in db.element_order:
		if el != "neutral" and el not in taken:
			keys.append({ "kind": "element", "key": el })
	for ph in db.phys_types:
		if ph not in taken:
			keys.append({ "kind": "phys", "key": ph })
	if keys.is_empty():
		return
	var pick: Dictionary = keys[rng.randi_range(0, keys.size() - 1)]
	var current: float
	if pick["kind"] == "element":
		current = Rules.element_mult(db, pick["key"], element)
	else:
		current = Rules.phys_mult(db, pick["key"], archetype)
	var new_mult: float
	if current >= Rules.WEAK_MULT:
		new_mult = Rules.RESIST_MULT
	elif current <= Rules.RESIST_MULT:
		new_mult = Rules.WEAK_MULT
	else:
		new_mult = Rules.WEAK_MULT if rng.randf() < 0.5 else Rules.RESIST_MULT
	mutations.append({ "kind": pick["kind"], "key": pick["key"], "mult": new_mult })
	if pick["kind"] == "element":
		elem_overrides[pick["key"]] = new_mult
	else:
		phys_overrides[pick["key"]] = new_mult


## Persist only what a run changes about a girl; the rest rebuilds from data.
func to_save_dict() -> Dictionary:
	return { "id": id, "hp": hp, "atk": atk, "moves": moves.duplicate() }


static func from_save_dict(db: DataDB, d: Dictionary) -> Combatant:
	var c := from_girl(db, d["id"])
	c.hp = int(d["hp"])
	c.atk = int(d["atk"])
	c.moves = (d["moves"] as Array).duplicate()
	return c


func is_alive() -> bool:
	return hp > 0


## Clear per-battle state (statuses, cooldowns) while keeping HP — used when a
## persistent run roster enters a new fight.
func reset_battle_state() -> void:
	statuses.clear()
	cooldowns.clear()
	actions_this_round = 0


func eff_def() -> float:
	var d := float(def)
	if statuses.has("sunder"):
		d *= 0.75
	return d


func eff_atk() -> int:
	var a := float(atk)
	if statuses.has("atk_up"):
		a *= 1.25
	return roundi(a)


func all_usable_moves() -> Array:
	var out: Array = []
	if basic != "":
		out.append(basic)
	for m in moves:
		if int(cooldowns.get(m, 0)) <= 0:
			out.append(m)
	return out


func take_damage(amount: int) -> int:
	var dealt := amount
	if statuses.has("guard") and amount > 0:
		dealt = maxi(1, dealt / 2)
		statuses.erase("guard")
	hp = maxi(0, hp - dealt)
	return dealt


func heal(amount: int) -> int:
	var before := hp
	hp = mini(max_hp, hp + amount)
	return hp - before


func tick_round() -> Array:
	## Advance cooldowns and statuses at round start; returns log lines.
	var lines: Array = []
	for m in cooldowns.keys():
		cooldowns[m] = maxi(0, int(cooldowns[m]) - 1)
	if statuses.has("burn") and is_alive():
		var burn_dmg := maxi(1, roundi(max_hp * 0.06))
		hp = maxi(0, hp - burn_dmg)
		lines.append("%s takes %d burn damage." % [display_name, burn_dmg])
	for s in statuses.keys():
		statuses[s] = int(statuses[s]) - 1
		if int(statuses[s]) <= 0:
			statuses.erase(s)
	return lines

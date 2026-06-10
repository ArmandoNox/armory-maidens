class_name Run
extends RefCounted
## One roguelike run: persistent roster, act node map, fight/draft/event/rest
## flow. Pure logic — the map UI and tests drive it identically.
##
## Map: floors bottom-up; floor 0 entered first, top floor is the boss. Each
## node = {type, edges} where edges index into the NEXT floor. Party HP carries
## between fights; statuses/cooldowns reset per fight; the fallen revive to 25%
## after victory.

const REVIVE_FRACTION := 0.25
const REST_HEAL_FRACTION := 0.30
const DRAFT_OFFERS := 3

var db: DataDB
var rng := RandomNumberGenerator.new()
var act_id := "act1"
var roster: Array = []          # Combatants, persistent across fights
var map: Array = []             # Array[Array[{type, edges, done}]]
var cur_floor := -1             # -1 = run start, nothing entered yet
var cur_index := -1
var state := "map"              # map | battle | draft | event | over
var result := ""                # "" | victory | defeat
var pending_battle: Battle = null
var pending_draft := {}         # {girl_index, offers}
var pending_event_id := ""
var fights_won := 0


static func create(p_db: DataDB, girl_ids: Array, seed_val: int) -> Run:
	var r := Run.new()
	r.db = p_db
	r.rng.seed = seed_val
	for gid in girl_ids:
		r.roster.append(Combatant.from_girl(p_db, gid))
	r._gen_map()
	return r


## ---- Map ---------------------------------------------------------------------

func _gen_map() -> void:
	map = []
	var counts: Array = [2]
	for f in range(1, 6):
		counts.append(2 + (1 if rng.randf() < 0.5 else 0))
	counts.append(1)  # pre-boss rest
	counts.append(1)  # boss
	var last_floor := counts.size() - 1
	for f in counts.size():
		var floor_nodes: Array = []
		for i in counts[f]:
			var t := "fight"
			if f == last_floor:
				t = "boss"
			elif f == last_floor - 1:
				t = "rest"
			elif f > 0:
				var roll := rng.randf()
				if roll >= 0.85:
					t = "rest"
				elif roll >= 0.60:
					t = "event"
			floor_nodes.append({ "type": t, "edges": [], "done": false })
		map.append(floor_nodes)
	# Exactly one elite, somewhere on floors 3-5.
	var ef := rng.randi_range(3, 5)
	map[ef][rng.randi_range(0, map[ef].size() - 1)]["type"] = "elite"
	# Edges: nearest-by-ratio plus occasional second branch; then guarantee
	# every next-floor node has an inbound edge.
	for f in range(0, map.size() - 1):
		var n: int = map[f].size()
		var m: int = map[f + 1].size()
		var covered := {}
		for i in n:
			var j: int
			if n > 1:
				j = roundi(float(i) * float(m - 1) / float(n - 1))
			else:
				j = rng.randi_range(0, m - 1)
			map[f][i]["edges"].append(j)
			covered[j] = true
			if m > 1 and rng.randf() < 0.4:
				var j2 := clampi(j + (1 if rng.randf() < 0.5 else -1), 0, m - 1)
				if j2 not in map[f][i]["edges"]:
					map[f][i]["edges"].append(j2)
					covered[j2] = true
		for j in m:
			if not covered.has(j):
				map[f][rng.randi_range(0, n - 1)]["edges"].append(j)


## Nodes the player may enter right now: [{floor, index}].
func selectable_nodes() -> Array:
	if state != "map":
		return []
	var out: Array = []
	if cur_floor < 0:
		for i in map[0].size():
			out.append({ "floor": 0, "index": i })
	elif cur_floor < map.size() - 1:
		for j in map[cur_floor][cur_index]["edges"]:
			out.append({ "floor": cur_floor + 1, "index": j })
	return out


func enter_node(f: int, i: int) -> bool:
	var ok := false
	for s in selectable_nodes():
		if s["floor"] == f and s["index"] == i:
			ok = true
	if not ok:
		return false
	cur_floor = f
	cur_index = i
	var node: Dictionary = map[f][i]
	node["done"] = true
	match node["type"]:
		"fight", "elite", "boss":
			pending_battle = Battle.create_with_party(db, roster, _pick_encounter(node["type"]), rng.randi())
			state = "battle"
		"rest":
			for c in roster:
				if c.is_alive():
					c.heal(roundi(c.max_hp * REST_HEAL_FRACTION))
			state = "map"
		"event":
			var keys: Array = db.events.keys()
			pending_event_id = keys[rng.randi_range(0, keys.size() - 1)]
			state = "event"
	return true


func _pick_encounter(node_type: String) -> Array:
	var act: Dictionary = db.acts[act_id]
	match node_type:
		"boss":
			return act["boss"][rng.randi_range(0, act["boss"].size() - 1)]
		"elite":
			return act["elites"][rng.randi_range(0, act["elites"].size() - 1)]
		_:
			var pool: Array = act["fights_early"] if cur_floor < 3 else act["fights_late"]
			return pool[rng.randi_range(0, pool.size() - 1)]


## ---- Battle resolution ----------------------------------------------------------

## Call once when pending_battle.phase == "over".
func on_battle_finished() -> void:
	if pending_battle == null or state != "battle":
		return
	var was_boss: bool = map[cur_floor][cur_index]["type"] == "boss"
	if pending_battle.result == "victory":
		fights_won += 1
		for c in roster:
			if not c.is_alive():
				c.hp = maxi(1, roundi(c.max_hp * REVIVE_FRACTION))
			c.reset_battle_state()
		if was_boss:
			state = "over"
			result = "victory"
		else:
			pending_draft = _make_draft()
			state = "draft" if not pending_draft.is_empty() else "map"
	else:
		state = "over"
		result = "defeat"
	pending_battle = null


## ---- Drafting (the armory) -------------------------------------------------------

func _make_draft() -> Dictionary:
	var order: Array = range(roster.size())
	order.shuffle()
	for gi in order:
		var girl: Combatant = roster[gi]
		var pool: Array = db.girls[girl.id]["moves"]
		var available: Array = pool.filter(func(m): return m not in girl.moves)
		if available.is_empty():
			continue
		available.shuffle()
		return { "girl_index": gi, "offers": available.slice(0, DRAFT_OFFERS) }
	return {}


## replace_index: which equipped slot the new move overwrites; -1 = skip draft.
func apply_draft(offer: String, replace_index: int) -> void:
	if state != "draft":
		return
	if replace_index >= 0 and offer in pending_draft.get("offers", []):
		var girl: Combatant = roster[pending_draft["girl_index"]]
		if replace_index < girl.moves.size():
			girl.moves[replace_index] = offer
	pending_draft = {}
	state = "map"


## ---- Events -----------------------------------------------------------------------

func apply_event_choice(choice_index: int) -> String:
	if state != "event":
		return ""
	var ev: Dictionary = db.events[pending_event_id]
	var choice: Dictionary = ev["choices"][choice_index]
	var msg := ""
	match choice["effect"]:
		"atk_plus_one_random":
			var living := roster.filter(func(c): return c.is_alive())
			var girl: Combatant = living[rng.randi_range(0, living.size() - 1)]
			girl.atk += 1
			msg = "%s's attack rises permanently." % girl.display_name
		"heal_party_20":
			for c in roster:
				if c.is_alive():
					c.heal(roundi(c.max_hp * 0.20))
			msg = "The party recovers."
		"heal_party_15":
			for c in roster:
				if c.is_alive():
					c.heal(roundi(c.max_hp * 0.15))
			msg = "Everyone feels a little better."
		"full_heal_lowest":
			var lowest: Combatant = null
			for c in roster:
				if c.is_alive() and (lowest == null or float(c.hp) / c.max_hp < float(lowest.hp) / lowest.max_hp):
					lowest = c
			if lowest != null:
				lowest.hp = lowest.max_hp
				msg = "%s is fully restored." % lowest.display_name
		"blood_offer":
			for c in roster:
				if c.is_alive():
					c.hp = maxi(1, c.hp - roundi(c.max_hp * 0.10))
					c.atk += 1
			msg = "The whetstone drinks. Every blade bites deeper."
		"none":
			msg = "You move on."
	pending_event_id = ""
	state = "map"
	return msg

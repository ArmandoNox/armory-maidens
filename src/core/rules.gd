class_name Rules
extends RefCounted
## Stateless combat math: multiplier composition, hit tiers, damage formula.

const WEAK_MULT := 1.5
const RESIST_MULT := 0.5

enum Tier { WEAK, NORMAL, RESIST }


static func element_mult(db: DataDB, atk_elem: String, def_elem: String, overrides: Dictionary = {}) -> float:
	if overrides.has(atk_elem):
		return overrides[atk_elem]
	var row: Dictionary = db.element_chart.get(atk_elem, {})
	return row.get(def_elem, 1.0)


static func phys_mult(db: DataDB, atk_phys: String, archetype: String, overrides: Dictionary = {}) -> float:
	if overrides.has(atk_phys):
		return overrides[atk_phys]
	return db.archetypes.get(archetype, {}).get(atk_phys, 1.0)


## The core composition rule: element and physical multipliers MULTIPLY.
## weak(1.5) x resist(0.5) = 0.75 -> NORMAL tier. A swap that only neutralizes
## one axis avoids the crit; it does not blank the hit.
static func combined_mult(db: DataDB, atk_elem: String, atk_phys: String, defender) -> float:
	var em := element_mult(db, atk_elem, defender.element, defender.elem_overrides)
	var pm := phys_mult(db, atk_phys, defender.archetype, defender.phys_overrides)
	return em * pm


static func tier_of(mult: float) -> Tier:
	if mult >= WEAK_MULT:
		return Tier.WEAK
	if mult <= RESIST_MULT:
		return Tier.RESIST
	return Tier.NORMAL


static func tier_name(t: Tier) -> String:
	match t:
		Tier.WEAK: return "WEAK"
		Tier.RESIST: return "RESIST"
		_: return "NORMAL"


## Flat damage, no dice. Randomness lives in information (mutations), never outcomes.
static func damage(power: int, atk: int, eff_def: float, mult: float) -> int:
	if power <= 0:
		return 0
	return maxi(1, roundi(power * (float(atk) / maxf(1.0, eff_def + 8.0)) * mult))


## What the player BELIEVES the multiplier is: uses the public species chart
## unless the defender's mutation has been revealed. Greedy AI/policy must use
## this, never the true value — the information asymmetry is the mechanic.
static func believed_mult(db: DataDB, atk_elem: String, atk_phys: String, defender) -> float:
	var eo: Dictionary = defender.elem_overrides if defender.mutation_revealed else {}
	var po: Dictionary = defender.phys_overrides if defender.mutation_revealed else {}
	var em := element_mult(db, atk_elem, defender.element, eo)
	var pm := phys_mult(db, atk_phys, defender.archetype, po)
	return em * pm

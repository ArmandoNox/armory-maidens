# Armory Maidens (working title)

Roguelike party battler: Slay-the-Spire run structure, SMT-style press-turn combat,
anime girls with weapons. Godot 4.6, GDScript, data-driven.

## Core combat rules (greybox v0)

- Every attack has an **element** (ember/gale/terra/volt/tide/neutral) and a
  **physical type** (slash/pierce/blunt).
- Damage multiplier = element_mult × physical_mult. Weakness 1.5, resist 0.5.
  They compose: a fire-weak target that resists blunt takes a blunt-fire hit at
  1.5 × 0.5 = 0.75 → **neutral tier**. Swapping in a resist girl avoids the crit,
  it doesn't blank the hit.
- **Press-turn economy:** each side starts a round with icons = living actives.
  Actions cost 1 icon. Combined tier ≥ 1.5 mints a bonus icon (capped per round);
  tier ≤ 0.5 burns an extra icon. Enemies play by the same rules.
- **Switching** costs 1 icon, binds to the slot — the incoming girl eats any
  telegraphed hit aimed there, and fires her signature switch-in trigger.
- **Mutations:** each enemy *instance* can roll one hidden affinity flip vs its
  species' known chart. Probe (1 icon) reveals it; finding out the hard way costs
  you the economy. No outcome RNG on resolved actions — randomness lives in
  information, not dice.

## Layout

- `data/` — all balance as JSON (elements, physical archetypes, girls, moves, enemies, encounters)
- `src/core/` — pure-logic battle engine (no scene nodes; drives both UI and headless sim)
- `scenes/` — greybox battle UI (rectangles; classic-FF pixel look comes later)
- `tests/run_tests.gd` — headless unit tests
- `tools/simulate.gd` — headless batch battle simulator for balance

## Running

```powershell
$godot = "$env:LOCALAPPDATA\Microsoft\WinGet\Links\godot_console.exe"
& $godot --path . --headless --script res://tests/run_tests.gd   # tests
& $godot --path . --headless --script res://tools/simulate.gd -- --n 200 --policy greedy --seed 7
& $godot --path . --editor    # open editor
& $godot --path .             # play the greybox battle
```

## Art direction (decided 2026-06-10)

Dual-track: combat rendered classic-FF pixel style (sprites authored/curated later);
full AI-generated illustrations reserved for portraits, cards, menus, bond art.
Weapons authored once as separate sprites and composited in-engine.

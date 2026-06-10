# ARMORY MAIDENS — Canonical Handoff & Design Record

Last updated: 2026-06-10. This file is the single source of truth for *what was
decided and why*. Read it fully before any non-trivial work on this repo.
Claude's memory (`project_armory_maidens_roguelike.md` in the cwd-keyed store)
indexes this; the repo holds the detail.

**Live build:** https://armandonox.github.io/armory-maidens/ (GitHub Pages, repo `ArmandoNox/armory-maidens`, branch `master`, served from `/docs`)
**Local repo:** `C:\Users\arman\IdeaProjects\armory-maidens`
**Operator:** Armando — away from PC until ~2026-07-01, testing via the web URL on Mac/iPhone. The PC stays on (it is August's production host).

---

## 1. What this is

A personal-first, Steam-eventual indie roguelike: **Slay-the-Spire run
structure + SMT-style press-turn party combat + anime girls with weapons**,
built entirely by Claude Code in Godot 4.6 (GDScript), with AI-generated art.
North star: a clean, polished, clearly-communicated game — Pokemon-ish depth
without deckbuilder cards.

## 2. Decision log (what was decided, and WHY — do not relitigate casually)

Decisions came from four adversarial review rounds (two Fable 5 instances
debating, operator arbitrating) plus direct operator rulings.

**D1. No card/deckbuilder pivot (operator-confirmed after DA rounds 3-4).**
Operator floated "shared hand blended from the girls' cards by color." Rejected
because: (a) draw RNG is architecturally incompatible with the
probe/information-purchase game — paying an icon to learn a weakness you then
can't draw into is pure feel-bad; (b) the symmetric press-turn economy (enemies
play by your icon rules) is the marketing differentiator and has no card-native
expression; (c) StS-likes are saturated; "non-deck StS-structured" is the
underserved lane. Operator: "too early to be breaking the initial idea."
*Escape hatch:* if the fun-gate rubric (see §7) says the SYSTEM is flat (not
content-thin) AND the card hunger is for per-turn surprise → reopen as
Chrono-Ark-style per-girl mini-decks. The shared-hand version stays dead.

**D2. Combat core: press-turn economy, not free switching.** Original pitch
(free switching vs telegraphed intents) was killed in DA round 1 as "a lookup
table with a confirm button." Current core: icons = living actives per side;
WEAK combined-tier mints a bonus icon (capped/round); RESIST burns an extra;
enemies symmetric. Switching costs 1 icon, binds to the SLOT (incoming girl
eats the telegraphed hit) and fires her signature switch-in trigger.

**D3. Element × physical composition (operator's own design — core identity).**
Every attack = element (5-cycle ember→gale→terra→volt→tide, + neutral) ×
physical type (slash/pierce/blunt vs body archetypes). Multipliers MULTIPLY:
weak 1.5 × resist 0.5 = 0.75 → NORMAL tier. Meaning: a swap is
**crit-avoidance, not full mitigation**. This rule is load-bearing; tests
encode it.

**D4. Randomness lives in INFORMATION, never outcomes.** No damage rolls, no
miss RNG. Per-enemy-INSTANCE hidden affinity mutations (one flip vs the public
species chart; elites always one, boss two) revealed by Probe (costs an icon)
or by hitting the mutated key. Setup variance = pack/slot rolls × mutations ×
carried HP. REJECTED: cooldown carryover between fights (sandbagging/stall
incentive), enemy rows (no positional verbs), per-turn tactics draws
(cannibalizes kit identity → see D1).

**D5. Girl identity = four relationships to the ONE shared icon economy**
(DA round 4, replaces "private gauges" which fail — see Sea of Stars).
NOT YET BUILT — next major system work, gated on rubric answers:
- Kaede: icon-expensive heavy moves, refunds on Break states (tempo investment)
- Riko: icon-cheap multi-hit weakness-fisher (mints what Kaede spends —
  shared-pool scarcity IS the synergy tension; no hard anti-synergies)
- Tsubaki: profits-when-targeted — counter converts enemy attacks ON HER into
  her own resource. **No proactive icon manipulation on either side, ever**
  (icon-denial builds degenerate into solitaire; resists burning attacker
  icons stay the only denial in the game).
- Mizuki: banks icons across fights, hard-capped 2-3 (cap = anti-stall).
Plus **6-8 NAMED two-girl combos** authored over the status-interaction table
(burn + multi-hit = detonating bullets; sunder + pierce = armor shatter), with
on-screen combo callouts — this is the operator's "specific combos" ask.

**D6. Primary run-variance engine: weapon evolution** — 2-3 mutually exclusive
branch points per girl per run, implemented as MODIFIER TRANSFORMS on equipped
moves (e.g. "Ember branch: strikes gain fire + burn"), NOT parallel movesets.
Visual payoff via weapon sprite swap. NOT YET BUILT.

**D7. Art: dual-track, AI fully accepted.** Operator explicitly accepts AI
generation, Steam/community risk dismissed ("personal project... we can swap
assets later"). Pixel-art combat (classic FF side-view framing); full AI
illustrations for portraits/cards/menus/bond art. Weapons eventually authored
once as separate sprites composited in-engine (solves prop drift). Draft UI =
**armory/weapon-rack aesthetic, never card frames** (deckbuilder bait-risk).
COST RULE: precise and frugal — 1K gen size default, no 4K; "don't burn $500
when $100 would do." Spend to date: ~$2.40 for 18 images, all first-try.

**D8. Sexy lane (for later art):** committed-confident, not timid — but
all-ages-ish: no nudity/jiggle/Sexual-Content tag/uncensor bait. Pin-up art
lives in the (future) per-girl bond unlock track. Pairwise bond system CUT;
flat per-girl track + banter only.

**D9. Launch shape (far future):** finished 1.0 at ~$11.99, NO Early Access;
demo into Next Fest; girls #5/#6 as free post-launch beats. Roster locked at 4
for 1.0 (10-move pools, 4 equipped, drafted from offers of 3,
overwrite-to-learn).

**D10. Audio deliberately LAST** (operator ruling). Generate as needed when
the time comes.

**D11. Tracking:** operator will create a dedicated Linear team himself and
announce it — do NOT create epics on Syncerelabs. Until then this file + memory
are the record.

## 3. Architecture (how it's built)

Engine/UI split is strict: `src/core/` is pure logic (RefCounted, no scene
nodes) and drives the UI, the tests, and the simulators IDENTICALLY.

- `data/*.json` — ALL balance: elements.json (chart+colors), physical.json
  (archetypes), girls.json (stats/triggers/pool+equipped), moves.json,
  enemies.json (incl. mutation_chance/mutation_count), encounters.json
  (standalone packs), acts.json (act1 fight pools/elites/boss), events.json.
  Tuning is JSON-only; code never hardcodes balance.
- `src/core/rules.gd` — multiplier composition, tiers, flat damage formula
  (`power * atk/(def+8) * mult`), `believed_mult` (public knowledge until
  mutation revealed — greedy AI must use this, never truth).
- `src/core/combatant.gd` — runtime fighter; `mutations` is an ARRAY;
  `reset_battle_state()` keeps HP, clears statuses/cooldowns.
- `src/core/battle.gd` — press-turn state machine. `create()` (fresh girls,
  tests/sim) vs `create_with_party()` (persistent run roster). `events` array
  = structured FX feed ({kind, target, actor, amount, tier}) consumed by UI
  for popups/animations. Enemy AoE via target "all_party".
- `src/core/run.gd` — map gen (8 floors, forced single elite floors 3-5,
  pre-boss rest, boss top; edge coverage guaranteed), node flow, rest 30%,
  revive-at-25% on victory, draft offers, events.
- `src/core/ai.gd` — enemy intents (greedy mult×power, 20% wobble) + sim
  policies (policy_greedy uses believed_mult — information honesty).
- `src/game.gd` — autoload "Game" (db + current Run + save/settings IO).
  `checkpoint()` persists the run to `user://run_save.json` at every map-level
  transition; battles are NEVER persisted (refresh = pre-fight checkpoint, no
  fight skipping). rng seed/state serialize as STRINGS (JSON float precision).
  `user://settings.json` holds flags (help_seen). NOTE: autoloads do NOT
  load under `--script`; tools instantiate scenes manually.
- `scenes/title.tscn|title_ui.gd` — MAIN SCENE: key art, New Run / Continue
  (when a save exists) / How to Play / Settings stub. Dev hooks: AM_SHOT env
  jumps to the map for screenshots; AM_TITLE_SHOT screenshots the title.
- `src/ui/help_overlay.gd` — HelpOverlay.popup(parent): shared how-to-play
  overlay (auto-shows on first run-mode battle via settings flag).
- `assets/icons/icon_*.png` — 48px pixel icons: 6 elements, 3 phys, 5 node
  types, probe, switch. UITheme.icon()/icon_rect() load them with fallbacks.
- `scenes/run_map.tscn|run_map_ui.gd` — act map with drawn edge lines
  (overlay draw signal; gold = paths from your node), node-type icons +
  tooltips + selectable pulse, portrait roster bar, event panel, over panel
  with run stats.
- `scenes/battle.tscn|battle_ui.gd` — side-view battlefield (enemies left /
  party right, anchor-ratio placement), intent bubbles, HP bars, damage
  popups, idle-bob/lunge/shake/flash tweens, JRPG-framed bottom panels,
  armory draft flow on victory. Dual-mode: run vs standalone (pack picker).
- `src/ui/ui_theme.gd` — UITheme.panel_box()/style_button(): deep-blue
  bordered JRPG framing, element-tinted ability buttons.
- `assets/` — sprites/{girls,enemies}/<id>.png, portraits/<id>.png,
  backgrounds/{field,boss,map}.png. UI falls back to element-colored
  silhouettes when an asset is missing — roster additions never break.

## 4. Verification & tooling (run these; "done" = observed)

```powershell
$godot = "$env:LOCALAPPDATA\Microsoft\WinGet\Links\godot_console.exe"
& $godot --path . --headless --import                              # REQUIRED after new class_name scripts or new assets
& $godot --path . --headless --script res://tests/run_tests.gd     # 66 tests
& $godot --path . --headless --script res://tools/uicheck.gd       # UI hit-rects + click smoke
& $godot --path . --headless --script res://tools/simulate.gd -- --n 200 --policy greedy --seed 7
& $godot --path . --headless --script res://tools/simulate_run.gd -- --n 150 --seed 7
& $godot --path . --script res://tools/screenshot.gd               # battle screenshot (opens window briefly)
$env:AM_SHOT="<abs path>.png"; & $godot --path . ; $env:AM_SHOT=""  # map screenshot hook
```
- Balance bar: greedy-vs-random gap must stay meaningful (random should bleed
  HP/lose slime packs); run sim ~95% act clear greedy, deaths at boss.
- **uicheck exists because of a real shipped bug:** Godot Buttons do NOT size
  to children → widgets rendered fine but had ~0 clickable rects. Run uicheck
  after ANY battle-UI change.
- **`--import` gotcha (cost a debugging cycle 2026-06-10):** a NEW `class_name`
  script (or new image assets) is invisible to headless `--script` runs and
  exports until `godot --headless --import` updates the global class cache /
  imports the assets. Symptom: "Identifier not declared" parse errors on a
  class that plainly exists, or missing textures in export.

## 5. Deploy pipeline

1. `& $godot --path . --headless --export-release "Web" docs/index.html`
   (no-threads web preset — works without COOP/COEP headers, iPhone-Safari-safe)
2. Commit (descriptive, Co-Authored-By Claude line).
3. **Push via WSL** (Windows git has no GitHub creds):
   `wsl -d Ubuntu -u august bash -lc "cd /mnt/c/Users/arman/IdeaProjects/armory-maidens && git push origin master"`
4. Verify Pages picked it up (rebuild ~30-60s; CDN can serve stale HEAD
   briefly — full GET, compare pck size).

Gotchas: put `.gdignore` in any non-asset image dir (docs/, art_staging/) or
the Godot importer scans it. `export_presets.cfg` is tracked (no secrets).

## 6. Art generation pipeline (reusable, cost-capped)

- Scripts in WSL home: `~/armory_gen.py` (15 sprites/portraits),
  `~/armory_bg_gen.py` (16:9 backgrounds), `~/armory_polish_gen.py` (UI icons
  48px, attack-pose sprites, title key art). Run with
  `/home/august/august_reed/.venv/bin/python`.
- Model `gemini-3-pro-image-preview` (Nano Banana Pro) on Vertex, project
  `alpine-inkwell-492314-g1`, location `global`, auth =
  `gcloud auth print-access-token` refreshed per batch (1h expiry → silent 401).
- image_size "1K" ALWAYS (cost rule). ~$0.13/img. Battle sprites: solid
  #00FF00 bg prompt → PIL chroma-key → alpha → NEAREST resize (girls 256px,
  trash 224, elite 300, boss 384). Portraits 512² LANCZOS. Raw gens land in
  gitignored `art_staging/gen/raw/`.
- Style strings live in those scripts — REUSE THEM VERBATIM for consistency
  (16-bit SNES JRPG pixel art for sprites; cel-shaded anime bust for portraits).
- Character canon: Kaede (dark ponytail, bronze plate + kimono, greatsword),
  Riko (golden bob, cropped jacket, twin pistols), Tsubaki (crimson wild hair,
  gi + sarashi, gauntlets, embers), Mizuki (long teal hair, ocean robes,
  water-orb staff).

## 6b. Presentation direction (operator-approved 2026-06-10, post-brainstorm)

"Cleaner gaming experience" vision blended from StS / Balatro / Cobalt Core /
Against the Storm — four pillars: (1) feel the math (tiered hit choreography is
the audio stand-in), (2) the icon economy as a physical object (Icon Forge),
(3) the girls are a cast (cut-ins + barks), (4) the run is a place (medallion
map, Colossus in the skyline, Armory Room draft). Style laws: pixel-snapped
NEAREST everything, no smooth-particle confetti, never card frames.
- **Batch A SHIPPED** (`e30f598`): hit-stop/punch-zoom/rim flashes, mass damage
  numbers, intent icon chips, mutation glitch-flicker, ticker log + Log overlay,
  heat-edge buttons, field CRT shader, victory/defeat staging, ember map trail,
  save-version guard, cancel affordance.
- **Batch B SHIPPED** (`5d4ef05`): forged-iron 9-slice on every panel
  (assets/ui/ui_frame.png via `~/armory_chrome_gen.py`), Icon Forge rack with
  molten-mint / shard-burn animations.
- **Batch C SHIPPED** (`90bf6ba`): 12 cut-in busts (assets/cutins/, 4 girls ×
  confident/strained/fierce via `~/armory_cast_gen.py`); data/barks.json (lines
  per girl per trigger: weak/kill/hurt/probe/switch_in/victory/map/map_low);
  cut-in slam system (3.5s cooldown + per-trigger chance — punctuates, never
  narrates); her-deck command header; per-girl idles (Kaede dead still, Riko
  tilt-flick, Tsubaki boxer rock, Mizuki tidal); bench sprites bottom-center;
  map barks (wounded complain first). Gotcha: one bust needed a looser chroma
  threshold (yellow-green bg survived the standard key) — re-keyed raw, no regen.
- **Batch D**: the world — medallion map + marching party, ember weather,
  Colossus skyline, fight-start stamp, boss letterbox, Armory Room draft scene,
  forge-quench scene wipe.
- DA-converged but deferred (operator deprioritized phone): touch parity /
  two-tap arm pattern / physical-pt layout audit — full spec in session
  transcript; revisit when phone matters. Enemy-phase replay (L refactor, with
  4 desync guards: tick events, deferred intent bubbles, gated outcome render,
  incremental widgets) remains the top gameplay-feel item not yet built.

## 7. Pending / open

- **Fun-gate rubric** — operator has the 6 questions written aside, testing
  now (~10 fights). Q1 icons-changed-a-decision; Q2 still probing?; Q3
  enemies-same vs turns-same; Q4 switches/fight; Q5 what card-hunger actually
  was (a-options/b-surprise/c-growth/d-rewards); Q6 fresh-trio appetite.
  Answers gate the D5 identity kits and the D1 escape hatch.
- ~~Run state is in-memory only~~ SOLVED 2026-06-10: runs auto-save to
  `user://` at every map-level checkpoint; Continue on the title screen.
- Operator's Linear team — wait for announcement (D11).
- Roadmap order after rubric: D5 identity kits + named combos → D6 weapon
  evolution + armory rack visuals → sprite-sheet animations → relics/held
  items → act 2 → audio (D10 last).

## 8. Session history (compressed)

2026-06-10, single marathon day, commits on `master`:
`2e17325` greybox combat engine + 36 tests + sims + rectangle UI →
`a20e3e8` web export/Pages →
`df006d6` run layer (map/draft/events/boss, 53 tests) →
`1d913ae` sprites/portraits + FF battlefield + map paths →
`df443f8` backgrounds →
`25de683` click-bug fix + animations + JRPG panels + uicheck →
`7915a84` this handoff file →
`cba3a48` polish pass (title screen + key art, user:// run saves + Continue,
framed ability entries w/ pixel icons + believed-tier detail panel + tier
badges while aiming, HelpOverlay onboarding + icon mint/burn teach popups,
map node icons/gold paths/pulse/tooltips, attack-pose lunge swap + KO/switch/
shake/intent-pulse animations, run stats on the over panel; 66 tests).
All four DA rounds and operator rulings happened this day. Art spend ~$5.40
total (41 images: 18 greybox-era + 23 polish, all 1K, only 2 re-rolls ever).

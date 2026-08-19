# Masterclass Katana Mode — Design & Implementation Plan

> **Status:** Design / not yet implemented. Written 2026-08-18.
>
> **⚠ Pre-merge caveat:** File paths and `file.gd:line` anchors below reflect the
> codebase state *before* some in-flight merges landed. After merging, re-verify the
> anchors — especially in `weapon_controller.gd`, `player.gd`, `enemy.gd`,
> `enemy_spawner.gd`, and `map_assembler.gd` — before treating any line number as exact.
> The architecture claims (what owns what) are the durable part; the line numbers are not.

---

## 1. Concept

Equipping the **Masterclass Katana** flips the run into a distinct combat mode: a
grayscale, aim-driven hack-and-slash where the player clicks enemy **weak spots** to
teleport-strike *behind* them, chaining a damage-scaling **combo** while enemies swarm out
of unexplored rooms. Unequipping the katana exits the mode and restores normal play.

**Confirmed rules (locked):**
- Mode **fully replaces** normal combat while the katana is equipped.
- **Overkill is per-hit** — a single strike dealing > 300% of the enemy's max HP.
- **Combo decays after an idle gap** (time-based drain, plus the HUD number visually draining).

---

## 2. How the current weapon system works (baseline)

Read this before touching combat — the katana slots into it rather than replacing it.

A weapon today = **data resource + behavior scene** (composition, not inheritance):

- **`WeaponData extends ItemData`** (`scripts/items/weapon_data.gd`) — immutable, shared
  stats resource: `held_texture`, `base_damage`, `damage_variance`,
  `attack_interval_seconds`, `knockback_strength`, `grip_offset`,
  `attack_behavior_scene`, `consumed_on_attack`. Authored as `.tres`, no code required.
  `validation_errors()` currently **requires** `attack_behavior_scene` to be non-null.
- **`WeaponAttackBehavior extends Node2D`** (`scripts/combat/weapon_attack_behavior.gd`) —
  the pluggable base class with virtual hooks `configure(data)`, `aim(direction)`,
  `start_attack()` and signals `hit_requested(targets, source_position)`,
  `hit_source_spawned(source)`, `attack_committed`. **This is already the
  "overridable base class with a default contract" pattern.**
- **`WeaponController extends Node2D`** (`scripts/combat/weapon_controller.gd`) — owns the
  equipped `WeaponData`, the active behavior instance, the cooldown, and the **generic
  damage application** in `_on_hit_requested` (`weapon_controller.gd:114`). It only applies
  damage *if the behavior emits `hit_requested`*.
- Concrete behaviors already shipping: `MeleeSwingAttack`, `BowAttack`,
  `ThrowingAxeAttack`, `linear_weapon_projectile`.

Input flow: `player._process` calls `weapon_controller.try_attack()` while the attack
action is held (`player.gd:72`) → controller checks cooldown → `active_behavior.start_attack()`.
Aim is forwarded every physics frame via `weapon_controller.aim_at(mouse)` (`player.gd:67`).

### Weapon-system revamp — decision: **do NOT do it (for now)**

There was a question about introducing a `WeaponT` base class with inheritable/overridable
methods + a default weapon. Conclusion after review:

- **That pattern already exists** as `WeaponAttackBehavior`. A `WeaponT` inheritance tree
  would *merge data back into behavior*, forcing a script per weapon and losing the
  author-a-weapon-as-a-`.tres` win. Inheritance chains (`WeaponT → MeleeWeapon → Katana`)
  also get rigid the moment a weapon is "melee but throwable" etc. Behavior scenes avoid that.
- **The katana needs no `WeaponController` changes.** The generic damage path only runs if a
  behavior emits `hit_requested`. The katana behavior simply **doesn't emit it** and instead
  routes to `KatanaMode`, which applies combo-scaled, classified damage. Override-everything
  is *already* achievable by opting out of the shared signal.
- **Deferred optional enhancements** (do only when 2–3 weapons actually ask for them):
  1. `WeaponAttackBehavior.applies_own_damage() -> bool` (default `false`) — formalizes the
     katana's opt-out of the controller damage path.
  2. A `DefaultAttackBehavior` used when `attack_behavior_scene` is null — the "default
     weapon/aim for weapons without a specific class" idea. Requires relaxing
     `WeaponData.validation_errors()` (`weapon_data.gd:37`).

  Both are ~30-line, backwards-compatible additions. **Not required to ship the katana.**
  Rule of thumb: don't rewrite the foundation while building a large feature on top of it.

---

## 3. Katana mode architecture

**A `KatanaMode` autoload orchestrates the entire mode** — the single owner of: mode
on/off, grayscale post-process, combo state, the weak-spot overlay, the spawn loop, and the
per-mode stat overrides (player speed, damage-taken multiplier, necro summon count, spawn
rate). Everything else reads flags off it. Keeps the mode self-contained and *reversible*
rather than scattering `if katana_mode` branches through the codebase.

Key decisions:
1. **Mode toggles off `equipped_weapon_changed`.** `player._on_equipped_weapon_changed`
   (`player.gd:153`) already fires on every swap → detect katana identity →
   `KatanaMode.enter()` / `.exit()`. No new input or menu.
2. **The katana is its own `WeaponAttackBehavior` subclass**, not the melee swing. Its
   `start_attack()` means "resolve the weak spot under the cursor and strike," not a hitbox swing.
3. **`KatanaMode` applies katana damage, not `WeaponController`.** The mode must classify
   each hit (survived / instakill / overkill) to pick the death animation and needs the live
   combo multiplier, so the behavior reports "weak spot struck this enemy" to `KatanaMode`,
   which computes damage, applies it, classifies, and fires the matching FX. Generic
   controller path is untouched for all other weapons.

---

## 4. New files

| File | Role |
|---|---|
| `scripts/autoload/katana_mode.gd` | Autoload. Mode lifecycle, combo state, stat overrides, spawn loop; holds refs to overlay + grayscale. |
| `scripts/items/katana_weapon_data.gd` | `extends WeaponData`; adds `sheathed_texture`, `unsheathed_texture`, `empty_sheath_texture`, `max_strike_range`, `combo_damage_per_stack`, `is_katana`. |
| `scripts/combat/katana_aim_attack.gd` + `scenes/combat/katana_aim_attack.tscn` | `WeaponAttackBehavior`. Renders sword + sheath, resolves clicked weak spot, requests the strike. |
| `scripts/combat/weak_spot.gd` + `scenes/effects/weak_spot.tscn` | Per-enemy pulsing-heart marker; computes behind-enemy position, range/reachability state, click detection. |
| `scripts/effects/slice_corpse.gd` + `scenes/effects/slice_corpse.tscn` | Gibbing system: splits a captured sprite frame into two halves along the slash angle; drives slide / floaty separation / dust-out. |
| `scripts/fx/katana_grayscale.gd` + `scripts/fx/grayscale.gdshader` | Full-screen desaturation post-process (CanvasLayer, like `FovRenderer`). |
| `scripts/fx/slice_split.gdshader` | Discards pixels on one side of an angled line, for the two corpse halves. |
| `scenes/effects/blood_spray.tscn` | Colored `GPUParticles2D` blood burst at the slash point. |
| `scenes/effects/teleport_fx.tscn` | Colored/white teleport flash at origin + destination. |
| `scenes/ui/combo_counter.tscn` + `scripts/ui/combo_counter.gd` | The colored hit-combo HUD. |
| `resources/weapons/masterclass_katana.tres` | The weapon resource; add to a loot pool / chest so it's obtainable. |
| `tests/combat/test_katana_mode.gd`, `tests/combat/test_weak_spot.gd` | GUT coverage. |

## 5. Modified files

- **`scripts/player.gd`** — make `SPEED` a runtime `move_speed` var so `KatanaMode` can set
  50%; in `_on_equipped_weapon_changed` detect the katana → enter/exit mode; `take_damage`
  applies `KatanaMode.damage_taken_multiplier`; add a `teleport_to(pos)` helper.
- **`scripts/enemies/enemy.gd`** — add `weak_spot_position(from)` = `global_position +
  (global_position - from).normalized() * offset`; add `apply_katana_hit(raw_damage,
  slash_angle, source)` that classifies survived/insta/overkill and spawns blood or
  `slice_corpse`; register/deregister a weak-spot marker while the mode is active.
- **`scripts/enemies/necromancer.gd`** — summon count reads `KatanaMode.necro_summon_count`
  (6 in mode, else current `randi_range(2, 3)` near `necromancer.gd:18`).
- **`scripts/autoload/enemy_spawner.gd`** — add `spawn_in_unvisited_rooms()`, reusing the
  wall-safe `_resolve_offset_position` pattern (`enemy_spawner.gd:73`).
- **`scripts/map/map_assembler.gd`** — expose `unvisited_room_bounds()`; it already tracks
  `_mm_rooms` bounds + `_visited_rooms` (`map_assembler.gd:128`, updated in
  `_update_exploration` `map_assembler.gd:536`).
- **`main.tscn` / project autoloads** — register `KatanaMode`; mount `combo_counter` and the
  grayscale layer.

---

## 6. Implementation phases

**Phase 1 — Weapon + mode skeleton (no FX).** `KatanaWeaponData`, the `.tres`, a stub
`KatanaAimAttack` showing the unsheathed sword + empty sheath (swap sheathed→empty on draw).
Wire `KatanaMode.enter/exit` off the equip signal. Verify toggle with a debug flag. Headless compile.

**Phase 2 — Weak spots + teleport strike (core loop).** `weak_spot.tscn` per enemy: each
frame compute the behind-enemy point; state = *in-range* (red pulsing heart) / *out-of-range*
(grayscale) / *unhittable* (teleport dest in wall or off-world → hidden/dimmed). Reachability
reuses the wall-raycast pattern from `enemy_spawner.gd:73`. On click of an in-range reachable
spot: `player.teleport_to(spot)`, `enemy.apply_katana_hit(...)`, combo++. Enforce
`max_strike_range` from the player.

**Phase 3 — Combo system + HUD.** `KatanaMode` tracks `combo` + `combo_timer`; damage =
`base_damage + combo * combo_damage_per_stack`. Combo **decays after an idle gap** (tween the
counter shrinking/fading as it drains). `combo_counter.tscn` renders in **color** on the top
color layer.

**Phase 4 — Death animations + gibbing.** In `enemy.apply_katana_hit`, classify:
- **Survived** → `blood_spray.tscn` at the slash point (colored), enemy lives, flash.
- **Instakill** (health ≤ 0, hit ≤ 300% max HP) → `slice_corpse` split along `slash_angle`;
  dramatic pause (~0.3 s tween delay), then one half **slides down** the other; free the enemy.
- **Overkill** (single hit > 300% max HP) → `slice_corpse` halves separate with **low-grav
  floaty drift**, then **dissolve to dust** by reusing `vaporize.gdshader` (drive its
  `progress` — same scatter the `Vaporizer` already produces, `scripts/fov/vaporizer.gd`).

  `slice_corpse.tscn` captures the enemy's current `AnimatedSprite2D` frame texture into two
  `Sprite2D` halves, each using `slice_split.gdshader` (discard on one side of the angled
  line). Halves persist briefly (`gib_lifetime`) then free — the reusable gibbing system.

**Phase 5 — Grayscale + color exceptions.** Full-screen desaturation via `BackBufferCopy` +
`ColorRect` shader on a CanvasLayer (mirrors `FovRenderer`'s screen-furniture pattern,
`fov_renderer.gd:90`). **Colored exceptions** — blood particles, katana + sheath sprites, and
the combo counter — render on a `ColorOverlay` CanvasLayer *above* the grayscale pass. The
sword/sheath track the player by copying its screen position each frame using the same
canvas-transform inversion as `FovRenderer._push_view` (`fov_renderer.gd:230`).
**Highest-risk visual piece** — fallback is a SubViewport composite (see Risks). Prototype early.

**Phase 6 — Teleport FX + entry cutscene.** `teleport_fx.tscn` flash at both origin and
destination per strike. Entry cutscene on `KatanaMode.enter()`: brief time-scale dip,
sheathe→unsheathe draw, grayscale fade-in, camera punch — short and skippable.

**Phase 7 — Swarm & difficulty tuning.** `KatanaMode` spawn loop calls
`enemy_spawner.spawn_in_unvisited_rooms()` on a fast interval (greatly increased rate);
`player.move_speed = SPEED * 0.5`; raise `damage_taken_multiplier`; `necro_summon_count = 6`.
All values are `@export`/consts on `KatanaMode` for tuning.

---

## 7. Testing

Per the Godot-validation notes, run headless compile/GUT after each phase (Godot exe is not
on PATH — see the memory note for the exact path/commands). Keep new tests logic-only so they
run headless:

- `test_weak_spot.gd` — behind-enemy math; in-range vs out-of-range vs unhittable; off-world rejection.
- `test_katana_mode.gd` — enter/exit toggles stat overrides; combo increment + decay; damage =
  base + combo·per-stack; hit classification thresholds (survive / insta / overkill at 300%).
- Extend enemy tests for `apply_katana_hit` outcome selection.

Visual FX (shaders, particles, cutscene) are verified by running the app, not GUT.

---

## 8. Risks / open items

1. **Grayscale-with-color-exceptions** is the trickiest Godot piece. Primary: screen-shader
   desaturate + top color CanvasLayer for exceptions. Fallback: render the world into a
   SubViewport, desaturate that, composite colored FX on top. Prototype in Phase 5 first.
2. **Input model** — normal play attacks on the *held* action (`player.gd:72`); the mode wants
   a *discrete click on a specific weak spot*. Plan routes clicks through each weak-spot
   marker's `Area2D`/input rather than hold-to-attack.
3. **Obtainability** — decide whether the katana drops from a chest/loot pool or is granted
   directly; it must reach the inventory to be equipped (`WeaponEquipment.swap_from_inventory`).
4. **Off-world / in-wall weak spots** — an enemy whose behind-spot lands in a wall or outside
   the world is **not hittable** (marker hidden/dimmed). Uses the same wall raycast as spawning.

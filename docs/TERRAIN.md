# Terrain and character inspection

Terrain modifiers belong to `src/play/terrain.zig`. Its typed table covers hit chance,
dodge, every elemental resistance and every harmful status resistance, with neutral defaults
for tiles that have no effects. Balance values live only in that table.

`Simulation.combatStats` resolves an actor's base resistances, hero dodge where applicable,
innate status resistance and temporary buildup, then applies the occupied tile's modifiers.
The tile is queried when needed, so walking, knockback, pulls, leaps, splits and travel
cannot leave a cached terrain bonus behind. All occupants use the same rule, including
flying bodies. Terrain bonuses are never written into actor stats or saved buildup.

Hit chance and dodge use separate rolls; a missed attack stops at its collision and
applies no damage, status or buildup. Dodge retains its attribute cap. Elemental
resistances clamp to -100..100 and reduce damage, including burning ticks. Status
resistances also clamp to -100..100 and affect application rather than damage: positive
values can resist an application; negative values increase its proc chance, capped at 100%.
Successful applications alone build temporary resistance. Leaving a tile changes resistance
immediately without clearing an existing status or changing its duration.

New terrain effects should add typed fields and resolution here, with a neutral default,
then route their consumers through the simulation resolver. Do not add tile checks to
individual skills. Inspection lists modifiers from the same table used by combat.

Inspect navigation includes HUD parts and visible onscreen characters. Foe cards show only
the name in title case and presented HP, followed by a divider and a separate terrain section:
the tile name and its signed effects, also in title case. Status effects read as changes to
application chance, such as "+15% Chance To Burn" on grass. Neutral terrain says "No Effects".
The tile is the one beneath the presented body. Hero cards retain their detailed stats,
presented statuses and buildup. Hidden, unborn and departed bodies have no inspect target.
Long cards scroll through page controls or the mouse wheel. Inspection never spends a turn.

Projectile target suggestions include only visible enemies reached by the preview flight,
which ignores unseen bodies and barrels. Free aiming can choose any in-range cell in geometric line of sight, including empty,
dark or wall cells, and opens without a visible target. The first body, barrel or blocking
terrain intercepts a nonpiercing projectile, even if that attack misses. Preview rendering
must not reveal hidden collisions or their surrounding burst areas; confirmed flight still
hits unseen interceptors.

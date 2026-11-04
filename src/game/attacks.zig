const std = @import("std");
const mathx = @import("../core/mathx.zig");
const actor = @import("../play/actor.zig");
const attrs = @import("../play/attrs.zig");
const damage = @import("../play/damage.zig");
const items = @import("../play/items.zig");
const progress = @import("../play/progress.zig");
const resilience = @import("../play/resilience.zig");
const chronicle = @import("../play/chronicle.zig");
const skillbar = @import("../play/skillbar.zig");
const terrain = @import("../play/terrain.zig");
const enfeeble = @import("../play/enfeeble.zig");
const shock = @import("../play/shock.zig");
const burning = @import("../play/burning.zig");
const glacial = @import("../play/glacial.zig");
const simulation = @import("sim.zig");
const Simulation = simulation.Simulation;

pub const Roll = struct {
    dmg: i32,
    crit: bool = false,
    physical: i32 = 0,
    effect: items.WeaponEffect = .{},
    applied: ?resilience.Kind = null,
    hit_checked: bool = false,

    pub fn against(self: Roll, armour: i32, rng: *mathx.Rng) Roll {
        var out = self;
        out.dmg -= self.physical - attrs.armoured(armour - self.effect.penetration, self.physical, rng);
        out.physical = 0;
        return out;
    }
};
pub const Rolled = struct {
    blow: damage.Damage,
    crit: bool = false,
    effect: items.WeaponEffect = .{},

    pub fn physical(h: Rolled) Roll {
        return .{ .dmg = h.blow.physical, .physical = h.blow.physical, .crit = h.crit, .effect = h.effect };
    }
};

/// A bump's roll before attributes: the melee weapon's, or the body's own blow.
pub fn kickRaw(rng: *mathx.Rng, gear: *const items.Gear, blow: actor.Strike) i32 {
    return if (gear.weapon(.melee)) |b| b.roll(rng) else blow.roll(rng);
}

/// The crit is drawn after the damage it scales.
pub fn scaled(rng: *mathx.Rng, by: attrs.Attrs, style: attrs.Style, hit: damage.Damage) Rolled {
    const crit = by.crits(rng);
    return .{ .blow = by.blow(style, hit, crit, rng), .crit = crit };
}

pub fn heroRoll(sim: *Simulation, comptime attack: attrs.Attack, raw: i32) Roll {
    return heroRollWith(&sim.rng, sim, attack, raw);
}

pub fn heroRollWith(rng: *mathx.Rng, sim: *const Simulation, comptime attack: attrs.Attack, raw: i32) Roll {
    const gear = sim.inventory.gear;
    var hit = scaled(rng, gear.forAttack(sim.heroAttrs(), attack), gear.scaling(attack), .{ .physical = raw });
    hit.effect = gear.onHit(attack);
    return hit.physical();
}

pub fn heroKick(sim: *Simulation) Roll {
    return heroRoll(sim, .melee, kickRaw(&sim.rng, &sim.inventory.gear, sim.class.strike()));
}

pub fn heroSkill(sim: *Simulation, comptime act: skillbar.Act) Roll {
    return heroArrow(sim, act, true).physical();
}

pub fn heroArrow(sim: *Simulation, comptime act: skillbar.Act, body: bool) Rolled {
    return heroScaled(sim, act, rawFor(sim, act, body));
}

/// A raw `act` roll scaled by the hero's attributes and its rank, with its crit.
pub fn heroScaled(sim: *Simulation, comptime act: skillbar.Act, raw: damage.Damage) Rolled {
    const b = blowFor(sim, act);
    var hit = scaled(&sim.rng, b.by, b.style, raw);
    if (raw.physical > 0) hit.effect = sim.inventory.gear.onHit(act.attack().?);
    return hit;
}

pub fn blowFor(sim: *const Simulation, comptime act: skillbar.Act) progress.Blow {
    comptime std.debug.assert(act.attack() != null);
    return sim.growth.preparedBlow(sim.heroAttrs(), sim.inventory.gear, act, sim.heroSteady()).?;
}

pub fn basesFor(sim: *const Simulation, act: skillbar.Act) skillbar.EquippedBases {
    return act.equippedBases(sim.inventory.gear);
}

/// Physical before elemental, preserving the seeded shot sequence; without `body`, no physical.
pub fn rollRaw(rng: *mathx.Rng, comptime act: skillbar.Act, bases: skillbar.EquippedBases, body: bool) damage.Damage {
    var raw = damage.Damage{};
    if (body) for (bases.parts()) |maybe| {
        if (maybe) |b| raw.physical += b.roll(rng);
    };
    if (comptime act.element()) |element| raw.elements.set(element, bases.element.?.roll(rng));
    return raw;
}

pub fn rawFor(sim: *Simulation, comptime act: skillbar.Act, body: bool) damage.Damage {
    return rollRaw(&sim.rng, act, basesFor(sim, act), body);
}

/// Roll status before nonlethal damage so split halves inherit it.
pub fn afflicted(sim: *Simulation, a: *actor.Actor, comptime M: type, lands: bool, resist: i16) bool {
    const takes = lands and if (sim.combatStats(a).statuses.get(M.AILMENT) < 0)
        sim.procStatus(a, M.AILMENT, M.chance(resist))
    else
        M.procs(&sim.rng, resist) and sim.takeStatus(a, M.AILMENT);
    if (takes) M.afflict(a, &sim.rng);
    return takes;
}

/// A mimic still posing as its chest cannot dodge.
pub fn heroLands(sim: *Simulation, a: *const actor.Actor, origin: chronicle.AttackOrigin) bool {
    const h = sim.heroBody() orelse return false;
    if (a.disguised or !sim.combatStats(h).misses(sim.combatStats(a), &sim.rng)) return true;
    sim.sayOf(a, "{s} misses the {s}.", .{ sim.name.text(), actor.row(a.kind).name });
    sim.chronicle.note(.{ .missed = .{ .origin = origin } });
    return false;
}

/// `dmg` past armour as it lands on `target`: cut by an enfeebled striker, then raised by the target's shock.
pub fn landed(weak: bool, target: *actor.Actor, dmg: i32) i32 {
    return target.shock.spend(enfeeble.weaken(weak, dmg));
}

fn heroWeak(sim: *const Simulation) bool {
    return if (sim.heroBody()) |h| h.afflictions().contains(.enfeeble) else false;
}

fn blowOn(weak: bool, bonus: i32, s: *shock.Shock, dmg: i32, applied: ?resilience.Kind) i32 {
    const weakened = enfeeble.weaken(weak, mathx.percentCeil(dmg, mathx.PERCENT + bonus));
    return if (applied == .shock) weakened else s.spend(weakened);
}

/// The hero's percent more damage against `a`, from Opportunist's.
pub fn opportune(sim: *const Simulation, a: *const actor.Actor) i32 {
    return if (a.slowed()) @max(0, sim.inventory.gear.sum(.opportunist)) else 0;
}

/// What `resolve` deals `target` past armour for a blow carrying `applied`, spending nothing.
pub fn dealt(sim: *const Simulation, target: *const actor.Actor, dmg: i32, applied: ?resilience.Kind) i32 {
    var s = target.shock;
    return blowOn(heroWeak(sim), opportune(sim, target), &s, dmg, applied);
}

pub fn bite(rng: *mathx.Rng, attacker: terrain.Stats, defender: terrain.Stats, s: actor.Strike) ?i32 {
    if (attacker.misses(defender, rng)) return null;
    return s.roll(rng);
}

pub const Hit = struct {
    damage: simulation.DamageResult,
    roll: Roll,
    kind: actor.Kind,
    at: mathx.P,
    culled: bool,
    bled: ?[]const u8,
    stunned: bool,
    imbued: Imbued,
    recovery: i32,
};

/// The ailments an imbued weapon brings, each by the module that owns it.
pub const IMBUED = .{ burning, glacial, shock };
pub const Imbued = std.EnumSet(resilience.Kind);

comptime {
    for (IMBUED, items.IMBUES) |M, e| std.debug.assert(M.AILMENT == items.imbued(e));
}

pub const Outcome = union(enum) { miss, hit: Hit };

pub fn resolve(sim: *Simulation, target: actor.ActorId, raw: Roll, origin: chronicle.AttackOrigin) ?Outcome {
    const a = sim.pool.get(target.value) orelse return null;
    if (!raw.hit_checked and !heroLands(sim, a, origin)) return .miss;
    var r = raw.against(sim.combatStats(a).armour, &sim.rng);
    r.dmg = blowOn(heroWeak(sim), opportune(sim, a), &a.shock, r.dmg, r.applied);
    const kind = a.kind;
    const at = a.at;
    const perks = sim.heroPerks();
    const culled = r.dmg > 0 and perks.culls(a.hp - r.dmg, a.max);
    var bled: ?[]const u8 = null;
    var stunned = false;
    var imbued = Imbued.initEmpty();
    if (!culled and r.dmg > 0 and r.dmg < a.hp) {
        if (r.applied != .bleed and sim.procStatus(a, .bleed, r.effect.bleed)) {
            bled = a.bleed.said();
            a.bleed.startWith(r.effect.bleed_damage);
        }
        if (r.applied != .stun and sim.procStatus(a, .stun, r.effect.stun)) {
            a.clock.stun();
            stunned = true;
        }
        inline for (IMBUED) |M| {
            if (r.applied != M.AILMENT and sim.procStatus(a, M.AILMENT, r.effect.chance(M.AILMENT))) {
                M.afflict(a, &sim.rng);
                imbued.insert(M.AILMENT);
            }
        }
    }
    const h = sim.resolveDamage(target, if (culled) a.hp else r.dmg);
    return .{ .hit = .{
        .damage = h,
        .roll = r,
        .kind = kind,
        .at = at,
        .culled = culled,
        .bled = bled,
        .stunned = stunned,
        .imbued = imbued,
        .recovery = if (h.dmg > 0) perks.life_on_hit + if (h.lethal) perks.life_on_kill else 0 else 0,
    } };
}

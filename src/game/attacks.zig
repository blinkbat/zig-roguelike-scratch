const std = @import("std");
const mathx = @import("../core/mathx.zig");
const actor = @import("../play/actor.zig");
const attrs = @import("../play/attrs.zig");
const damage = @import("../play/damage.zig");
const affixes = @import("../play/affixes.zig");
const Gear = @import("../play/gear.zig").Gear;
const item_bases = @import("../play/item_bases.zig");
const progress = @import("../play/progress.zig");
const resilience = @import("../play/resilience.zig");
const chronicle = @import("../play/chronicle.zig");
const skillbar = @import("../play/skillbar.zig");
const terrain = @import("../play/terrain.zig");
const enfeeble = @import("../play/enfeeble.zig");
const shock = @import("../play/shock.zig");
const burning = @import("../play/burning.zig");
const glacial = @import("../play/glacial.zig");
const tactics = @import("../play/tactics.zig");
const simulation = @import("sim.zig");
const Simulation = simulation.Simulation;

pub const Roll = struct {
    dmg: i32,
    crit: bool = false,
    physical: i32 = 0,
    effect: item_bases.WeaponEffect = .{},
    applied: ?resilience.Kind = null,
    hit_checked: bool = false,
    /// Opportunist's bonus as the target stood before this blow's own ailment.
    opportunity: ?i32 = null,
    /// Imbue's fire, past armour, still to meet the target's fire resistance; not in `dmg` yet.
    fire: i32 = 0,

    pub fn against(self: Roll, armour: i32, rng: *mathx.Rng) Roll {
        var out = self;
        out.dmg -= self.physical - attrs.armoured(armour - self.effect.penetration, self.physical, rng);
        out.physical = 0;
        return out;
    }

    pub fn burnt(self: Roll, resists: damage.Resists) Roll {
        var out = self;
        out.dmg += damage.resisted(self.fire, resists.get(tactics.Imbue.IMBUES));
        out.fire = 0;
        return out;
    }
};
pub const Rolled = struct {
    blow: damage.Damage,
    crit: bool = false,
    effect: item_bases.WeaponEffect = .{},

    pub fn physical(h: Rolled) Roll {
        return .{ .dmg = h.blow.physical, .physical = h.blow.physical, .crit = h.crit, .effect = h.effect, .fire = h.blow.elements.get(tactics.Imbue.IMBUES) };
    }

    /// Its whole blow past `resists`, armour still to take its physical part.
    pub fn against(h: Rolled, resists: damage.Resists) Roll {
        return .{ .dmg = h.blow.total(resists), .physical = h.blow.physical, .crit = h.crit, .effect = h.effect };
    }
};

pub fn meleeRaw(rng: *mathx.Rng, gear: *const Gear, blow: actor.Strike) i32 {
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
    return imbuedScaled(rng, sim, attack, gear.forAttack(sim.heroAttrs(), attack), gear.scaling(attack), .{ .physical = raw }).physical();
}

fn imbuedScaled(rng: *mathx.Rng, sim: *const Simulation, attack: attrs.Attack, by: attrs.Attrs, style: attrs.Style, d: damage.Damage) Rolled {
    const readied = sim.heroReadied();
    var fired = d;
    if (readied.imbues(attack)) fired.elements.getPtr(tactics.Imbue.IMBUES).* += tactics.Imbue.FIRE.roll(rng);
    var hit = scaled(rng, by, style, fired);
    hit.effect = sim.growth.onHit(sim.inventory.gear, attack, readied);
    return hit;
}

pub fn heroMelee(sim: *Simulation) Roll {
    return heroRoll(sim, .melee, meleeRaw(&sim.rng, &sim.inventory.gear, sim.class.strike()));
}

pub fn heroSkill(sim: *Simulation, comptime act: skillbar.Act) Roll {
    return heroBlow(sim, act).physical();
}

pub fn heroBlow(sim: *Simulation, comptime act: skillbar.Act) Rolled {
    return heroScaled(sim, act, rawFor(sim, act));
}

pub fn heroScaled(sim: *Simulation, comptime act: skillbar.Act, raw: damage.Damage) Rolled {
    const b = blowFor(sim, act);
    if (raw.physical > 0) return imbuedScaled(&sim.rng, sim, act.attack().?, b.by, b.style, raw);
    return scaled(&sim.rng, b.by, b.style, raw);
}

pub fn blowFor(sim: *const Simulation, comptime act: skillbar.Act) progress.Blow {
    comptime std.debug.assert(act.attack() != null);
    return sim.growth.preparedBlow(sim.heroAttrs(), sim.inventory.gear, act, sim.heroReadied()).?;
}

pub fn basesFor(sim: *const Simulation, act: skillbar.Act) skillbar.EquippedBases {
    return act.equippedBases(sim.inventory.gear);
}

/// Physical before elemental, preserving the seeded shot sequence.
pub fn rollRaw(rng: *mathx.Rng, comptime act: skillbar.Act, bases: skillbar.EquippedBases) damage.Damage {
    var physical: i32 = 0;
    for (bases.parts()) |maybe| {
        if (maybe) |b| physical += b.roll(rng);
    }
    var raw = rollRawElement(rng, act, bases);
    raw.physical = physical;
    return raw;
}

fn rollRawElement(rng: *mathx.Rng, comptime act: skillbar.Act, bases: skillbar.EquippedBases) damage.Damage {
    var raw = damage.Damage{};
    if (comptime act.element()) |element| raw.elements.set(element, bases.element.?.roll(rng));
    return raw;
}

pub fn rawFor(sim: *Simulation, comptime act: skillbar.Act) damage.Damage {
    return rollRaw(&sim.rng, act, basesFor(sim, act));
}

pub fn rawElementFor(sim: *Simulation, comptime act: skillbar.Act) damage.Damage {
    return rollRawElement(&sim.rng, act, basesFor(sim, act));
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

pub fn heroLands(sim: *Simulation, a: *const actor.Actor, origin: chronicle.AttackOrigin) bool {
    const h = sim.heroBody() orelse return false;
    if (a.disguised or !sim.combatStats(h).misses(sim.combatStats(a), &sim.rng)) return true;
    sim.sayOf(a, "{s} misses the {s}.", .{ sim.name.text(), actor.row(a.kind).name });
    sim.chronicle.note(.{ .missed = .{ .origin = origin } });
    return false;
}

pub fn landed(weak: bool, target: *actor.Actor, dmg: i32) i32 {
    return shock.spend(&target.shock, enfeeble.weaken(weak, dmg));
}

fn heroWeak(sim: *const Simulation) bool {
    return if (sim.heroBody()) |h| h.afflictions().contains(.enfeeble) else false;
}

fn blowOn(weak: bool, bonus: i32, s: *shock.Shock, dmg: i32, applied: ?resilience.Kind) i32 {
    const weakened = enfeeble.weaken(weak, mathx.percentCeil(dmg, mathx.PERCENT + bonus));
    return if (applied == .shock) weakened else shock.spend(s, weakened);
}

fn opportune(sim: *const Simulation, a: *const actor.Actor) i32 {
    return if (a.slowed()) @max(0, sim.inventory.gear.sum(.opportunist)) else 0;
}

/// What `resolve` deals `target` past armour for a blow carrying `applied`, spending nothing.
pub fn dealt(sim: *const Simulation, target: *const actor.Actor, dmg: i32, applied: ?resilience.Kind) i32 {
    var s = target.shock;
    return blowOn(heroWeak(sim), opportune(sim, target), &s, dmg, applied);
}

pub fn foeRoll(rng: *mathx.Rng, attacker: terrain.Stats, defender: terrain.Stats, s: actor.Strike) ?i32 {
    if (attacker.misses(defender, rng)) return null;
    return s.roll(rng);
}

/// `rolled` before the target's resistance or armour, its guard, an enfeebled striker and its shock; `dealt` after.
pub const FoeBlow = struct { rolled: i32, dealt: i32 };

/// A foe's strike `s` on `target`; null when it misses.
pub fn foeBlow(sim: *Simulation, attacker: *const actor.Actor, target: *actor.Actor, s: actor.Strike, weak: bool) ?FoeBlow {
    const defended = sim.combatStats(target);
    const rolled = foeRoll(&sim.rng, sim.combatStats(attacker), defended, s) orelse return null;
    var dmg = if (s.element) |e| damage.resisted(rolled, defended.elements.get(e)) else attrs.armoured(defended.armour, rolled, &sim.rng);
    if (s.element == null and target.tactics.guard > 0) dmg = tactics.Guard.reduce(target.tactics.guard, dmg);
    if (target.tactics.bide > 0) dmg = tactics.Bide.reduce(sim.growth.ranks.get(.bide), dmg);
    const dealt_ = landed(weak, target, dmg);
    if (target.tactics.bide > 0) target.tactics.bided +|= dealt_;
    return .{ .rolled = rolled, .dealt = dealt_ };
}

pub const HeroStrike = union(enum) {
    blocked,
    dodged,
    hit: struct {
        damage: simulation.DamageResult,
        hp_before: i32,
        maximum_roll: bool,
        bled: ?[]const u8 = null,
        stunned: bool = false,
        chilled: bool = false,
    },
};

pub fn strikeHero(sim: *Simulation, attacker_id: actor.ActorId, strike: actor.Strike, weak: bool) HeroStrike {
    const hero = sim.heroActor().?;
    const attacker = sim.pool.get(attacker_id.value).?;
    if (sim.heroBlocks()) return .blocked;
    const blow = foeBlow(sim, attacker, hero, strike, weak) orelse return .dodged;
    const hp_before = hero.hp;
    const defended = sim.combatStats(hero);
    const harm = sim.resolveDamage(.fromInt(sim.hero), blow.dealt);
    var outcome = HeroStrike{ .hit = .{
        .damage = harm,
        .hp_before = hp_before,
        .maximum_roll = blow.rolled == strike.hit.hi,
    } };
    if (harm.lethal or harm.dmg <= 0) return outcome;
    if (sim.procStatus(hero, .bleed, strike.bleeds)) {
        outcome.hit.bled = hero.bleed.said();
        hero.bleed.start();
    }
    if (sim.procStatus(hero, .stun, strike.stuns)) {
        hero.clock.stun();
        outcome.hit.stunned = true;
    }
    const chill_chance = damage.resistedChance(strike.chills, defended.elements.get(glacial.ELEMENT));
    if (sim.procStatus(hero, glacial.AILMENT, chill_chance)) {
        hero.chill.apply();
        outcome.hit.chilled = true;
    }
    return outcome;
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

pub const IMBUED = .{ burning, glacial, shock };
pub const Imbued = std.EnumSet(resilience.Kind);

comptime {
    for (IMBUED, affixes.IMBUES) |M, e| std.debug.assert(M.AILMENT == affixes.imbued(e));
}

pub const Outcome = union(enum) { miss, hit: Hit };

pub fn resolve(sim: *Simulation, target: actor.ActorId, raw: Roll, origin: chronicle.AttackOrigin) ?Outcome {
    const a = sim.pool.get(target.value) orelse return null;
    if (!raw.hit_checked and !heroLands(sim, a, origin)) return .miss;
    const stats = sim.combatStats(a);
    var r = raw.against(stats.armour, &sim.rng).burnt(stats.elements);
    r.dmg = blowOn(heroWeak(sim), r.opportunity orelse opportune(sim, a), &a.shock, r.dmg, r.applied);
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
        inline for (IMBUED, affixes.IMBUES) |M, e| {
            const chance = damage.resistedChance(r.effect.chance(M.AILMENT), stats.elements.get(e));
            if (r.applied != M.AILMENT and sim.procStatus(a, M.AILMENT, chance)) {
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
        .recovery = if (h.dmg > 0) perks.life_on_hit + leeched(sim, h.dmg) + if (h.lethal and !a.raider) perks.life_on_kill else 0 else 0,
    } };
}

fn leeched(sim: *Simulation, dmg: i32) i32 {
    const share = sim.inventory.gear.leech();
    if (share == 0) return 0;
    return @intCast(mathx.percentRound(@as(i64, dmg) * share, &sim.rng));
}

pub const Chosen = struct { roll: Roll, takes: bool };

fn survives(sim: *const Simulation, a: *const actor.Actor, dmg: i32, ailment: resilience.Kind) bool {
    const d = dealt(sim, a, dmg, ailment);
    return d > 0 and d < a.hp;
}

pub fn chosenBlow(sim: *Simulation, target: *actor.Actor, raw: Roll, comptime act: skillbar.Act, through: bool, resist: i16) Chosen {
    const M = skillbar.Act.skill(act);
    const stats = sim.combatStats(target);
    var roll = raw.against(stats.armour, &sim.rng);
    roll.hit_checked = true;
    roll.opportunity = opportune(sim, target);
    var takes = false;
    if (comptime act.afflicts()) {
        const can_afflict = through and survives(sim, target, roll.burnt(stats.elements).dmg, M.AILMENT);
        takes = afflicted(sim, target, M, can_afflict, resist);
        if (takes) roll.applied = M.AILMENT;
    }
    return .{ .roll = roll, .takes = takes };
}

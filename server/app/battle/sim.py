"""Детерминированный бой 5 на 5 (вид сбоку, реальное время, фиксированный тик).

Одинаковые герои + расстановка + seed -> всегда одинаковый бой (используем только
random.Random(seed), порядок обхода фиксирован). Сервер считает бой, клиент
проигрывает журнал событий (log["events"]) анимацией.

Сторона 0 — атакующие (игрок), стоят слева (x < 0). Сторона 1 — защита, справа.
Все числа (урон, энергия, дальность) берутся из контента: config/battle.json, hero.json.
"""
from __future__ import annotations

import math
import random
from dataclasses import dataclass, field

LOG_VERSION = 1
FRONT_SLOTS = (0, 1)
BACK_SLOTS = (2, 3, 4)


class BattleError(Exception):
    pass


@dataclass
class Unit:
    uid: int
    side: int
    slot: int
    hero: dict
    x: float
    lane: float
    max_hp: int
    atk_base: float
    def_base: float
    interval_ms: int
    crit_chance: float
    crit_damage: float
    range: float
    speed: float
    windup_ticks: int
    projectile_speed: float
    targeting: str
    hp: int = 0
    energy: int = 0
    alive: bool = True
    stun_until: int = -1
    busy_until: int = -1
    next_attack: int = 0
    moving: bool = False
    target: "Unit | None" = None
    low_hp_fired: bool = False
    shields: list = field(default_factory=list)   # [amount, expire_tick]
    buffs: list = field(default_factory=list)     # [stat, percent, expire_tick]
    dots: list = field(default_factory=list)      # [src, per_tick_raw, next_tick, expire_tick]
    cooldowns: dict = field(default_factory=dict)  # skill_id -> tick
    stats: dict = field(default_factory=lambda: {"damage": 0, "taken": 0, "healing": 0, "shielded": 0})

    @property
    def faction(self) -> str:
        return self.hero["faction"]

    def buff_pct(self, stat: str) -> float:
        return sum(b[1] for b in self.buffs if b[0] == stat)

    def atk(self) -> float:
        return self.atk_base * max(0.1, 1 + self.buff_pct("atk") / 100)

    def defense(self) -> float:
        return self.def_base * max(0.0, 1 + self.buff_pct("def") / 100)

    def crit(self) -> float:
        return min(1.0, self.crit_chance + self.buff_pct("crit_chance") / 100)

    def interval_ticks(self, tick_rate: int) -> int:
        speed = max(0.2, 1 + self.buff_pct("attack_speed") / 100)
        return max(1, round(self.interval_ms / speed * tick_rate / 1000))

    def shield_total(self) -> int:
        return sum(s[0] for s in self.shields)


class Battle:
    def __init__(self, config: dict, factions: dict, heroes: dict, team_a: list, team_b: list, seed: int,
                 auto: tuple[bool, bool] = (True, True)):
        self.cfg = config
        self.factions = factions
        self.rng = random.Random(seed)
        self.seed = seed
        self.tick_rate = int(config["tick_rate"])
        self.max_ticks = int(config["max_duration_sec"]) * self.tick_rate
        self.t = 0
        self.events: list[dict] = []
        self.pending: list[tuple] = []  # (tick, seq, kind, payload)
        self._seq = 0
        self.auto = list(auto)
        self.ult_requests: set[int] = set()
        self.winner: int | None = None
        self._snap: dict[int, float] = {}
        self._moves: list = []
        self.units: list[Unit] = []
        for side, team in ((0, team_a), (1, team_b)):
            slots = set()
            for entry in team:
                if entry["slot"] in slots:
                    raise BattleError(f"Слот {entry['slot']} занят дважды")
                slots.add(entry["slot"])
                hero = heroes.get(entry["hero"])
                if hero is None:
                    raise BattleError(f"Неизвестный герой «{entry['hero']}»")
                if hero["faction"] not in factions:
                    raise BattleError(f"У героя {hero['id']} неизвестная фракция {hero['faction']}")
                self.units.append(self._make_unit(len(self.units), side, entry, hero))
        if not any(u.side == 0 for u in self.units) or not any(u.side == 1 for u in self.units):
            raise BattleError("В каждом отряде должен быть хотя бы один герой")
        self._start()

    # --- Создание ---------------------------------------------------------------

    def _make_unit(self, uid: int, side: int, entry: dict, hero: dict) -> Unit:
        st = hero["stats"]
        role = self.cfg["roles"].get(hero["role"], {})
        dmg = self.cfg["damage"]
        field_cfg = self.cfg["field"]
        mult = float(entry.get("stat_multiplier", 1.0))
        dist = field_cfg["front_x"] if entry["slot"] in FRONT_SLOTS else field_cfg["back_x"]
        u = Unit(
            uid=uid, side=side, slot=entry["slot"], hero=hero,
            x=-dist if side == 0 else dist, lane=field_cfg["lanes"][entry["slot"]],
            max_hp=round(st["hp"] * mult), atk_base=st["atk"] * mult, def_base=st["def"] * mult,
            interval_ms=st["attack_interval_ms"],
            crit_chance=st.get("crit_chance", dmg["crit_chance"]), crit_damage=st.get("crit_damage", dmg["crit_damage"]),
            range=st.get("range", role.get("range", 1.5)), speed=st.get("move_speed", role.get("move_speed", 1.5)),
            windup_ticks=max(1, round(role.get("attack_windup_ms", 350) * self.tick_rate / 1000)),
            projectile_speed=float(role.get("projectile_speed", 0)),
            targeting=role.get("targeting", "nearest"),
        )
        u.hp = u.max_hp
        u.energy = int(self.cfg["energy"].get("start", 0))
        for s in hero["skills"]:
            if s["type"] == "active":
                u.cooldowns[s["id"]] = self._ms(s.get("first_cast_ms", s.get("cooldown_ms", 5000)))
        return u

    def _ms(self, ms: float) -> int:
        return max(0, round(ms * self.tick_rate / 1000))

    def _start(self) -> None:
        # Пассивки «в начале боя» (постоянные характеристики, энергия)
        for u in self.units:
            for s in u.hero["skills"]:
                if s["type"] == "passive" and s.get("trigger", "battle_start") == "battle_start":
                    self._apply_effects(u, s, permanent=True)
        for u in self.units:
            u.hp = u.max_hp  # после бонусов к здоровью

    # --- Публичное API ------------------------------------------------------------

    def request_ult(self, uid: int) -> None:
        """Ручной ультимейт (кнопка в клиенте, режим «Авто» выключен)."""
        self.ult_requests.add(uid)

    def set_auto(self, side: int, value: bool) -> None:
        self.auto[side] = value
        self._emit("auto", side=side, on=value)

    @property
    def finished(self) -> bool:
        return self.winner is not None

    def run(self) -> dict:
        while not self.finished:
            self.step()
        return self.log()

    def step(self) -> None:
        if self.finished:
            return
        t = self.t
        self._process_pending(t)
        self._tick_effects(t)
        # Решения всех бойцов принимаются по позициям на начало тика, а движения
        # применяются одновременно в конце — иначе тот, кто ходит первым, получал бы фору.
        self._snap = {u.uid: u.x for u in self.units}
        self._moves = []
        order = list(self.units)
        self.rng.shuffle(order)
        for u in order:
            if u.alive and not self.finished:
                self._act(u, t)
        for u, dx in self._moves:
            if u.alive and u.moving:
                u.x += dx
        self._snap = {}
        self._check_end()
        if not self.finished and t + 1 >= self.max_ticks:
            self.t = t + 1
            self._finish(1)  # время вышло — победа защиты
            return
        self.t = t + 1

    def log(self) -> dict:
        return {
            "version": LOG_VERSION,
            "seed": self.seed,
            "tick_rate": self.tick_rate,
            "max_ticks": self.max_ticks,
            "energy_max": int(self.cfg["energy"]["max"]),
            "field": self.cfg["field"],
            "units": [self._unit_public(u) for u in self.units_initial],
            "events": self.events,
            "result": {
                "winner": self.winner,
                "ticks": self.t,
                "survivors": [u.uid for u in self.units if u.alive],
                "stats": [{"uid": u.uid, **u.stats} for u in self.units],
            },
        }

    # --- Внутреннее ---------------------------------------------------------------

    @property
    def units_initial(self):
        return self.units

    def _unit_public(self, u: Unit) -> dict:
        start_x = (-1 if u.side == 0 else 1) * (self.cfg["field"]["front_x"] if u.slot in FRONT_SLOTS else self.cfg["field"]["back_x"])
        return {"uid": u.uid, "side": u.side, "slot": u.slot, "hero": u.hero["id"], "name": u.hero["name"],
                "faction": u.faction, "role": u.hero["role"], "x": start_x, "lane": u.lane,
                "max_hp": u.max_hp, "energy": int(self.cfg["energy"].get("start", 0)),
                "skills": [{"id": s["id"], "type": s["type"], "name": s["name"]} for s in u.hero["skills"]]}

    def _emit(self, event_name: str, /, **data) -> None:
        self.events.append({"t": self.t, "e": event_name, **data})

    def _schedule(self, tick: int, kind: str, payload: dict) -> None:
        self._seq += 1
        self.pending.append((tick, self._seq, kind, payload))

    def _process_pending(self, t: int) -> None:
        due = sorted([p for p in self.pending if p[0] <= t], key=lambda p: (p[0], p[1]))
        if not due:
            return
        # Одновременные события тика — в случайном (но воспроизводимом по seed) порядке,
        # чтобы ни у одной стороны не было систематического преимущества.
        if len(due) > 1:
            self.rng.shuffle(due)
        self.pending = [p for p in self.pending if p[0] > t]
        # Всё, что приходится на один тик, срабатывает одновременно: удар бойца,
        # погибшего в этот же тик, тоже доходит (иначе выигрывал бы тот, кто «ходил первым»).
        alive_at_start = {u.uid for u in self.units if u.alive}
        for _, _, kind, p in due:
            src = p["src"]
            if src.uid not in alive_at_start:
                continue
            if kind == "attack_hit":
                tgt = p["target"]
                if tgt.alive:
                    self._damage(src, tgt, 1.0, "attack", can_crit=True)
                if src.alive:
                    self._gain_energy(src, int(self.cfg["energy"]["on_attack"]))
            elif kind == "skill_impact":
                self._apply_effects(src, p["skill"])
                if p["skill"]["type"] == "active":
                    self._gain_energy(src, int(self.cfg["energy"].get("on_skill", 0)))

    def _tick_effects(self, t: int) -> None:
        for u in self.units:
            if not u.alive:
                continue
            expired = [b for b in u.buffs if b[2] <= t]
            if expired:
                u.buffs = [b for b in u.buffs if b[2] > t]
                for b in expired:
                    self._emit("buff_end", u=u.uid, stat=b[0])
            if u.shields and any(s[1] <= t for s in u.shields):
                u.shields = [s for s in u.shields if s[1] > t]
                self._emit("shield", u=u.uid, value=u.shield_total())
            for d in list(u.dots):
                if d[2] <= t and d[3] >= t:
                    d[2] = t + self.tick_rate
                    self._damage(d[0], u, d[1], "dot", can_crit=False)
                    if not u.alive:
                        break
            u.dots = [d for d in u.dots if d[3] > t]

    def _enemies(self, u: Unit) -> list[Unit]:
        return [o for o in self.units if o.alive and o.side != u.side]

    def _allies(self, u: Unit) -> list[Unit]:
        return [o for o in self.units if o.alive and o.side == u.side]

    def _dist(self, a: Unit, b: Unit) -> float:
        snap = self._snap
        return abs(snap.get(a.uid, a.x) - snap.get(b.uid, b.x))

    def _pick_target(self, u: Unit) -> Unit | None:
        enemies = self._enemies(u)
        if not enemies:
            return None
        if u.targeting == "backline":
            back = [e for e in enemies if e.slot in BACK_SLOTS]
            pool = back or enemies
            return min(pool, key=lambda e: (e.hp / e.max_hp, e.uid))
        if u.targeting == "lowest_hp":
            return min(enemies, key=lambda e: (e.hp / e.max_hp, e.uid))
        if u.targeting == "frontline":
            front = [e for e in enemies if e.slot in FRONT_SLOTS] or enemies
            return min(front, key=lambda e: (self._dist(u, e), e.uid))
        return min(enemies, key=lambda e: (self._dist(u, e), e.slot, e.uid))

    def _act(self, u: Unit, t: int) -> None:
        if t < u.stun_until or t < u.busy_until:
            if u.moving:
                u.moving = False
                self._emit("stop", u=u.uid, x=round(u.x, 3))
            return
        # 1. Ультимейт
        emax = int(self.cfg["energy"]["max"])
        if u.energy >= emax and (self.auto[u.side] or u.uid in self.ult_requests):
            ult = next((s for s in u.hero["skills"] if s["type"] == "ultimate"), None)
            if ult:
                self.ult_requests.discard(u.uid)
                u.energy = 0
                self._emit("energy", u=u.uid, value=0)
                self._cast(u, ult, t)
                return
        # 2. Цель
        if u.target is None or not u.target.alive or u.targeting == "lowest_hp":
            u.target = self._pick_target(u)
        elif u.targeting in ("nearest", "frontline") and u.range <= 2.5:
            # Бойцы ближнего боя переключаются на заметно более близкого врага
            # (например, на убийцу, прорвавшегося мимо них); стрелки и маги держат цель.
            cand = self._pick_target(u)
            if cand is not None and cand is not u.target and \
                    self._dist(u, cand) + 0.75 < self._dist(u, u.target):
                u.target = cand
        if u.target is None:
            return
        in_range = self._dist(u, u.target) <= u.range + 1e-6
        # 3. Активный навык (по перезарядке, когда цель в досягаемости)
        if in_range:
            for s in u.hero["skills"]:
                if s["type"] == "active" and t >= u.cooldowns.get(s["id"], 0):
                    u.cooldowns[s["id"]] = t + self._ms(s.get("cooldown_ms", 8000))
                    self._cast(u, s, t)
                    return
        # 4. Обычная атака или движение
        if in_range:
            if u.moving:
                u.moving = False
                self._emit("stop", u=u.uid, x=round(u.x, 3))
            if t >= u.next_attack:
                u.next_attack = t + u.interval_ticks(self.tick_rate)
                u.busy_until = t + u.windup_ticks
                tgt = u.target
                if u.projectile_speed > 0:
                    travel = max(1, round(self._dist(u, tgt) / u.projectile_speed * self.tick_rate))
                    self._emit("attack", u=u.uid, target=tgt.uid, projectile=True,
                               hit_t=t + u.windup_ticks + travel)
                    self._schedule(t + u.windup_ticks + travel, "attack_hit", {"src": u, "target": tgt})
                else:
                    self._emit("attack", u=u.uid, target=tgt.uid, projectile=False, hit_t=t + u.windup_ticks)
                    self._schedule(t + u.windup_ticks, "attack_hit", {"src": u, "target": tgt})
        else:
            step = u.speed / self.tick_rate
            direction = 1 if u.target.x > u.x else -1
            gap = self._dist(u, u.target) - u.range
            move = min(step, max(0.0, gap))
            if not u.moving:
                u.moving = True
                self._emit("move", u=u.uid, x=round(u.x, 3), vx=round(direction * u.speed, 3))
            self._moves.append((u, direction * move))

    def _cast(self, u: Unit, skill: dict, t: int) -> None:
        if u.moving:
            u.moving = False
            self._emit("stop", u=u.uid, x=round(u.x, 3))
        cast = self._ms(skill.get("cast_time_ms", 500))
        u.busy_until = t + cast
        u.next_attack = max(u.next_attack, t + cast)
        self._emit("cast", u=u.uid, skill=skill["id"], kind=skill["type"],
                   anim=skill.get("animation", "skill"), impact_t=t + cast)
        self._schedule(t + cast, "skill_impact", {"src": u, "skill": skill})

    # --- Эффекты ------------------------------------------------------------------

    def _select(self, u: Unit, target: dict) -> list[Unit]:
        pool = self._enemies(u) if target["side"] == "enemy" else self._allies(u)
        if not pool:
            return []
        sel = target["select"]
        n = int(target.get("count", 1))
        by_dist = sorted(pool, key=lambda o: (self._dist(u, o), o.slot, o.uid))
        if sel == "self":
            return [u] if u.alive else []
        if sel == "all":
            return sorted(pool, key=lambda o: o.uid)
        if sel == "current":
            if target["side"] == "enemy" and u.target is not None and u.target.alive:
                return [u.target]
            return by_dist[:1]
        if sel == "nearest":
            return by_dist[:n]
        if sel == "farthest":
            return list(reversed(by_dist))[:n]
        if sel == "lowest_hp":
            return sorted(pool, key=lambda o: (o.hp / o.max_hp, o.uid))[:n]
        if sel == "highest_atk":
            return sorted(pool, key=lambda o: (-o.atk(), o.uid))[:n]
        if sel == "frontline":
            front = [o for o in by_dist if o.slot in FRONT_SLOTS] or by_dist
            return front[:n]
        if sel == "backline":
            back = [o for o in pool if o.slot in BACK_SLOTS] or pool
            return sorted(back, key=lambda o: (o.hp / o.max_hp, o.uid))[:n]
        if sel == "random":
            ordered = sorted(pool, key=lambda o: o.uid)
            return self.rng.sample(ordered, min(n, len(ordered)))
        return by_dist[:n]

    def _apply_effects(self, u: Unit, skill: dict, permanent: bool = False) -> None:
        targets_hit = []
        for eff in skill["effects"]:
            targets = self._select(u, eff.get("target", {"side": "enemy", "select": "current"}))
            kind = eff["kind"]
            chance = eff.get("chance", 1.0)
            for tg in targets:
                if chance < 1.0 and self.rng.random() >= chance:
                    continue
                targets_hit.append(tg.uid)
                if kind == "damage":
                    self._damage(u, tg, eff.get("multiplier", 1.0), "skill", can_crit=True, skill_id=skill["id"])
                elif kind == "heal":
                    self._heal(u, tg, eff.get("multiplier", 1.0))
                elif kind == "shield":
                    amount = round(u.atk() * eff.get("multiplier", 1.0))
                    tg.shields.append([amount, self.t + self._ms(eff.get("duration_ms", 5000))])
                    u.stats["shielded"] += amount
                    self._emit("shield", u=tg.uid, value=tg.shield_total(), src=u.uid)
                elif kind == "stun":
                    tg.stun_until = max(tg.stun_until, self.t + self._ms(eff.get("duration_ms", 1000)))
                    self._emit("stun", u=tg.uid, until=tg.stun_until, src=u.uid)
                elif kind == "buff":
                    stat, pct = eff.get("stat", "atk"), eff.get("percent", 0)
                    tg.buffs.append([stat, pct, self.t + self._ms(eff.get("duration_ms", 5000))])
                    self._emit("buff", u=tg.uid, stat=stat, percent=pct, until=tg.buffs[-1][2], src=u.uid)
                elif kind == "dot":
                    expire = self.t + self._ms(eff.get("duration_ms", 3000))
                    tg.dots.append([u, eff.get("multiplier", 0.2), self.t + self.tick_rate, expire])
                    self._emit("dot", u=tg.uid, until=expire, src=u.uid)
                elif kind == "energy":
                    self._gain_energy(tg, int(eff.get("amount", 0)))
                elif kind == "stat":
                    stat, pct = eff.get("stat", "atk"), eff.get("percent", 0) / 100
                    if stat == "hp":
                        tg.max_hp = round(tg.max_hp * (1 + pct))
                        tg.hp = tg.max_hp
                    elif stat == "atk":
                        tg.atk_base *= 1 + pct
                    elif stat == "def":
                        tg.def_base *= 1 + pct
                    elif stat == "crit_chance":
                        tg.crit_chance += eff.get("percent", 0) / 100
                    elif stat == "attack_speed":
                        tg.interval_ms = max(200, round(tg.interval_ms / (1 + pct)))
        if not permanent:
            self._emit("impact", u=u.uid, skill=skill["id"], targets=sorted(set(targets_hit)))

    def _damage(self, src: Unit, tgt: Unit, mult: float, kind: str, can_crit: bool, skill_id: str | None = None) -> None:
        d = self.cfg["damage"]
        raw = src.atk() * mult
        var = d.get("variance", 0)
        if var:
            raw *= 1 + self.rng.uniform(-var, var)
        crit = can_crit and self.rng.random() < src.crit()
        if crit:
            raw *= src.crit_damage
        if tgt.faction in self.factions.get(src.faction, {}).get("strong_against", []):
            raw *= 1 + d["faction_bonus"]
        de = tgt.defense()
        reduction = min(d.get("max_reduction", 0.8), de / (de + d["defense_constant"]))
        amount = max(int(d.get("min_damage", 1)), round(raw * (1 - reduction)))
        absorbed = 0
        while tgt.shields and amount > absorbed:
            s = tgt.shields[0]
            take = min(s[0], amount - absorbed)
            s[0] -= take
            absorbed += take
            if s[0] <= 0:
                tgt.shields.pop(0)
        to_hp = amount - absorbed
        tgt.hp = max(0, tgt.hp - to_hp)
        src.stats["damage"] += amount
        tgt.stats["taken"] += amount
        ev = {"src": src.uid, "u": tgt.uid, "amount": amount, "hp": tgt.hp, "kind": kind}
        if crit:
            ev["crit"] = True
        if absorbed:
            ev["absorbed"] = absorbed
            ev["shield"] = tgt.shield_total()
        if skill_id:
            ev["skill"] = skill_id
        self._emit("damage", **ev)
        if tgt.hp > 0 and to_hp > 0:
            gain = round(to_hp / tgt.max_hp * 100 * self.cfg["energy"]["on_hit_per_hp_percent"])
            self._gain_energy(tgt, gain)
        if tgt.hp <= 0:
            self._kill(src, tgt)
        elif not tgt.low_hp_fired and tgt.hp < tgt.max_hp * 0.3:
            tgt.low_hp_fired = True
            for s in tgt.hero["skills"]:
                if s["type"] == "passive" and s.get("trigger") == "low_hp":
                    self._emit("passive", u=tgt.uid, skill=s["id"])
                    self._apply_effects(tgt, s)

    def _heal(self, src: Unit, tgt: Unit, mult: float) -> None:
        amount = round(src.atk() * mult)
        real = min(amount, tgt.max_hp - tgt.hp)
        tgt.hp += real
        src.stats["healing"] += real
        self._emit("heal", src=src.uid, u=tgt.uid, amount=real, hp=tgt.hp)

    def _gain_energy(self, u: Unit, amount: int) -> None:
        if not u.alive or amount == 0:
            return
        emax = int(self.cfg["energy"]["max"])
        new = max(0, min(emax, u.energy + amount))
        if new != u.energy:
            u.energy = new
            self._emit("energy", u=u.uid, value=new)

    def _kill(self, src: Unit, tgt: Unit) -> None:
        tgt.alive = False
        tgt.moving = False
        tgt.shields.clear()
        tgt.dots.clear()
        tgt.buffs.clear()
        self.pending = [p for p in self.pending if p[3]["src"] is not tgt]
        self._emit("death", u=tgt.uid, src=src.uid)
        if src.alive and src is not tgt:
            self._gain_energy(src, int(self.cfg["energy"]["on_kill"]))
            for s in src.hero["skills"]:
                if s["type"] == "passive" and s.get("trigger") == "kill":
                    self._emit("passive", u=src.uid, skill=s["id"])
                    self._apply_effects(src, s)

    def _check_end(self) -> None:
        alive = {u.side for u in self.units if u.alive}
        if alive == {0}:
            self._finish(0)
        elif alive == {1}:
            self._finish(1)
        elif not alive:
            self._finish(1)

    def _finish(self, winner: int) -> None:
        if self.winner is None:
            self.winner = winner
            self._emit("end", winner=winner)
            for u in self.units:
                if u.alive and u.side == winner:
                    self._emit("victory", u=u.uid)


def simulate(config: dict, factions: dict, heroes: dict, team_a: list, team_b: list, seed: int) -> dict:
    return Battle(config, factions, heroes, team_a, team_b, seed).run()

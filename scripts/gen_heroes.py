#!/usr/bin/env python3
"""Генератор стартового контента этапа 3: 19 героев-заглушек (6 фракций), фракции, формулы боя, тестовые отряды.

Рисует части тела в PNG (единый мультяшный стиль, цвета фракций), собирает skeleton.json
с анимациями idle/attack/skill/ultimate/hit/death/victory, портрет и полный арт.
Позже всё это заменяется ИИ-артом через админку/ZIP-патчи — формат файлов тот же.

Нужен Pillow:  pip install Pillow
Запуск из корня репозитория:  python3 scripts/gen_heroes.py
"""
from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1] / "content"
S = 2  # рисуем в 2x и уменьшаем — сглаживание краёв

# ---------------------------------------------------------------------------
# Фракции и круг преимуществ: батыры -> нечисть -> духи -> кочевники -> батыры
# ---------------------------------------------------------------------------
FACTIONS = [
    {"id": "ural_batyrs", "name": "Батыры Урала", "color": "#D9A441", "strong_against": ["evil_spirits"],
     "description": "Богатыри уральских гор, защитники людей и живой воды."},
    {"id": "evil_spirits", "name": "Нечисть", "color": "#8E3B5B", "strong_against": ["forest_spirits"],
     "description": "Албасты, дивы и змеи — порождения тьмы и смерти."},
    {"id": "forest_spirits", "name": "Лесные духи", "color": "#4F9D69", "strong_against": ["steppe_nomads"],
     "description": "Шурале, водяные девы и хозяева лесов."},
    {"id": "steppe_nomads", "name": "Степные кочевники", "color": "#C9693B", "strong_against": ["ural_batyrs"],
     "description": "Вольные всадники, лучники и шаманы бескрайней степи."},
    # Две отдельные фракции (как Небожители и Гипогеи в AFK Arena):
    # +25% урона друг другу, с четырьмя основными фракциями — нейтральны.
    {"id": "sky_dwellers", "name": "Небожители", "color": "#7FB8E8", "strong_against": ["underworld"],
     "description": "Царь птиц Самрау и его небесный род — свет над Уралом."},
    {"id": "underworld", "name": "Подземное царство", "color": "#5B3A8C", "strong_against": ["sky_dwellers"],
     "description": "Владения Катил-падиши и змеиного царя — мрак под горами."},
]
FCOLOR = {f["id"]: f["color"] for f in FACTIONS}

BATTLE = {
    "tick_rate": 20,
    "max_duration_sec": 90,
    "energy": {"max": 1000, "start": 0, "on_attack": 100, "on_hit_per_hp_percent": 10, "on_kill": 300, "on_skill": 50},
    "damage": {"defense_constant": 600, "max_reduction": 0.75, "faction_bonus": 0.25,
               "crit_chance": 0.05, "crit_damage": 1.5, "variance": 0.05, "min_damage": 1},
    "field": {"front_x": 2.0, "back_x": 5.0, "lanes": [0.35, 0.75, 0.15, 0.55, 0.95]},
    "roles": {
        "tank":     {"range": 1.5, "move_speed": 1.6, "attack_windup_ms": 350, "projectile_speed": 0, "targeting": "nearest"},
        "warrior":  {"range": 1.5, "move_speed": 1.8, "attack_windup_ms": 350, "projectile_speed": 0, "targeting": "nearest"},
        "assassin": {"range": 1.5, "move_speed": 3.0, "attack_windup_ms": 300, "projectile_speed": 0, "targeting": "backline"},
        "archer":   {"range": 9.0, "move_speed": 1.2, "attack_windup_ms": 400, "projectile_speed": 16, "targeting": "nearest"},
        "mage":     {"range": 9.0, "move_speed": 1.2, "attack_windup_ms": 400, "projectile_speed": 11, "targeting": "nearest"},
        "support":  {"range": 9.0, "move_speed": 1.2, "attack_windup_ms": 400, "projectile_speed": 11, "targeting": "nearest"},
    },
}

HP_SCALE = 1.8  # баланс длительности боя (~25-35 с)
BASE_STATS = {
    "tank":     {"hp": 3400, "atk": 120, "def": 180, "attack_interval_ms": 1400},
    "warrior":  {"hp": 2500, "atk": 200, "def": 110, "attack_interval_ms": 1100},
    "assassin": {"hp": 1800, "atk": 235, "def": 80, "attack_interval_ms": 900, "crit_chance": 0.15},
    "archer":   {"hp": 1600, "atk": 225, "def": 70, "attack_interval_ms": 1200, "crit_chance": 0.10},
    "mage":     {"hp": 1500, "atk": 250, "def": 60, "attack_interval_ms": 1500},
    "support":  {"hp": 1750, "atk": 140, "def": 85, "attack_interval_ms": 1400},
}


def T(side, select, count=None):
    t = {"side": side, "select": select}
    if count:
        t["count"] = count
    return t


def dmg(target, mult):
    return {"kind": "damage", "target": target, "multiplier": mult}


def ult(sid, name, desc, effects, cast=900):
    return {"id": sid, "name": name, "description": desc, "type": "ultimate", "cast_time_ms": cast,
            "animation": "ultimate", "effects": effects}


def active(sid, name, desc, effects, cd, first, cast=500):
    return {"id": sid, "name": name, "description": desc, "type": "active", "cooldown_ms": cd,
            "first_cast_ms": first, "cast_time_ms": cast, "animation": "skill", "effects": effects}


def passive(sid, name, desc, effects, trigger="battle_start"):
    return {"id": sid, "name": name, "description": desc, "type": "passive", "trigger": trigger, "effects": effects}


# ---------------------------------------------------------------------------
# Герои. look: skin — цвет кожи, cloth — одежда (по умолчанию цвет фракции), acc — украшение
# ---------------------------------------------------------------------------
HEROES = [
    # --- Батыры Урала ---
    dict(id="ural_batyr", name="Урал-батыр", title="Сын Янбирде", faction="ural_batyrs", role="warrior",
         description="Легендарный богатырь, добывший живую воду ради людей.",
         lore="Урал-батыр отправился в путь, чтобы победить смерть. Он одолел дивов и змеев, а живую воду не выпил сам, а окропил ею землю — и встали горы, что носят его имя.",
         look=dict(skin="#F1C79B", hair="#3A2414", acc="helmet"),
         skills=[ult("ural_ult", "Удар горного хребта", "Сокрушает всех врагов перед собой: 220% атаки по переднему ряду и оглушение на 1,5 с.",
                     [dmg(T("enemy", "frontline", 2), 2.2), {"kind": "stun", "target": T("enemy", "frontline", 2), "duration_ms": 1500}]),
                 active("ural_s1", "Рассекающий удар", "Бьёт текущую цель на 180% атаки.", [dmg(T("enemy", "current"), 1.8)], 7000, 3000),
                 active("ural_s2", "Клич батыра", "Повышает атаку союзников на 15% на 6 с.",
                        [{"kind": "buff", "target": T("ally", "all"), "stat": "atk", "percent": 15, "duration_ms": 6000}], 14000, 6000),
                 passive("ural_p", "Сила живой воды", "При падении здоровья ниже 30% восстанавливает 25% здоровья (1 раз).",
                         [{"kind": "heal", "target": T("ally", "self"), "multiplier": 3.0}], "low_hp")]),
    dict(id="alpamysha", name="Алпамыша", title="Несокрушимый", faction="ural_batyrs", role="tank",
         description="Богатырь-исполин, принимающий удары за друзей.",
         lore="Алпамыша прошёл через плен и испытания, но ни разу не опустил щит. Говорят, его щит выкован из камня самой высокой вершины.",
         look=dict(skin="#E8B98A", hair="#5A3A1E", acc="helmet"),
         skills=[ult("alp_ult", "Каменная стена", "Даёт себе щит на 400% атаки и оглушает ближайших врагов на 2 с.",
                     [{"kind": "shield", "target": T("ally", "self"), "multiplier": 4.0, "duration_ms": 8000},
                      {"kind": "stun", "target": T("enemy", "nearest", 2), "duration_ms": 2000}]),
                 active("alp_s1", "Удар щитом", "Бьёт цель на 140% атаки и оглушает на 1 с.",
                        [dmg(T("enemy", "current"), 1.4), {"kind": "stun", "target": T("enemy", "current"), "duration_ms": 1000}], 8000, 4000),
                 active("alp_s2", "Твердыня", "Повышает защиту на 30% на 6 с.",
                        [{"kind": "buff", "target": T("ally", "self"), "stat": "def", "percent": 30, "duration_ms": 6000}], 12000, 2000),
                 passive("alp_p", "Кровь великанов", "Здоровье +15%.", [{"kind": "stat", "target": T("ally", "self"), "stat": "hp", "percent": 15}])]),
    dict(id="zayatulyak", name="Заятуляк", title="Стрелок озёрный", faction="ural_batyrs", role="archer",
         description="Меткий охотник, полюбивший водяную деву.",
         lore="Заятуляк подстрелил белую утку, а она обернулась девой Хыухылу. С тех пор его стрелы не знают промаха — их ведёт озёрная вода.",
         look=dict(skin="#F0C090", hair="#2B1B10", acc="feather"),
         skills=[ult("zay_ult", "Дождь стрел", "Обстреливает всех врагов: 150% атаки каждому.", [dmg(T("enemy", "all"), 1.5)]),
                 active("zay_s1", "Прицельный выстрел", "Бьёт врага с наименьшим здоровьем на 220% атаки.", [dmg(T("enemy", "lowest_hp"), 2.2)], 8000, 3500),
                 active("zay_s2", "Двойная стрела", "Две стрелы по 110% атаки в случайных врагов.", [dmg(T("enemy", "random", 2), 1.1)], 6000, 5000),
                 passive("zay_p", "Глаз охотника", "Шанс крита +10%.", [{"kind": "stat", "target": T("ally", "self"), "stat": "crit_chance", "percent": 10}])]),
    dict(id="humai", name="Хумай", title="Дева-птица", faction="ural_batyrs", role="support",
         description="Дочь царя птиц Самрау, исцеляющая раны.",
         lore="Хумай может обернуться белой лебедью. Урал-батыр спас её, и с тех пор её крылья укрывают батыров в бою.",
         look=dict(skin="#F6D7B5", hair="#F4ECDD", acc="wings"),
         skills=[ult("humai_ult", "Крылья Самрау", "Лечит всех союзников на 250% атаки и даёт +20% защиты на 5 с.",
                     [{"kind": "heal", "target": T("ally", "all"), "multiplier": 2.5},
                      {"kind": "buff", "target": T("ally", "all"), "stat": "def", "percent": 20, "duration_ms": 5000}]),
                 active("humai_s1", "Перо исцеления", "Лечит самого раненого союзника на 300% атаки.",
                        [{"kind": "heal", "target": T("ally", "lowest_hp"), "multiplier": 3.0}], 7000, 4000),
                 active("humai_s2", "Лебяжий щит", "Щит на 200% атаки самому раненому союзнику.",
                        [{"kind": "shield", "target": T("ally", "lowest_hp"), "multiplier": 2.0, "duration_ms": 6000}], 11000, 7000),
                 passive("humai_p", "Небесная песнь", "В начале боя союзники получают 200 энергии.",
                         [{"kind": "energy", "target": T("ally", "all"), "amount": 200}])]),
    # --- Лесные духи ---
    dict(id="shurale", name="Шурале", title="Лесной щекотун", faction="forest_spirits", role="assassin",
         description="Длиннопалый дух леса, нападающий из чащи.",
         lore="Шурале заманивает путников в глушь и щекочет до смерти. Он быстр, как ветер в соснах, и бьёт тех, кто прячется позади.",
         look=dict(skin="#8FB36A", hair="#3E5A2A", acc="horns"),
         skills=[ult("shu_ult", "Смертельная щекотка", "Бьёт врага в заднем ряду на 400% атаки.", [dmg(T("enemy", "backline"), 4.0)]),
                 active("shu_s1", "Удар из чащи", "Бьёт врага с наименьшим здоровьем на 200% атаки.", [dmg(T("enemy", "lowest_hp"), 2.0)], 6000, 2500),
                 active("shu_s2", "Колючие пальцы", "Яд: 40% атаки в секунду 4 с.",
                        [{"kind": "dot", "target": T("enemy", "current"), "multiplier": 0.4, "duration_ms": 4000}], 9000, 5000),
                 passive("shu_p", "Охота", "После убийства получает 300 энергии.", [{"kind": "energy", "target": T("ally", "self"), "amount": 300}], "kill")]),
    dict(id="hyuhylu", name="Хыухылу", title="Водяная дева", faction="forest_spirits", role="mage",
         description="Дочь водяного царя, повелевающая волнами.",
         lore="Хыухылу живёт в глубинах уральских озёр. Её песня зовёт воду — и вода сметает врагов.",
         look=dict(skin="#BFE3E8", hair="#3B7FA6", acc="fin"),
         skills=[ult("hyu_ult", "Волна озера", "Бьёт всех врагов на 170% атаки и снижает их атаку на 20% на 5 с.",
                     [dmg(T("enemy", "all"), 1.7), {"kind": "buff", "target": T("enemy", "all"), "stat": "atk", "percent": -20, "duration_ms": 5000}]),
                 active("hyu_s1", "Водяной шар", "Бьёт цель на 200% атаки.", [dmg(T("enemy", "current"), 2.0)], 6000, 3000),
                 active("hyu_s2", "Омут", "Оглушает самого сильного врага на 2 с.",
                        [{"kind": "stun", "target": T("enemy", "highest_atk"), "duration_ms": 2000}], 12000, 6000),
                 passive("hyu_p", "Глубина", "Атака +10%.", [{"kind": "stat", "target": T("ally", "self"), "stat": "atk", "percent": 10}])]),
    dict(id="urman_huzha", name="Урман-хужа", title="Хозяин леса", faction="forest_spirits", role="tank",
         description="Древний дух-хранитель, корни которого уходят в сердце Урала.",
         lore="Урман-хужа старше гор. Он просыпается, когда лесу грозит беда, и стоит стеной, как вековой дуб.",
         look=dict(skin="#9C7A55", hair="#4F7A3A", acc="antlers"),
         skills=[ult("urm_ult", "Корни земли", "Оглушает всех врагов на 1,5 с и бьёт на 100% атаки.",
                     [dmg(T("enemy", "all"), 1.0), {"kind": "stun", "target": T("enemy", "all"), "duration_ms": 1500}]),
                 active("urm_s1", "Кора", "Щит на 250% атаки себе.",
                        [{"kind": "shield", "target": T("ally", "self"), "multiplier": 2.5, "duration_ms": 6000}], 9000, 3000),
                 active("urm_s2", "Удар ветвью", "Бьёт ближайших 2 врагов на 130% атаки.", [dmg(T("enemy", "nearest", 2), 1.3)], 7000, 5000),
                 passive("urm_p", "Вековой дуб", "Защита +20%.", [{"kind": "stat", "target": T("ally", "self"), "stat": "def", "percent": 20}])]),
    dict(id="bisura", name="Бисура", title="Дух-хранитель", faction="forest_spirits", role="support",
         description="Маленький добрый дух, оберегающий дом и друзей.",
         lore="Бисура живёт за печью и в дуплах старых лип. Тем, кого любит, он дарит удачу, а врагов путает и усыпляет.",
         look=dict(skin="#D9C3A0", hair="#7A5A3A", acc="hood"),
         skills=[ult("bis_ult", "Оберег", "Щит всем союзникам на 180% атаки и +15% атаки на 6 с.",
                     [{"kind": "shield", "target": T("ally", "all"), "multiplier": 1.8, "duration_ms": 6000},
                      {"kind": "buff", "target": T("ally", "all"), "stat": "atk", "percent": 15, "duration_ms": 6000}]),
                 active("bis_s1", "Домашнее тепло", "Лечит двух самых раненых союзников на 180% атаки.",
                        [{"kind": "heal", "target": T("ally", "lowest_hp", 2), "multiplier": 1.8}], 7000, 4000),
                 active("bis_s2", "Морок", "Снижает защиту врага на 25% на 6 с.",
                        [{"kind": "buff", "target": T("enemy", "current"), "stat": "def", "percent": -25, "duration_ms": 6000}], 10000, 6000),
                 passive("bis_p", "Удача", "Шанс крита союзников +5%.",
                         [{"kind": "stat", "target": T("ally", "all"), "stat": "crit_chance", "percent": 5}])]),
    # --- Степные кочевники ---
    dict(id="kusyak_biy", name="Кусяк-бий", title="Вождь степи", faction="steppe_nomads", role="tank",
         description="Мудрый и суровый вождь, ведущий род сквозь бури.",
         lore="Кусяк-бий судил по совести и сражался в первых рядах. Его щит украшен знаками всех родов степи.",
         look=dict(skin="#D9A577", hair="#1E140C", acc="crown"),
         skills=[ult("kus_ult", "Знамя рода", "Щит себе на 300% атаки и +25% защиты союзникам на 6 с.",
                     [{"kind": "shield", "target": T("ally", "self"), "multiplier": 3.0, "duration_ms": 6000},
                      {"kind": "buff", "target": T("ally", "all"), "stat": "def", "percent": 25, "duration_ms": 6000}]),
                 active("kus_s1", "Таран", "Бьёт цель на 150% атаки и оглушает на 1 с.",
                        [dmg(T("enemy", "current"), 1.5), {"kind": "stun", "target": T("enemy", "current"), "duration_ms": 1000}], 9000, 3500),
                 active("kus_s2", "Закалка", "Восстанавливает себе 150% атаки здоровья.",
                        [{"kind": "heal", "target": T("ally", "self"), "multiplier": 1.5}], 8000, 6000),
                 passive("kus_p", "Слово вождя", "Здоровье союзников +5%.", [{"kind": "stat", "target": T("ally", "all"), "stat": "hp", "percent": 5}])]),
    dict(id="mergen", name="Мерген", title="Лучница степи", faction="steppe_nomads", role="archer",
         description="Всадница, попадающая в беркута на лету.",
         lore="Мерген — так в степи зовут лучших стрелков. Она взяла это имя, когда сбила стрелой коршуна, уносившего ягнёнка.",
         look=dict(skin="#E3B07E", hair="#24160D", acc="feather"),
         skills=[ult("mer_ult", "Стрела бури", "Бьёт врага в заднем ряду на 350% атаки и оглушает на 1 с.",
                     [dmg(T("enemy", "backline"), 3.5), {"kind": "stun", "target": T("enemy", "backline"), "duration_ms": 1000}]),
                 active("mer_s1", "Залп", "Три стрелы по 90% атаки в случайных врагов.", [dmg(T("enemy", "random", 3), 0.9)], 7000, 3000),
                 active("mer_s2", "Ветер степи", "Скорость атаки +30% на 5 с.",
                        [{"kind": "buff", "target": T("ally", "self"), "stat": "attack_speed", "percent": 30, "duration_ms": 5000}], 12000, 5000),
                 passive("mer_p", "Меткость", "Атака +8%, шанс крита +5%.",
                         [{"kind": "stat", "target": T("ally", "self"), "stat": "atk", "percent": 8},
                          {"kind": "stat", "target": T("ally", "self"), "stat": "crit_chance", "percent": 5}])]),
    dict(id="baksy", name="Баксы", title="Шаман", faction="steppe_nomads", role="mage",
         description="Шаман с бубном, говорящий с духами предков.",
         lore="Баксы бьёт в бубен — и духи предков отвечают ему огнём и бурей. Говорят, он видел вход в подземное царство.",
         look=dict(skin="#D6A070", hair="#3A2A1A", acc="feathers"),
         skills=[ult("bak_ult", "Камлание", "Огонь предков: 140% атаки всем врагам и горение 30% атаки в секунду 5 с.",
                     [dmg(T("enemy", "all"), 1.4), {"kind": "dot", "target": T("enemy", "all"), "multiplier": 0.3, "duration_ms": 5000}]),
                 active("bak_s1", "Удар бубна", "Бьёт двух ближайших врагов на 150% атаки.", [dmg(T("enemy", "nearest", 2), 1.5)], 7000, 3000),
                 active("bak_s2", "Зов предков", "Даёт 300 энергии союзнику с наибольшей атакой.",
                        [{"kind": "energy", "target": T("ally", "highest_atk"), "amount": 300}], 13000, 6000),
                 passive("bak_p", "Тайное знание", "Атака +12%.", [{"kind": "stat", "target": T("ally", "self"), "stat": "atk", "percent": 12}])]),
    # --- Нечисть ---
    dict(id="shulgen", name="Шульген", title="Падший брат", faction="evil_spirits", role="warrior",
         description="Брат Урала, выбравший сторону тьмы.",
         lore="Шульген выпил запретную кровь и встал на путь зла. Он сражается вместе с дивами, но в глубине души помнит брата.",
         look=dict(skin="#B9A2A8", hair="#1A0E14", acc="horns"),
         skills=[ult("shul_ult", "Проклятый клинок", "Бьёт текущую цель на 380% атаки и восстанавливает себе 150% атаки.",
                     [dmg(T("enemy", "current"), 3.8), {"kind": "heal", "target": T("ally", "self"), "multiplier": 1.5}]),
                 active("shul_s1", "Тёмный взмах", "Бьёт двух ближайших врагов на 140% атаки.", [dmg(T("enemy", "nearest", 2), 1.4)], 7000, 3000),
                 active("shul_s2", "Ярость", "Атака +25% на 5 с.",
                        [{"kind": "buff", "target": T("ally", "self"), "stat": "atk", "percent": 25, "duration_ms": 5000}], 13000, 4000),
                 passive("shul_p", "Запретная кровь", "При падении здоровья ниже 30% атака +30% до конца боя.",
                         [{"kind": "buff", "target": T("ally", "self"), "stat": "atk", "percent": 30, "duration_ms": 90000}], "low_hp")]),
    dict(id="albasty", name="Албасты", title="Ночная дева", faction="evil_spirits", role="assassin",
         description="Злой дух в облике женщины с длинными волосами.",
         lore="Албасты является в полночь и душит спящих. Её волосы — как чёрная река, а когти острее ножа.",
         look=dict(skin="#C7B8C9", hair="#120A14", acc="hood"),
         skills=[ult("alb_ult", "Полночь", "Бьёт врага с наименьшим здоровьем на 420% атаки.", [dmg(T("enemy", "lowest_hp"), 4.2)]),
                 active("alb_s1", "Когти", "Бьёт текущую цель на 170% атаки и отравляет: 30% атаки в секунду 3 с.",
                        [dmg(T("enemy", "current"), 1.7), {"kind": "dot", "target": T("enemy", "current"), "multiplier": 0.3, "duration_ms": 3000}], 6000, 2500),
                 active("alb_s2", "Удушье", "Оглушает врага в заднем ряду на 1,5 с.",
                        [{"kind": "stun", "target": T("enemy", "backline"), "duration_ms": 1500}], 11000, 5500),
                 passive("alb_p", "Жажда", "После убийства восстанавливает 200% атаки.",
                         [{"kind": "heal", "target": T("ally", "self"), "multiplier": 2.0}], "kill")]),
    dict(id="deyeu", name="Дейеу", title="Див", faction="evil_spirits", role="tank",
         description="Огромный див, слуга царя Катила.",
         lore="Дейеу — многоголовые дивы, которых Урал-батыр сбрасывал в море. Их шкура крепче камня.",
         look=dict(skin="#7D6A8C", hair="#2A1E33", acc="horns"),
         skills=[ult("dey_ult", "Рёв дива", "Оглушает ближайших 3 врагов на 2 с и даёт себе щит на 250% атаки.",
                     [{"kind": "stun", "target": T("enemy", "nearest", 3), "duration_ms": 2000},
                      {"kind": "shield", "target": T("ally", "self"), "multiplier": 2.5, "duration_ms": 6000}]),
                 active("dey_s1", "Сокрушение", "Бьёт цель на 160% атаки и снижает её защиту на 20% на 5 с.",
                        [dmg(T("enemy", "current"), 1.6), {"kind": "buff", "target": T("enemy", "current"), "stat": "def", "percent": -20, "duration_ms": 5000}], 8000, 3500),
                 active("dey_s2", "Каменная шкура", "Защита +35% на 6 с.",
                        [{"kind": "buff", "target": T("ally", "self"), "stat": "def", "percent": 35, "duration_ms": 6000}], 13000, 2000),
                 passive("dey_p", "Многоголовый", "Здоровье +20%.", [{"kind": "stat", "target": T("ally", "self"), "stat": "hp", "percent": 20}])]),
    dict(id="azhdaha", name="Аждаха", title="Змей", faction="evil_spirits", role="mage",
         description="Огнедышащий змей подземного царства.",
         lore="Аждаха стерёг подземные богатства и пожирал смельчаков. Его дыхание плавит камень.",
         look=dict(skin="#6E9E6E", hair="#2E4A2E", acc="tail"),
         skills=[ult("azh_ult", "Огненное дыхание", "Бьёт всех врагов на 190% атаки.", [dmg(T("enemy", "all"), 1.9)]),
                 active("azh_s1", "Пламя", "Бьёт цель на 160% атаки и поджигает: 35% атаки в секунду 4 с.",
                        [dmg(T("enemy", "current"), 1.6), {"kind": "dot", "target": T("enemy", "current"), "multiplier": 0.35, "duration_ms": 4000}], 7000, 3000),
                 active("azh_s2", "Чешуя", "Щит себе на 200% атаки.",
                        [{"kind": "shield", "target": T("ally", "self"), "multiplier": 2.0, "duration_ms": 6000}], 12000, 6000),
                 passive("azh_p", "Подземный жар", "Атака +10%.", [{"kind": "stat", "target": T("ally", "self"), "stat": "atk", "percent": 10}])]),
]

HEROES += [
    # --- Небожители ---
    dict(id="samrau", name="Самрау", title="Царь птиц", faction="sky_dwellers", role="mage",
         description="Владыка небес, отец Хумай.",
         lore="Самрау правит птицами и солнечным светом. Его дочери — Хумай и Айхылыу — несут свет солнца и луны.",
         look=dict(skin="#F6E3C0", hair="#F2B544", acc="halo"),
         skills=[ult("sam_ult", "Солнечный гнев", "Бьёт всех врагов на 220% атаки и снижает их защиту на 15% на 5 с.",
                     [dmg(T("enemy", "all"), 2.2), {"kind": "buff", "target": T("enemy", "all"), "stat": "def", "percent": -15, "duration_ms": 5000}]),
                 active("sam_s1", "Луч", "Бьёт врага с наибольшей атакой на 260% атаки.", [dmg(T("enemy", "highest_atk"), 2.6)], 7000, 3000),
                 active("sam_s2", "Взмах крыла", "Оглушает двух ближайших врагов на 1 с.",
                        [{"kind": "stun", "target": T("enemy", "nearest", 2), "duration_ms": 1000}], 12000, 6000),
                 passive("sam_p", "Небесная кровь", "Атака +12%, здоровье +8%.",
                         [{"kind": "stat", "target": T("ally", "self"), "stat": "atk", "percent": 12},
                          {"kind": "stat", "target": T("ally", "self"), "stat": "hp", "percent": 8}])]),
    dict(id="aihylu", name="Айхылыу", title="Лунная дева", faction="sky_dwellers", role="support",
         description="Дочь Самрау, хранительница лунного света.",
         lore="Айхылыу выходит на небо по ночам. Её свет возвращает силы раненым и не даёт тьме подойти близко.",
         look=dict(skin="#EDE6F6", hair="#C9D6F0", acc="halo"),
         skills=[ult("aih_ult", "Полнолуние", "Лечит всех союзников на 220% атаки и даёт щит на 120% атаки.",
                     [{"kind": "heal", "target": T("ally", "all"), "multiplier": 2.2},
                      {"kind": "shield", "target": T("ally", "all"), "multiplier": 1.2, "duration_ms": 6000}]),
                 active("aih_s1", "Лунный свет", "Лечит самого раненого союзника на 320% атаки.",
                        [{"kind": "heal", "target": T("ally", "lowest_hp"), "multiplier": 3.2}], 7000, 4000),
                 active("aih_s2", "Сон", "Оглушает врага с наибольшей атакой на 2 с.",
                        [{"kind": "stun", "target": T("enemy", "highest_atk"), "duration_ms": 2000}], 13000, 7000),
                 passive("aih_p", "Тихий свет", "В начале боя союзники получают щит на 100% атаки.",
                         [{"kind": "shield", "target": T("ally", "all"), "multiplier": 1.0, "duration_ms": 8000}])]),
    # --- Подземное царство ---
    dict(id="katil", name="Катил-падиша", title="Царь дивов", faction="underworld", role="warrior",
         description="Владыка подземного царства, враг Урал-батыра.",
         lore="Катил-падиша приносил людей в жертву и держал в страхе всю землю. Его трон стоит в пещере, где не бывает света.",
         look=dict(skin="#8C6F8F", hair="#1A0E1E", acc="crown"),
         skills=[ult("kat_ult", "Жертвоприношение", "Бьёт двух ближайших врагов на 210% атаки и лечит себя на 150% атаки.",
                     [dmg(T("enemy", "nearest", 2), 2.1), {"kind": "heal", "target": T("ally", "self"), "multiplier": 1.5}]),
                 active("kat_s1", "Тяжёлый удар", "Бьёт цель на 200% атаки.", [dmg(T("enemy", "current"), 2.0)], 7000, 3000),
                 active("kat_s2", "Власть тьмы", "Снижает атаку двух ближайших врагов на 15% на 4 с.",
                        [{"kind": "buff", "target": T("enemy", "nearest", 2), "stat": "atk", "percent": -15, "duration_ms": 4000}], 15000, 7000),
                 passive("kat_p", "Подземный трон", "Здоровье +10%.",
                         [{"kind": "stat", "target": T("ally", "self"), "stat": "hp", "percent": 10}])]),
    dict(id="zarkum", name="Заркум", title="Змеиный царевич", faction="underworld", role="assassin",
         description="Сын змеиного царя, принимающий облик юноши.",
         lore="Заркум умеет становиться то змеем, то человеком. Он подкрадывается бесшумно и жалит тех, кто стоит позади.",
         look=dict(skin="#9DBA8A", hair="#2E3A1E", acc="horns"),
         skills=[ult("zar_ult", "Смертельный укус", "Бьёт врага в заднем ряду на 300% атаки и отравляет: 30% атаки в секунду 4 с.",
                     [dmg(T("enemy", "backline"), 3.0), {"kind": "dot", "target": T("enemy", "backline"), "multiplier": 0.3, "duration_ms": 4000}]),
                 active("zar_s1", "Змеиный бросок", "Бьёт врага с наименьшим здоровьем на 190% атаки.", [dmg(T("enemy", "lowest_hp"), 1.9)], 6000, 2500),
                 active("zar_s2", "Сброс кожи", "Щит себе на 200% атаки.",
                        [{"kind": "shield", "target": T("ally", "self"), "multiplier": 2.0, "duration_ms": 5000}], 11000, 5000),
                 passive("zar_p", "Холодная кровь", "Шанс крита +5%.", [{"kind": "stat", "target": T("ally", "self"), "stat": "crit_chance", "percent": 5}])]),
]

# --- Простые (редкие) герои: результат «Редкий» в призыве, корм и эссенция. По одному на фракцию ---
RARE = [
    ("militia_ural", "Ополченец Урала", "ural_batyrs", "warrior", "helmet", "#E8B98A",
     "Простой защитник горных селений.", "Удар копьём", "Бьёт цель на 200% атаки."),
    ("imp_evil", "Упырь", "evil_spirits", "assassin", "horns", "#A99AA8",
     "Мелкая нечисть, что бродит по ночам.", "Укус", "Бьёт врага с наименьшим здоровьем на 220% атаки."),
    ("forest_archer", "Лесной стрелок", "forest_spirits", "archer", "feather", "#9FBF7A",
     "Дух-охотник с луком из ветки рябины.", "Меткая стрела", "Бьёт врага с наименьшим здоровьем на 200% атаки."),
    ("steppe_rider", "Степной всадник", "steppe_nomads", "warrior", "feather", "#D9A577",
     "Лихой наездник из кочевого рода.", "Наскок", "Бьёт цель на 200% атаки."),
    ("sky_guard", "Небесный страж", "sky_dwellers", "support", "halo", "#F0E6D0",
     "Младший служитель царя птиц.", "Свет", "Лечит самого раненого союзника на 200% атаки."),
    ("under_guard", "Подземный страж", "underworld", "tank", "horns", "#8C7A8F",
     "Стражник пещер Катил-падиши.", "Каменный удар", "Бьёт цель на 150% атаки и оглушает на 1 с."),
]
for rid, rname, rfac, rrole, racc, rskin, rdesc, rult, rultd in RARE:
    if rrole == "support":
        ult_eff = [{"kind": "heal", "target": T("ally", "lowest_hp"), "multiplier": 2.0}]
    elif rrole == "tank":
        ult_eff = [dmg(T("enemy", "current"), 1.5), {"kind": "stun", "target": T("enemy", "current"), "duration_ms": 1000}]
    elif rrole in ("assassin", "archer"):
        ult_eff = [dmg(T("enemy", "lowest_hp"), 2.2 if rrole == "assassin" else 2.0)]
    else:
        ult_eff = [dmg(T("enemy", "current"), 2.0)]
    HEROES.append(dict(
        id=rid, name=rname, title="Простой герой", faction=rfac, role=rrole, rarity="rare",
        description=rdesc, lore=rdesc + " Годится в корм для вознесения или в эссенцию.",
        look=dict(skin=rskin, hair="#3A2A1A", acc=racc),
        skills=[ult(f"{rid}_ult", rult, rultd, ult_eff),
                active(f"{rid}_s1", "Обычный приём", "Бьёт цель на 130% атаки.", [dmg(T("enemy", "current"), 1.3)], 8000, 4000)]))

TEST_TEAMS = {"teams": [
    {"id": "test_evil", "name": "Отряд Шульгена", "units": [
        {"hero": "deyeu", "slot": 0}, {"hero": "shulgen", "slot": 1},
        {"hero": "albasty", "slot": 2}, {"hero": "azhdaha", "slot": 3}, {"hero": "baksy", "slot": 4}]},
    {"id": "test_forest", "name": "Лесная засада", "units": [
        {"hero": "urman_huzha", "slot": 0}, {"hero": "shurale", "slot": 1},
        {"hero": "hyuhylu", "slot": 2}, {"hero": "bisura", "slot": 3}, {"hero": "mergen", "slot": 4}]},
    {"id": "test_underworld", "name": "Подземное войско", "units": [
        {"hero": "deyeu", "slot": 0}, {"hero": "katil", "slot": 1},
        {"hero": "zarkum", "slot": 2}, {"hero": "azhdaha", "slot": 3}, {"hero": "albasty", "slot": 4}]},
    {"id": "test_weak", "name": "Учебный отряд", "units": [
        {"hero": "kusyak_biy", "slot": 0, "stat_multiplier": 0.5}, {"hero": "mergen", "slot": 3, "stat_multiplier": 0.5}]},
]}

# ---------------------------------------------------------------------------
# Рисование частей тела
# ---------------------------------------------------------------------------

def rgb(h, k=1.0):
    h = h.lstrip("#")
    c = tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
    return tuple(max(0, min(255, int(v * k))) for v in c) + (255,)


OUTLINE = (34, 22, 40, 255)


def canvas(w, h):
    img = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def done(img, path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    w, h = img.size
    img.resize((w // S, h // S), Image.LANCZOS).save(path, optimize=True)


def rr(d, box, r, fill, ow=3):
    d.rounded_rectangle([v * S for v in box], radius=r * S, fill=fill, outline=OUTLINE, width=ow * S // 2 + 1)


def ell(d, box, fill, ow=3):
    d.ellipse([v * S for v in box], fill=fill, outline=OUTLINE, width=ow * S // 2 + 1)


def poly(d, pts, fill, ow=3):
    d.polygon([(x * S, y * S) for x, y in pts], fill=fill, outline=OUTLINE)
    d.line([(x * S, y * S) for x, y in pts + [pts[0]]], fill=OUTLINE, width=ow * S // 2 + 1)


def draw_head(hero, path):
    lk = hero["look"]
    img, d = canvas(72, 72)
    skin, hair, accent = rgb(lk["skin"]), rgb(lk["hair"]), rgb(FCOLOR[hero["faction"]])
    ell(d, (10, 12, 62, 64), skin)                     # лицо
    d.pieslice([10 * S, 8 * S, 62 * S, 50 * S], 180, 360, fill=hair, outline=OUTLINE, width=2 * S)  # волосы
    for ex in (28, 46):                                 # глаза (смотрит вправо)
        ell(d, (ex - 4, 34, ex + 4, 44), (255, 255, 255, 255), 2)
        ell(d, (ex - 1, 37, ex + 3, 43), (30, 20, 30, 255), 1)
    d.arc([34 * S, 46 * S, 50 * S, 56 * S], 10, 170, fill=OUTLINE, width=2 * S)  # рот
    acc = lk["acc"]
    if acc == "helmet":
        d.pieslice([8 * S, 4 * S, 64 * S, 46 * S], 180, 360, fill=accent, outline=OUTLINE, width=2 * S)
        poly(d, [(34, 0), (38, 0), (40, 14), (32, 14)], rgb("#C0C0C8"))
    elif acc == "crown":
        poly(d, [(14, 18), (18, 4), (26, 14), (36, 2), (46, 14), (54, 4), (58, 18)], accent)
    elif acc == "horns":
        poly(d, [(16, 20), (6, 2), (24, 14)], rgb("#E8E0D0"))
        poly(d, [(56, 20), (66, 2), (48, 14)], rgb("#E8E0D0"))
    elif acc == "antlers":
        for sx in (-1, 1):
            cx = 36 + sx * 14
            d.line([(cx * S, 16 * S), ((cx + sx * 10) * S, 0)], fill=rgb("#7A5A3A"), width=4 * S)
            d.line([((cx + sx * 5) * S, 8 * S), ((cx + sx * 14) * S, 6 * S)], fill=rgb("#7A5A3A"), width=3 * S)
    elif acc == "hood":
        d.pieslice([6 * S, 2 * S, 66 * S, 60 * S], 160, 380, fill=accent, outline=OUTLINE, width=2 * S)
    elif acc in ("feather", "feathers"):
        for i in range(1 if acc == "feather" else 3):
            x = 20 + i * 8
            poly(d, [(x, 16), (x - 6, 0), (x + 4, 2)], accent)
    elif acc == "halo":
        d.ellipse([14 * S, 0, 58 * S, 12 * S], outline=rgb("#FFE27A"), width=4 * S)
    elif acc == "fin":
        poly(d, [(36, 10), (26, 0), (52, 2), (46, 12)], rgb("#7FC8D8"))
    done(img, path)


def draw_torso(hero, path):
    img, d = canvas(48, 56)
    cloth = rgb(FCOLOR[hero["faction"]])
    rr(d, (4, 4, 44, 54), 12, cloth)
    d.rectangle([6 * S, 38 * S, 42 * S, 44 * S], fill=rgb(FCOLOR[hero["faction"]], 0.6))  # пояс
    poly(d, [(20, 4), (28, 4), (24, 16)], rgb(hero["look"]["skin"]), 2)                    # ворот
    done(img, path)


def draw_limb(color, w, h, path, hand=None):
    img, d = canvas(w, h)
    rr(d, (2, 2, w - 2, h - 2), (w - 4) // 2, color)
    if hand:
        ell(d, (1, h - w, w - 1, h - 1), hand, 2)
    done(img, path)


def draw_weapon(role, faction, path):
    accent = rgb(FCOLOR[faction])
    metal, wood = rgb("#D8DCE6"), rgb("#8A5A30")
    if role in ("warrior",):
        img, d = canvas(18, 72)
        poly(d, [(9, 0), (15, 10), (15, 50), (3, 50), (3, 10)], metal)
        rr(d, (0, 48, 18, 54), 2, accent)
        rr(d, (6, 54, 12, 72), 2, wood)
        pivot = (9, 60)
    elif role == "assassin":
        img, d = canvas(14, 44)
        poly(d, [(7, 0), (12, 8), (11, 30), (3, 30), (2, 8)], metal)
        rr(d, (4, 30, 10, 44), 2, wood)
        pivot = (7, 36)
    elif role == "tank":
        img, d = canvas(16, 64)
        rr(d, (5, 14, 11, 64), 2, wood)
        ell(d, (0, 0, 16, 18), metal)  # булава
        pivot = (8, 52)
    elif role == "archer":
        img, d = canvas(26, 76)
        d.arc([0, 0, 40 * S, 76 * S], 100, 260, fill=wood, width=5 * S)
        d.line([(14 * S, 4 * S), (14 * S, 72 * S)], fill=(240, 240, 240, 255), width=S)
        pivot = (8, 38)
    else:  # mage, support — посох
        img, d = canvas(20, 88)
        rr(d, (7, 14, 13, 88), 3, wood)
        ell(d, (0, 0, 20, 20), accent if role == "mage" else rgb("#F4ECDD"))
        pivot = (10, 60)
    done(img, path)
    return pivot


def draw_shield(faction, path):
    img, d = canvas(44, 52)
    poly(d, [(4, 4), (40, 4), (40, 28), (22, 50), (4, 28)], rgb(FCOLOR[faction]))
    poly(d, [(14, 14), (30, 14), (22, 34)], rgb("#F4ECDD"), 2)
    done(img, path)
    return (22, 26)


def draw_wings(path):
    img, d = canvas(96, 64)
    white = rgb("#F4F0E8")
    poly(d, [(48, 40), (4, 4), (10, 30), (2, 46), (40, 50)], white)
    poly(d, [(48, 40), (92, 4), (86, 30), (94, 46), (56, 50)], white)
    done(img, path)
    return (48, 40)


def draw_tail(skin, path):
    img, d = canvas(64, 30)
    poly(d, [(60, 6), (34, 4), (4, 24), (30, 18), (60, 22)], rgb(skin))
    done(img, path)
    return (58, 14)


def draw_projectile(role, faction, path):
    if role == "archer":
        img, d = canvas(40, 10)
        d.line([(0, 5 * S), (32 * S, 5 * S)], fill=rgb("#8A5A30"), width=2 * S)
        poly(d, [(30, 1), (40, 5), (30, 9)], rgb("#D8DCE6"), 1)
    else:
        img, d = canvas(24, 24)
        ell(d, (2, 2, 22, 22), rgb(FCOLOR[faction], 1.2), 2)
        ell(d, (7, 7, 15, 15), (255, 255, 255, 220), 1)
    done(img, path)


# ---------------------------------------------------------------------------
# Скелет и анимации (поза покоя: ось Y вниз, ноги в точке 0,0, смотрит вправо)
# ---------------------------------------------------------------------------

def skeleton_for(hero):
    role = hero["role"]
    acc = hero["look"]["acc"]
    bones = [
        {"name": "root"},
        {"name": "hips", "parent": "root", "x": 0, "y": -34},
        {"name": "leg_back", "parent": "hips", "x": -7, "y": 0},
        {"name": "leg_front", "parent": "hips", "x": 7, "y": 0},
        {"name": "torso", "parent": "hips", "x": 0, "y": 0},
        {"name": "head", "parent": "torso", "x": 2, "y": -48},
        {"name": "arm_back", "parent": "torso", "x": -12, "y": -42},
        {"name": "arm_front", "parent": "torso", "x": 12, "y": -42},
        {"name": "weapon", "parent": "arm_front", "x": 0, "y": 34, "rotation": -90 if role == "archer" else 0},
    ]
    slots = []
    if acc == "wings":
        bones.append({"name": "wings", "parent": "torso", "x": -6, "y": -36})
        slots.append({"name": "wings", "bone": "wings", "image": "parts/wings.png", "pivot": [48, 40]})
    if acc == "tail":
        bones.append({"name": "tail", "parent": "hips", "x": -10, "y": -4})
        slots.append({"name": "tail", "bone": "tail", "image": "parts/tail.png", "pivot": [58, 14]})
    slots += [
        {"name": "arm_back", "bone": "arm_back", "image": "parts/arm.png", "pivot": [8, 6]},
    ]
    if role == "tank":
        bones.append({"name": "shield", "parent": "arm_back", "x": 4, "y": 28})
        slots.append({"name": "shield", "bone": "shield", "image": "parts/shield.png", "pivot": [22, 26]})
    slots += [
        {"name": "leg_back", "bone": "leg_back", "image": "parts/leg.png", "pivot": [9, 4]},
        {"name": "leg_front", "bone": "leg_front", "image": "parts/leg.png", "pivot": [9, 4]},
        {"name": "torso", "bone": "torso", "image": "parts/torso.png", "pivot": [24, 52]},
        {"name": "head", "bone": "head", "image": "parts/head.png", "pivot": [36, 64]},
        {"name": "arm_front", "bone": "arm_front", "image": "parts/arm.png", "pivot": [8, 6]},
        {"name": "weapon", "bone": "weapon", "image": "parts/weapon.png", "pivot": list(hero["_weapon_pivot"])},
    ]
    anchors = {
        "projectile": {"bone": "weapon", "x": 0, "y": -30},
        "hit": {"bone": "torso", "x": 0, "y": -26},
        "overhead": {"bone": "head", "x": 0, "y": -70},
    }
    ranged = role in ("archer", "mage", "support")

    idle = {"duration": 1.2, "loop": True, "bones": {
        "torso": {"scale": [[0, 1, 1], [0.6, 1.0, 1.03], [1.2, 1, 1]]},
        "head": {"translate": [[0, 0, 0], [0.6, 0, -1.5], [1.2, 0, 0]]},
        "arm_front": {"rotate": [[0, 0], [0.6, -5], [1.2, 0]]},
        "arm_back": {"rotate": [[0, 0], [0.6, 5], [1.2, 0]]},
    }}
    if acc == "wings":
        idle["bones"]["wings"] = {"rotate": [[0, 0], [0.6, -6], [1.2, 0]]}
    if ranged:
        attack = {"duration": 0.6, "bones": {
            "arm_front": {"rotate": [[0, 0], [0.2, -100], [0.45, -95], [0.6, 0]]},
            "torso": {"rotate": [[0, 0], [0.4, -4], [0.6, 0]]},
        }, "events": [{"t": 0.4, "name": "projectile"}]}
        skill = {"duration": 0.8, "bones": {
            "arm_front": {"rotate": [[0, 0], [0.3, -150], [0.6, -120], [0.8, 0]]},
            "arm_back": {"rotate": [[0, 0], [0.3, 60], [0.8, 0]]},
            "root": {"scale": [[0, 1, 1], [0.5, 1.08, 1.08], [0.8, 1, 1]]},
        }, "events": [{"t": 0.5, "name": "hit"}]}
    else:
        attack = {"duration": 0.6, "bones": {
            "arm_front": {"rotate": [[0, 0], [0.22, -150], [0.35, 30], [0.6, 0]]},
            "torso": {"rotate": [[0, 0], [0.22, -8], [0.35, 10], [0.6, 0]]},
            "root": {"translate": [[0, 0, 0], [0.35, 6, 0], [0.6, 0, 0]]},
        }, "events": [{"t": 0.35, "name": "hit"}]}
        skill = {"duration": 0.8, "bones": {
            "arm_front": {"rotate": [[0, 0], [0.3, -170], [0.5, 40], [0.8, 0]]},
            "torso": {"rotate": [[0, 0], [0.3, -12], [0.5, 14], [0.8, 0]]},
            "root": {"translate": [[0, 0, 0], [0.5, 14, 0], [0.8, 0, 0]], "scale": [[0, 1, 1], [0.5, 1.1, 1.1], [0.8, 1, 1]]},
        }, "events": [{"t": 0.5, "name": "hit"}]}
    ultimate = {"duration": 1.2, "bones": {
        "hips": {"translate": [[0, 0, 0], [0.3, 0, 6], [0.6, 0, -24], [0.9, 0, 0], [1.2, 0, 0]]},
        "arm_front": {"rotate": [[0, 0], [0.6, -175], [0.9, 50], [1.2, 0]]},
        "arm_back": {"rotate": [[0, 0], [0.6, 120], [1.2, 0]]},
        "root": {"scale": [[0, 1, 1], [0.6, 1.25, 1.25], [1.0, 1.1, 1.1], [1.2, 1, 1]]},
    }, "events": [{"t": 0.9, "name": "hit"}]}
    hit = {"duration": 0.3, "bones": {
        "torso": {"rotate": [[0, 0], [0.1, -12], [0.3, 0]]},
        "root": {"translate": [[0, 0, 0], [0.1, -6, 0], [0.3, 0, 0]]},
        "head": {"rotate": [[0, 0], [0.1, -10], [0.3, 0]]},
    }}
    death = {"duration": 0.9, "bones": {
        "root": {"rotate": [[0, 0], [0.5, -85], [0.9, -90]], "translate": [[0, 0, 0], [0.5, -14, -6], [0.9, -16, 0]]},
    }, "alpha": [[0, 1], [0.6, 1], [0.9, 0.35]]}
    victory = {"duration": 1.0, "loop": True, "bones": {
        "root": {"translate": [[0, 0, 0], [0.3, 0, -18], [0.6, 0, 0], [1.0, 0, 0]]},
        "arm_front": {"rotate": [[0, -160], [0.5, -140], [1.0, -160]]},
        "arm_back": {"rotate": [[0, 150], [0.5, 130], [1.0, 150]]},
    }}
    walk = {"duration": 0.6, "loop": True, "bones": {
        "leg_front": {"rotate": [[0, -25], [0.3, 25], [0.6, -25]]},
        "leg_back": {"rotate": [[0, 25], [0.3, -25], [0.6, 25]]},
        "hips": {"translate": [[0, 0, 0], [0.15, 0, -3], [0.3, 0, 0], [0.45, 0, -3], [0.6, 0, 0]]},
        "arm_back": {"rotate": [[0, -15], [0.3, 15], [0.6, -15]]},
    }}
    return {
        "format": "ufa-skeleton", "version": 1, "size": [96, 130],
        "bones": bones, "slots": slots, "anchors": anchors,
        "animations": {"idle": idle, "walk": walk, "attack": attack, "skill": skill, "ultimate": ultimate,
                       "hit": hit, "death": death, "victory": victory},
    }


def draw_portrait(hero, head_path, path):
    bg = rgb(FCOLOR[hero["faction"]], 0.55)
    img = Image.new("RGBA", (128 * S, 128 * S), bg)
    d = ImageDraw.Draw(img)
    for i in range(0, 128 * S, 8 * S):  # лёгкая штриховка
        d.line([(i, 0), (0, i)], fill=rgb(FCOLOR[hero["faction"]], 0.65), width=2 * S)
    head = Image.open(head_path).resize((104 * S, 104 * S), Image.LANCZOS)
    img.alpha_composite(head, (12 * S, 18 * S))
    d.rectangle([0, 0, 128 * S - 1, 128 * S - 1], outline=rgb("#F2B544"), width=6 * S)
    done(img, path)


def compose_full(hero_dir: Path, skel: dict, path: Path):
    """Полный арт = герой в позе покоя (собираем части по скелету, без поворотов)."""
    W, H = 160, 200
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    pos = {}
    for b in skel["bones"]:
        px, py = pos.get(b.get("parent"), (W / 2, H - 16))
        pos[b["name"]] = (px + b.get("x", 0), py + b.get("y", 0))
    for s in skel["slots"]:
        part = Image.open(hero_dir / s["image"])
        bx, by = pos[s["bone"]]
        bone = next(b for b in skel["bones"] if b["name"] == s["bone"])
        if bone.get("rotation"):
            part = part.rotate(-bone["rotation"], expand=True, resample=Image.BICUBIC)
            img.alpha_composite(part, (int(bx - part.width / 2), int(by - part.height / 2)))
            continue
        img.alpha_composite(part, (int(bx - s["pivot"][0]), int(by - s["pivot"][1])))
    img.save(path, optimize=True)


def write_hero(h, hid, role, art, write):
    stats = dict(BASE_STATS[role])
    stats["hp"] = round(stats["hp"] * HP_SCALE)
    if h.get("rarity") == "rare":  # простые герои слабее
        for k in ("hp", "atk", "def"):
            stats[k] = round(stats[k] * 0.8)
    hero_json = {
        "id": hid, "name": h["name"], "title": h["title"], "faction": h["faction"], "role": role,
        "rarity": h.get("rarity", "legendary"), "description": h["description"], "lore": h["lore"],
        "stats": stats, "skills": h["skills"], "art": art,
    }
    old = ROOT / "heroes" / hid / "hero.json"
    if old.is_file():  # скины, добавленные в админке/вручную, не теряем
        prev = json.loads(old.read_text(encoding="utf-8"))
        if prev.get("skins"):
            hero_json["skins"] = prev["skins"]
    write(f"heroes/{hid}/hero.json", hero_json)
    print(f"{hid:<12} {h['name']:<12} {role:<9} {h['faction']}")


def main():
    def write(rel, data):
        p = ROOT / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    write("config/battle.json", BATTLE)
    write("factions/factions.json", {"factions": FACTIONS})
    write("battle/test_teams.json", TEST_TEAMS)

    for h in HEROES:
        hid = h["id"]
        hdir = ROOT / "heroes" / hid
        role = h["role"]
        if (hdir / "rig").is_dir():
            # Готовый арт (scripts/import_cutout_rig.py) — не перерисовываем, берём пути из hero.json
            art = json.loads((hdir / "hero.json").read_text(encoding="utf-8"))["art"]
            write_hero(h, hid, role, art, write)
            continue
        skin = rgb(h["look"]["skin"])
        cloth = rgb(FCOLOR[h["faction"]], 0.85)
        draw_head(h, hdir / "parts/head.png")
        draw_torso(h, hdir / "parts/torso.png")
        draw_limb(cloth, 16, 40, hdir / "parts/arm.png", hand=skin)
        draw_limb(rgb("#3A2A3A"), 18, 38, hdir / "parts/leg.png")
        h["_weapon_pivot"] = draw_weapon(role, h["faction"], hdir / "parts/weapon.png")
        if role == "tank":
            draw_shield(h["faction"], hdir / "parts/shield.png")
        if h["look"]["acc"] == "wings":
            draw_wings(hdir / "parts/wings.png")
        if h["look"]["acc"] == "tail":
            draw_tail(h["look"]["skin"], hdir / "parts/tail.png")
        skel = skeleton_for(h)
        write(f"heroes/{hid}/skeleton.json", skel)
        draw_portrait(h, hdir / "parts/head.png", hdir / "portrait.png")
        compose_full(hdir, skel, hdir / "full.png")
        art = {"portrait": f"heroes/{hid}/portrait.png", "full": f"heroes/{hid}/full.png",
               "skeleton": f"heroes/{hid}/skeleton.json"}
        if role in ("archer", "mage", "support"):
            draw_projectile(role, h["faction"], hdir / "projectile.png")
            art["projectile"] = f"heroes/{hid}/projectile.png"
        write_hero(h, hid, role, art, write)
    print(f"Готово: {len(HEROES)} героев -> {ROOT / 'heroes'}")


if __name__ == "__main__":
    main()

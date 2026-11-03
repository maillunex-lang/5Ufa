"""Точный расчёт наград в целых долях, без округления при смене скорости.

Сундук копит несколько ресурсов (золото, опыт героев, кристаллы, эссенция). Для каждого
хранится целочисленная «доля»: микросекунды × ставка_в_час × процент_скорости.
Целая часть выдаётся при сборе, остаток сохраняется.
"""
from datetime import datetime, timezone, timedelta

DENOMINATOR = 3600 * 1_000_000 * 100
UFA = timezone(timedelta(hours=5))

# ресурс -> (ключ ставки в config/campaign.json, поле доли в campaign_progress, делитель ставки)
# Делитель 100 — ставка задана «за 100 часов» (так задаются редкие награды вроде предметов).
# "equipment" — количество предметов снаряжения; сами предметы создаёт вызывающий код.
RESOURCES = {
    "gold": ("gold_per_hour", "gold_fraction", 1),
    "hero_xp": ("hero_xp_per_hour", "xp_fraction", 1),
    "crystals": ("crystals_per_hour", "crystal_fraction", 1),
    "essence": ("essence_per_hour", "essence_fraction", 1),
    "ore": ("ore_per_hour", "ore_fraction", 1),
    "equipment": ("equipment_per_100h", "equipment_fraction", 100),
}


def as_utc(value):
    return value.replace(tzinfo=value.tzinfo or timezone.utc).astimezone(timezone.utc)


def rate_percent(progress, config):
    return 100 + progress.cleared * config["stage_bonus_percent"]


def settle(progress, config, now):
    now = as_utc(now)
    last = as_utc(progress.updated_at)
    delta = now - last
    micros = max(0, delta.days * 86400 * 1_000_000 + delta.seconds * 1_000_000 + delta.microseconds)
    cap = config["afk_cap_seconds"] * 1_000_000
    added = min(micros, max(0, cap - progress.elapsed_us))
    rate = rate_percent(progress, config)
    for _, (rate_key, field, _div) in RESOURCES.items():
        per_hour = int(config.get(rate_key, 0))
        if per_hour:
            setattr(progress, field, getattr(progress, field) + added * per_hour * rate)
    progress.elapsed_us += added
    progress.updated_at = max(now, last)


def pending(progress):
    return {res: getattr(progress, field) // (DENOMINATOR * div) for res, (_, field, div) in RESOURCES.items()}


def claim(progress):
    """Забрать целую часть сундука; остатки долей сохраняются. Начисление в кошелёк — вызывающий код."""
    reward = pending(progress)
    for _, (_, field, div) in RESOURCES.items():
        setattr(progress, field, getattr(progress, field) % (DENOMINATOR * div))
    progress.elapsed_us = 0
    return reward


def quick(progress, config, now):
    """Быстрая награда: N часов по текущей скорости. Не уменьшает сундук. None — лимит на сегодня."""
    today = as_utc(now).astimezone(UFA).date().isoformat()
    if progress.quick_day != today:
        progress.quick_day = today
        progress.quick_count = 0
    if progress.quick_count >= config["quick_daily_limit"]:
        return None
    rate = rate_percent(progress, config)
    reward = {}
    for res, (rate_key, _, div) in RESOURCES.items():
        # Дробные остатки быстрой награды не относятся к накоплениям сундука.
        reward[res] = config["quick_seconds"] * 1_000_000 * int(config.get(rate_key, 0)) * rate // (DENOMINATOR * div)
    progress.quick_count += 1
    return reward

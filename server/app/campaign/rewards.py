"""Точный расчёт наград в целых долях, без округления при смене скорости."""
from datetime import datetime, timezone, timedelta

DENOMINATOR = 3600 * 1_000_000 * 100
UFA = timezone(timedelta(hours=5))


def as_utc(value):
    return value.replace(tzinfo=value.tzinfo or timezone.utc).astimezone(timezone.utc)


def settle(progress, config, now):
    now = as_utc(now)
    last = as_utc(progress.updated_at)
    delta = now - last
    micros = max(0, delta.days * 86400 * 1_000_000 + delta.seconds * 1_000_000 + delta.microseconds)
    cap = config["afk_cap_seconds"] * 1_000_000
    added = min(micros, max(0, cap - progress.elapsed_us))
    rate = 100 + progress.cleared * config["stage_bonus_percent"]
    progress.gold_fraction += added * config["gold_per_hour"] * rate
    progress.xp_fraction += added * config["hero_xp_per_hour"] * rate
    progress.elapsed_us += added
    progress.updated_at = max(now, last)


def pending(progress):
    return {"gold": progress.gold_fraction // DENOMINATOR, "hero_xp": progress.xp_fraction // DENOMINATOR}


def claim(progress):
    reward = pending(progress)
    progress.gold += reward["gold"]
    progress.hero_xp += reward["hero_xp"]
    progress.gold_fraction %= DENOMINATOR
    progress.xp_fraction %= DENOMINATOR
    progress.elapsed_us = 0
    return reward


def quick(progress, config, now):
    today = as_utc(now).astimezone(UFA).date().isoformat()
    if progress.quick_day != today:
        progress.quick_day = today
        progress.quick_count = 0
    if progress.quick_count >= config["quick_daily_limit"]:
        return None
    rate = 100 + progress.cleared * config["stage_bonus_percent"]
    gold_n = config["quick_seconds"] * 1_000_000 * config["gold_per_hour"] * rate
    xp_n = config["quick_seconds"] * 1_000_000 * config["hero_xp_per_hour"] * rate
    # Дробные остатки быстрой награды не относятся к накоплениям сундука.
    gold = gold_n // DENOMINATOR
    xp = xp_n // DENOMINATOR
    progress.gold += gold
    progress.hero_xp += xp
    progress.quick_count += 1
    return {"gold": gold, "hero_xp": xp}

"""Кошелёк игрока: все валюты в одной таблице (player_wallet).

Вызывающий код должен заранее заблокировать строку игрока (lock_player), чтобы
параллельные запросы не потратили одну и ту же валюту дважды.
"""
from __future__ import annotations

from fastapi import HTTPException
from sqlalchemy import select

from app.models import WalletEntry

CURRENCY_NAMES = {
    "gold": "золота",
    "hero_xp": "опыта героев",
    "crystals": "кристаллов",
    "essence": "эссенции",
    "scrolls": "свитков призыва",
    "ore": "руды",
    "legacy_shards": "осколков наследия",
}


def currency_name(code: str) -> str:
    if code.startswith("faction_scroll_"):
        return "свитков фракции"
    return CURRENCY_NAMES.get(code, code)


async def balances(session, player_id) -> dict[str, int]:
    rows = (await session.execute(select(WalletEntry).where(WalletEntry.player_id == player_id))).scalars()
    return {r.code: int(r.amount) for r in rows}


async def _entry(session, player_id, code: str) -> WalletEntry:
    entry = await session.get(WalletEntry, (player_id, code))
    if entry is None:
        entry = WalletEntry(player_id=player_id, code=code, amount=0)
        session.add(entry)
        await session.flush()
    return entry


async def add(session, player_id, amounts: dict[str, int]) -> None:
    for code, amount in amounts.items():
        if amount:
            entry = await _entry(session, player_id, code)
            entry.amount += int(amount)


async def spend(session, player_id, costs: dict[str, int]) -> None:
    """Списать всё или ничего. Не хватает — HTTP 409 с понятным текстом."""
    entries = {}
    for code, amount in costs.items():
        if amount <= 0:
            continue
        entry = await _entry(session, player_id, code)
        if entry.amount < amount:
            raise HTTPException(409, f"Не хватает {currency_name(code)}: нужно {amount}, есть {entry.amount}")
        entries[code] = entry
    for code, entry in entries.items():
        entry.amount -= int(costs[code])

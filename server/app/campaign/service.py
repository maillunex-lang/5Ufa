from sqlalchemy import select

from app.models import CampaignProgress, Player, utcnow


async def locked_progress(session, player_id):
    # Строка игрока сериализует также первое создание прогресса.
    await session.execute(select(Player.id).where(Player.id == player_id).with_for_update())
    progress = await session.get(CampaignProgress, player_id)
    if progress is None:
        progress = CampaignProgress(player_id=player_id, cleared=0, gold=0, hero_xp=0,
                                    gold_fraction=0, xp_fraction=0, elapsed_us=0,
                                    updated_at=utcnow(), quick_day="", quick_count=0)
        session.add(progress)
        await session.flush()
    return progress

"""Манифест загрузки контента для клиента игры."""
from fastapi import APIRouter, Depends, HTTPException, Request, Response
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import optional_player
from app.content.releases import get_channel_release, public_manifest
from app.db import get_session
from app.models import Player

router = APIRouter(prefix="/api/v1/content", tags=["content"])


@router.get("/manifest")
async def get_manifest(
    request: Request,
    response: Response,
    session: AsyncSession = Depends(get_session),
    player: Player | None = Depends(optional_player),
):
    """Список пакетов контента с версиями, размерами и SHA-256 каждого файла.

    URL файла = base_url + sha256[:2] + "/" + sha256.
    Поддерживается If-None-Match: если контент не изменился — ответ 304 без тела.
    Канал выбирает сервер: тестовые аккаунты (is_test) получают канал test, остальные — live.
    """
    channel = "test" if player is not None and player.is_test else "live"
    release = await get_channel_release(session, channel)
    if release is None:
        raise HTTPException(status_code=503, detail="Контент ещё не опубликован")
    etag = f'"{channel}-{release.id}-{release.content_hash[:16]}"'
    if request.headers.get("if-none-match") == etag:
        return Response(status_code=304, headers={"ETag": etag})
    response.headers["ETag"] = etag
    response.headers["Cache-Control"] = "no-cache"
    return public_manifest(release, channel)

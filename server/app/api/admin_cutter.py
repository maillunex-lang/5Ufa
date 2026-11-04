"""API нарезчика героя (админка, этап 6в-3). Описание — app/admin/cutter.py, docs/admin.md.

Нарезка ИИ идёт в фоне (Gemini отвечает до пары минут): POST .../ai запускает, GET .../ai — статус.
"""
from __future__ import annotations

import asyncio
import json
import logging

from fastapi import APIRouter, Depends, Header, HTTPException, Request, Response
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.admin import cutter as cut
from app.admin import draft as drf
from app.admin.security import audit, require_role
from app.ai import gemini
from app.content.validation import ContentError
from app.db import get_session
from app.models import AdminUser

router = APIRouter(prefix="/api/v1/admin/cutter", tags=["admin"])
editor = require_role("editor")
log = logging.getLogger("cutter")
MAX_UPLOAD = 60 * 1024 * 1024
_ai_tasks: dict[str, asyncio.Task] = {}


def _err(e: Exception):
    if isinstance(e, ContentError):
        return HTTPException(422, {"message": "Ошибка в данных героя", "errors": e.messages})
    return HTTPException(422, str(e))


class CropIn(BaseModel):
    x: int
    y: int
    w: int = Field(gt=0)
    h: int = Field(gt=0)


class TemplateIn(BaseModel):
    template: str = "humanoid"


class PartIn(BaseModel):
    name: str
    layer: str = "source"
    polygons: list[list[list[float]]] = []
    strokes: list[dict] = []


class PreviewIn(BaseModel):
    part: PartIn


class BuildIn(BaseModel):
    hero: str
    skin: str = ""
    template: str = "humanoid"
    parts: list[PartIn]
    joints: dict[str, list[float]]
    art: bool = False


@router.get("/templates")
async def get_templates(admin: AdminUser = Depends(editor)):
    return {"templates": cut.templates_public(), "ai": bool(gemini.api_key())}


@router.post("")
async def upload(request: Request, name: str = "", x_filename: str = Header(""), admin: AdminUser = Depends(editor)):
    data = await request.body()
    if not data:
        raise HTTPException(422, "Пустой файл")
    if len(data) > MAX_UPLOAD:
        raise HTTPException(413, "Файл больше 60 МБ")
    try:
        return await asyncio.to_thread(cut.create_session, data, name or x_filename)
    except cut.CutterError as e:
        raise _err(e)


@router.get("/{sid}/image")
async def image(sid: str, which: str = "source", admin: AdminUser = Depends(editor)):
    try:
        return Response(cut.image_png(sid, which), media_type="image/png")
    except cut.CutterError as e:
        raise HTTPException(404, str(e))


@router.post("/{sid}/crop")
async def crop(sid: str, body: CropIn, admin: AdminUser = Depends(editor)):
    try:
        return await asyncio.to_thread(cut.crop_session, sid, body.x, body.y, body.w, body.h)
    except cut.CutterError as e:
        raise _err(e)


@router.post("/{sid}/auto")
async def auto(sid: str, body: TemplateIn, admin: AdminUser = Depends(editor)):
    try:
        return await asyncio.to_thread(cut.auto_cut, sid, body.template)
    except cut.CutterError as e:
        raise _err(e)


def _ai_status_path(sid: str):
    return cut.session_dir(sid) / "ai_status.json"


def _ai_job(sid: str, tid: str) -> None:
    path = _ai_status_path(sid)
    try:
        res = cut.ai_cut(sid, tid, gemini.generate_image, gemini.detect_boxes)
        path.write_text(json.dumps({"status": "done", "result": res}, ensure_ascii=False), encoding="utf-8")
    except (cut.CutterError, gemini.GeminiError) as e:
        path.write_text(json.dumps({"status": "error", "error": str(e)}, ensure_ascii=False), encoding="utf-8")
    except Exception:  # noqa: BLE001 — сообщаем админке, подробности в лог сервера
        log.exception("ИИ-нарезка %s", sid)
        path.write_text(json.dumps({"status": "error", "error": "Внутренняя ошибка нарезки ИИ (см. лог сервера)"},
                                   ensure_ascii=False), encoding="utf-8")


@router.post("/{sid}/ai")
async def ai_start(sid: str, body: TemplateIn, admin: AdminUser = Depends(editor)):
    try:
        cut.template(body.template)
        path = _ai_status_path(sid)
    except cut.CutterError as e:
        raise _err(e)
    if not gemini.api_key():
        raise HTTPException(422, "ИИ не подключён: на сервере нет ключа Gemini (GEMINI_API_KEY в .env)")
    task = _ai_tasks.get(sid)
    if task and not task.done():
        return {"status": "running"}
    path.write_text(json.dumps({"status": "running"}), encoding="utf-8")
    _ai_tasks[sid] = asyncio.create_task(asyncio.to_thread(_ai_job, sid, body.template))
    return {"status": "running"}


@router.get("/{sid}/ai")
async def ai_status(sid: str, admin: AdminUser = Depends(editor)):
    try:
        path = _ai_status_path(sid)
    except cut.CutterError as e:
        raise HTTPException(404, str(e))
    if not path.exists():
        return {"status": "none"}
    st = json.loads(path.read_text(encoding="utf-8"))
    if st.get("status") == "running" and sid not in _ai_tasks:
        st = {"status": "error", "error": "Нарезка прервалась (сервер перезапускался) — запустите ещё раз"}
    return st


@router.post("/{sid}/preview")
async def preview(sid: str, body: PreviewIn, admin: AdminUser = Depends(editor)):
    try:
        return await asyncio.to_thread(cut.part_preview, sid, body.part.model_dump())
    except cut.CutterError as e:
        raise _err(e)


def _template_anims(ws, hero_id: str, role: str, tpl: dict) -> dict | None:
    """Анимации для нового скелета — с героя той же роли с теми же костями (потом — шаблоны 6в-4)."""
    need = set(tpl["anim_bones"])
    best = None
    for path in sorted(ws.files()):
        if not (path.startswith("heroes/") and path.endswith("/hero.json")) or path == f"heroes/{hero_id}/hero.json":
            continue
        try:
            h = ws.read_json(path)
            sk = ws.read_json(str(h.get("art", {}).get("skeleton", path[:-9] + "skeleton.json")))
        except (KeyError, ValueError):
            continue
        if not need <= {b["name"] for b in sk.get("bones", [])} or not sk.get("animations"):
            continue
        if h.get("role") == role:
            return sk["animations"]
        best = best or sk["animations"]
    return best


@router.post("/{sid}/build")
async def build(sid: str, body: BuildIn, request: Request, admin: AdminUser = Depends(editor),
                session: AsyncSession = Depends(get_session)):
    ws = await drf.workspace(session)
    hero_path = f"heroes/{body.hero}/hero.json"
    if not ws.exists(hero_path):
        raise HTTPException(404, "Герой не найден")
    hero = ws.read_json(hero_path)
    skel_path = str(hero.get("art", {}).get("skeleton") or f"heroes/{body.hero}/skeleton.json")
    existing = ws.read_json(skel_path) if ws.exists(skel_path) else None
    skin = body.skin if body.skin not in ("", "default") else None
    if skin and not any(s.get("id") == skin for s in hero.get("skins", [])):
        raise HTTPException(404, f"У героя нет скина «{skin}» — создайте его в «Предпросмотр героя»")
    try:
        tpl = cut.template(body.template)
        base_anims = None if skin else _template_anims(ws, body.hero, str(hero.get("role", "")), tpl)
        files, skel, report = await asyncio.to_thread(
            cut.build_rig, sid, body.template, [p.model_dump() for p in body.parts], body.joints,
            existing=existing, skin=skin, base_anims=base_anims)
        if body.art:
            art = await asyncio.to_thread(cut.portrait_and_full, sid)
            for name, data in art.items():
                files[(f"skins/{skin}/" if skin else "") + name] = data
    except cut.CutterError as e:
        raise _err(e)
    prefix = f"heroes/{body.hero}/"
    try:
        for rel, data in files.items():
            await drf.put_file(session, admin.id, prefix + rel, data)
        await drf.put_json(session, admin.id, skel_path, skel)
        removed = 0
        if not skin:
            # Старые картинки частей, на которые больше не ссылается скелет
            keep = {prefix + s["image"] for s in skel["slots"]}
            for p in sorted(ws.files()):
                if p.startswith((prefix + "rig/", prefix + "parts/")) and p not in keep:
                    await drf.delete_file(session, admin.id, p)
                    removed += 1
        if body.art and not skin:
            art = hero.setdefault("art", {})
            art["portrait"], art["full"] = prefix + "portrait.png", prefix + "full.png"
            await drf.put_json(session, admin.id, hero_path, hero)
    except ContentError as e:
        raise _err(e)
    report["removed"] = removed
    report["files"] = len(files)
    what = f"скин «{skin}»" if skin else "обычный вид"
    await audit(session, request, admin, "hero_cut",
                f"Герой «{body.hero}»: нарезка ({what}, шаблон «{tpl['name']}», частей {len(report['parts'])})",
                {"hero": body.hero, "skin": skin, "template": body.template})
    await session.commit()
    return {"ok": True, "report": report, "skeleton": skel_path}

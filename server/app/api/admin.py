"""API админки (этап 6а): вход, журнал, разделы контента, черновик → тест → публикация → откат, ZIP-патчи.

Все запросы, кроме входа, — с заголовком Authorization: Bearer <токен админки>.
Каждое изменение пишется в журнал действий (admin_audit).
"""
from __future__ import annotations

import json
from datetime import datetime, timezone

from fastapi import APIRouter, Body, Depends, HTTPException, Query, Request, Response
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.admin import draft as drf
from app.admin import sections as sec
from app.admin.security import (audit, clear_failures, current_admin, locked_for, new_token, register_failure,
                                require_role, token_hash, totp_verify)
from app.auth.deps import client_ip
from app.auth.security import verify_password
from app.config import get_settings
from app.content.releases import get_channel_release, publish
from app.content.validation import ContentError, get_schema_registry
from app.db import get_session
from app.models import CHANNELS, AdminAudit, AdminSession, AdminUser, ContentChannel, ContentRelease

router = APIRouter(prefix="/api/v1/admin", tags=["admin"])
editor = require_role("editor")


def content_error(e: ContentError) -> HTTPException:
    return HTTPException(422, {"message": "Контент не прошёл проверку", "errors": e.messages[:200]})


# --- Вход ---------------------------------------------------------------------------

class LoginIn(BaseModel):
    login: str = Field(min_length=1, max_length=64)
    password: str = Field(min_length=1, max_length=256)
    code: str = Field(default="", max_length=12, description="Код 2FA, если включена")


@router.post("/auth/login")
async def login(body: LoginIn, request: Request, session: AsyncSession = Depends(get_session)):
    ip = client_ip(request)
    login_name = body.login.strip().lower()
    for key in (f"ip:{ip}", f"login:{login_name}"):
        wait = await locked_for(key)
        if wait:
            raise HTTPException(429, f"Слишком много неудачных попыток. Попробуйте через {max(1, wait // 60)} мин.")
    admin = (await session.execute(select(AdminUser).where(AdminUser.login == login_name))).scalar_one_or_none()
    ok = admin is not None and not admin.disabled and verify_password(body.password, admin.password_hash)
    if ok and admin.totp_enabled:
        if not body.code:
            return JSONResponse({"totp_required": True, "detail": "Введите код из приложения-аутентификатора"}, 401)
        ok = totp_verify(admin.totp_secret or "", body.code)
    if not ok:
        await register_failure(f"ip:{ip}")
        await register_failure(f"login:{login_name}")
        await audit(session, request, None, "login_failed", f"Неудачный вход: {login_name}", login=login_name)
        await session.commit()
        raise HTTPException(401, "Неверный логин или пароль")
    await clear_failures(f"login:{login_name}")
    token = new_token()
    session.add(AdminSession(admin_id=admin.id, token_hash=token_hash(token), ip=ip,
                             user_agent=request.headers.get("user-agent", "")[:256]))
    admin.last_login_at = datetime.now(timezone.utc)
    await audit(session, request, admin, "login", "Вход в админку")
    await session.commit()
    return {"token": token, "admin": {"login": admin.login, "role": admin.role, "totp_enabled": admin.totp_enabled},
            "session_days": get_settings().admin_session_days}


@router.post("/auth/logout")
async def logout(request: Request, admin: AdminUser = Depends(current_admin), session: AsyncSession = Depends(get_session)):
    row = await session.get(AdminSession, request.state.admin_session_id)
    if row is not None:
        await session.delete(row)
    await audit(session, request, admin, "logout", "Выход")
    await session.commit()
    return {"ok": True}


@router.get("/me")
async def me(admin: AdminUser = Depends(current_admin), session: AsyncSession = Depends(get_session)):
    await session.commit()
    return {"login": admin.login, "role": admin.role, "totp_enabled": admin.totp_enabled}


# --- Журнал -------------------------------------------------------------------------

@router.get("/audit")
async def audit_log(limit: int = Query(50, ge=1, le=200), before_id: int | None = None, action: str = "",
                    admin: AdminUser = Depends(require_role()), session: AsyncSession = Depends(get_session)):
    q = select(AdminAudit).order_by(AdminAudit.id.desc()).limit(limit)
    if before_id:
        q = q.where(AdminAudit.id < before_id)
    if action:
        q = q.where(AdminAudit.action == action)
    rows = (await session.execute(q)).scalars()
    return {"items": [{"id": r.id, "at": r.created_at.isoformat(), "login": r.login, "action": r.action,
                       "summary": r.summary, "details": r.details, "ip": r.ip} for r in rows]}


# --- Разделы ------------------------------------------------------------------------

@router.get("/sections")
async def list_sections(admin: AdminUser = Depends(editor), session: AsyncSession = Depends(get_session)):
    ws = await drf.workspace(session)
    ch = await drf.changes(session)
    changed = {}
    for c in ch["changes"]:
        sid = sec.section_of(c["path"]) or "other"
        changed[sid] = changed.get(sid, 0) + 1
    out = []
    for s in sec.sections().values():
        files = sec.section_files(ws, s)
        out.append({"id": s["id"], "title": s["title"], "icon": s.get("icon", ""), "preview": s.get("preview", "none"),
                    "objects": len(sec.list_objects(ws, s)), "assets": len(files["assets"]),
                    "draft_changes": changed.get(s["id"], 0)})
    await session.commit()
    return {"sections": out, "draft": {k: v for k, v in ch.items() if k != "changes"} | {"count": len(ch["changes"])}}


@router.get("/sections/{section_id}")
async def section_detail(section_id: str, admin: AdminUser = Depends(editor), session: AsyncSession = Depends(get_session)):
    try:
        s = sec.get_section(section_id)
    except ContentError as e:
        raise HTTPException(404, e.messages[0])
    ws = await drf.workspace(session)
    files = sec.section_files(ws, s)
    reg = get_schema_registry()
    await session.commit()
    return {"id": s["id"], "title": s["title"], "objects_kind": s["objects"], "preview": s.get("preview", "none"),
            "objects": sec.list_objects(ws, s), "files": [{"path": p, "schema": reg.schema_for_path(p)} for p in files["files"]],
            "assets": [{"path": p, "sha256": ws.files()[p]} for p in files["assets"]]}


@router.get("/sections/{section_id}/objects/{oid}")
async def get_object(section_id: str, oid: str, admin: AdminUser = Depends(editor), session: AsyncSession = Depends(get_session)):
    s = sec.get_section(section_id)
    ws = await drf.workspace(session)
    data = sec.get_object(ws, s, oid)
    await session.commit()
    if data is None:
        raise HTTPException(404, f"Объекта «{oid}» нет в разделе «{s['title']}»")
    o = s["objects"]
    path = o.get("file") or o["path"].replace("{id}", oid)
    return {"id": oid, "data": data, "path": path, "schema": get_schema_registry().schema_for_path(path)}


class ObjectIn(BaseModel):
    data: dict
    create: bool = False


@router.put("/sections/{section_id}/objects/{oid}")
async def put_object(section_id: str, oid: str, body: ObjectIn, request: Request,
                     admin: AdminUser = Depends(editor), session: AsyncSession = Depends(get_session)):
    s = sec.get_section(section_id)
    ws = await drf.workspace(session)
    exists = sec.get_object(ws, s, oid) is not None
    if body.create and exists:
        raise HTTPException(409, f"Объект «{oid}» уже есть")
    if not body.create and not exists:
        raise HTTPException(404, f"Объекта «{oid}» нет — чтобы добавить, отметьте «новый»")
    o = s["objects"]
    try:
        if o["kind"] == "single":
            path = o["file"]
            await drf.put_json(session, admin.id, path, body.data)
        elif o["kind"] == "array_in_file":
            path = o["file"]
            doc = ws.read_json(path) if ws.exists(path) else {o["key"]: []}
            items = doc.setdefault(o["key"], [])
            item = {**body.data, "id": oid}
            idx = next((i for i, x in enumerate(items) if x.get("id") == oid), None)
            if idx is None:
                items.append(item)
            else:
                items[idx] = item
            await drf.put_json(session, admin.id, path, doc)
        else:
            import re
            if not re.fullmatch(r"[a-z][a-z0-9_]{0,63}", oid):
                raise HTTPException(422, "id: латиница в нижнем регистре, цифры и _, начинается с буквы")
            path = o["path"].replace("{id}", oid)
            await drf.put_json(session, admin.id, path, body.data)
    except ContentError as e:
        raise content_error(e)
    await audit(session, request, admin, "object_create" if body.create else "object_update",
                f"{s['title']}: {'добавлен' if body.create else 'изменён'} «{oid}»", {"section": section_id, "id": oid, "path": path})
    await session.commit()
    return {"ok": True, "path": path}


@router.delete("/sections/{section_id}/objects/{oid}")
async def delete_object(section_id: str, oid: str, request: Request,
                        admin: AdminUser = Depends(editor), session: AsyncSession = Depends(get_session)):
    s = sec.get_section(section_id)
    ws = await drf.workspace(session)
    if sec.get_object(ws, s, oid) is None:
        raise HTTPException(404, f"Объекта «{oid}» нет")
    patch = {"id": "manual-delete", "format_version": 1, "section": section_id, "description": "Удаление",
             "operations": [{"op": "delete", "id": oid}]}
    plan = _plan_from_patch(ws, patch, {})
    if plan.errors:
        raise HTTPException(422, {"message": "Удалить нельзя", "errors": plan.errors})
    await _apply_plan(session, admin.id, plan)
    await audit(session, request, admin, "object_delete", f"{s['title']}: удалён «{oid}»", {"section": section_id, "id": oid})
    await session.commit()
    return {"ok": True}


# --- Файлы (картинки, JSON) -------------------------------------------------------------

@router.get("/files")
async def get_file(path: str, admin: AdminUser = Depends(editor), session: AsyncSession = Depends(get_session)):
    ws = await drf.workspace(session)
    await session.commit()
    try:
        data = ws.read_bytes(path)
    except KeyError:
        raise HTTPException(404, f"Файла {path} нет")
    media = "application/json" if path.endswith(".json") else "application/octet-stream"
    return Response(data, media_type=media)


@router.put("/files")
async def put_file(request: Request, path: str, admin: AdminUser = Depends(editor), session: AsyncSession = Depends(get_session)):
    data = await request.body()
    try:
        res = await drf.put_file(session, admin.id, path, data)
    except ContentError as e:
        raise content_error(e)
    await audit(session, request, admin, "file_put", f"Загружен файл {res['path']}", {"path": res["path"], "size": len(data)})
    await session.commit()
    return res


@router.delete("/files")
async def delete_file(request: Request, path: str, admin: AdminUser = Depends(editor), session: AsyncSession = Depends(get_session)):
    try:
        await drf.delete_file(session, admin.id, path)
    except ContentError as e:
        raise content_error(e)
    await audit(session, request, admin, "file_delete", f"Удалён файл {path}", {"path": path})
    await session.commit()
    return {"ok": True}


@router.get("/schemas/{name}")
async def get_schema(name: str, admin: AdminUser = Depends(editor)):
    path = get_settings().shared_dir / "schemas" / name
    if "/" in name or not name.endswith(".schema.json") or not path.is_file():
        raise HTTPException(404, "Схема не найдена")
    return json.loads(path.read_text(encoding="utf-8"))


# --- Черновик, тест, публикация, откат --------------------------------------------------

@router.get("/draft")
async def get_draft(admin: AdminUser = Depends(editor), session: AsyncSession = Depends(get_session)):
    """Изменения черновика и все файлы «как будет после публикации» (для предпросмотра в админке)."""
    from app.models import DraftFile
    data = await drf.changes(session)
    ws = await drf.workspace(session)
    sizes = {}
    if ws.base is not None:
        for pkg in ws.base.manifest.get("packages", []):
            for f in pkg["files"]:
                sizes[f["path"]] = f["size"]
    for r in (await session.execute(select(DraftFile))).scalars():
        sizes[r.path] = r.size
    data["files"] = {p: {"sha256": sha, "size": int(sizes.get(p, 0))} for p, sha in ws.files().items() if p != drf.PACKAGES}
    data["base_url"] = get_settings().public_content_files_url
    await session.commit()
    return data


class RevertIn(BaseModel):
    path: str | None = None


@router.post("/draft/revert")
async def revert(body: RevertIn, request: Request, admin: AdminUser = Depends(editor), session: AsyncSession = Depends(get_session)):
    n = await drf.revert(session, body.path)
    await audit(session, request, admin, "draft_revert",
                f"Отменена правка {body.path}" if body.path else f"Черновик сброшен ({n} правок)", {"path": body.path, "count": n})
    await session.commit()
    return {"ok": True, "reverted": n}


@router.post("/draft/rebase")
async def rebase(request: Request, admin: AdminUser = Depends(editor), session: AsyncSession = Depends(get_session)):
    await drf.rebase(session)
    await audit(session, request, admin, "draft_rebase", "Черновик перенесён на текущую версию игры")
    await session.commit()
    return {"ok": True}


class PublishIn(BaseModel):
    comment: str = Field(default="", max_length=500)
    confirm: bool = False


async def _build(session, comment: str) -> ContentRelease:
    try:
        release, _ = await drf.build_release(session, comment)
    except ContentError as e:
        raise content_error(e)
    return release


@router.post("/draft/test")
async def draft_to_test(body: PublishIn, request: Request, admin: AdminUser = Depends(editor),
                        session: AsyncSession = Depends(get_session)):
    """Собрать черновик в версию и показать её только тестовым аккаунтам (канал test)."""
    release = await _build(session, body.comment or "Черновик на тест")
    await publish(session, release.id, "test")
    await audit(session, request, admin, "draft_test", f"Версия №{release.id} отправлена на тест",
                {"release": release.id, "comment": body.comment})
    await session.commit()
    return {"ok": True, "release": release.id, "channel": "test"}


@router.post("/draft/publish")
async def draft_publish(body: PublishIn, request: Request, admin: AdminUser = Depends(editor),
                        session: AsyncSession = Depends(get_session)):
    """Опубликовать черновик сразу всем игрокам (с подтверждением)."""
    if not body.confirm:
        raise HTTPException(400, "Подтвердите публикацию для всех игроков")
    release = await _build(session, body.comment or "Публикация из админки")
    for ch in CHANNELS:
        await publish(session, release.id, ch)
    await drf.clear_after_publish(session, release)
    await audit(session, request, admin, "publish", f"Версия №{release.id} опубликована для всех",
                {"release": release.id, "comment": body.comment, "from": "draft"})
    await session.commit()
    return {"ok": True, "release": release.id, "channel": "live"}


@router.get("/releases")
async def releases(limit: int = Query(30, ge=1, le=200), admin: AdminUser = Depends(editor),
                   session: AsyncSession = Depends(get_session)):
    channels = {c.name: c.release_id for c in (await session.execute(select(ContentChannel))).scalars()}
    rows = (await session.execute(select(ContentRelease).order_by(ContentRelease.id.desc()).limit(limit))).scalars()
    return {"channels": channels, "items": [
        {"id": r.id, "at": r.created_at.isoformat(), "source": r.source, "comment": r.comment, "files": r.files_count,
         "size": r.total_size, "channels": [n for n, rid in channels.items() if rid == r.id]} for r in rows]}


class ReleasePublishIn(BaseModel):
    channel: str = Field(pattern="^(live|test)$")
    confirm: bool = False


@router.post("/releases/{release_id}/publish")
async def release_publish(release_id: int, body: ReleasePublishIn, request: Request,
                          admin: AdminUser = Depends(editor), session: AsyncSession = Depends(get_session)):
    """Опубликовать проверенную версию или откатиться к любой прошлой."""
    if body.channel == "live" and not body.confirm:
        raise HTTPException(400, "Подтвердите публикацию для всех игроков")
    old = await get_channel_release(session, body.channel)
    try:
        await publish(session, release_id, body.channel)
        if body.channel == "live":
            await publish(session, release_id, "test")
    except ContentError as e:
        raise HTTPException(404, e.messages[0])
    rollback = old is not None and release_id < old.id
    action = "rollback" if rollback and body.channel == "live" else "publish" if body.channel == "live" else "test"
    await audit(session, request, admin, action,
                f"{'Откат' if action == 'rollback' else 'Публикация'}: канал {body.channel} → версия №{release_id}",
                {"release": release_id, "channel": body.channel, "previous": old.id if old else None})
    data = await drf.changes(session)
    if body.channel == "live" and not data["changes"]:
        await drf.rebase(session)  # черновик пуст — следующая правка начнётся от новой версии
    await session.commit()
    return {"ok": True, "release": release_id, "channel": body.channel,
            "draft_outdated": body.channel == "live" and bool(data["changes"])}


# --- ZIP-патчи, выгрузка, промпт ------------------------------------------------------

def _plan_from_patch(ws, patch: dict, files: dict):
    import io
    import zipfile
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr("patch.json", json.dumps(patch, ensure_ascii=False))
        for p, d in files.items():
            zf.writestr("files/" + p, d)
    return sec.plan_patch(ws, buf.getvalue())


async def _apply_plan(session, admin_id, plan) -> None:
    try:
        for path, data in plan.writes.items():
            await drf.put_file(session, admin_id, path, data)
        for path in plan.deletes:
            if path not in plan.writes:
                await drf.delete_file(session, admin_id, path)
    except ContentError as e:
        raise content_error(e)


def _plan_payload(plan) -> dict:
    return {"ok": not plan.errors, "patch": {k: plan.patch.get(k) for k in ("id", "section", "description", "author")},
            "changes": plan.changes, "errors": plan.errors[:200], "warnings": plan.warnings,
            "writes": sorted(plan.writes), "deletes": sorted(plan.deletes)}


@router.post("/patches/preview")
async def patch_preview(request: Request, admin: AdminUser = Depends(editor), session: AsyncSession = Depends(get_session)):
    """Разобрать ZIP-патч: что добавится, изменится, удалится. Ничего не меняет."""
    ws = await drf.workspace(session)
    plan = sec.plan_patch(ws, await request.body())
    await session.commit()
    return _plan_payload(plan)


@router.post("/patches/apply")
async def patch_apply(request: Request, admin: AdminUser = Depends(editor), session: AsyncSession = Depends(get_session)):
    """Применить ZIP-патч в черновик (дальше — тест и публикация)."""
    ws = await drf.workspace(session)
    plan = sec.plan_patch(ws, await request.body())
    if plan.errors:
        raise HTTPException(422, {"message": "Патч не прошёл проверку", "errors": plan.errors[:200]})
    await _apply_plan(session, admin.id, plan)
    await audit(session, request, admin, "patch_apply",
                f"Патч «{plan.patch.get('id')}» ({plan.patch.get('section')}): {len(plan.changes)} изменений",
                {"patch": plan.patch.get("id"), "section": plan.patch.get("section"),
                 "description": plan.patch.get("description"), "changes": plan.changes[:500]})
    await session.commit()
    return _plan_payload(plan)


@router.get("/sections/{section_id}/export")
async def export(section_id: str, request: Request, admin: AdminUser = Depends(editor), session: AsyncSession = Depends(get_session)):
    s = sec.get_section(section_id)
    ws = await drf.workspace(session)
    data = sec.export_section(ws, s)
    await audit(session, request, admin, "export", f"Выгрузка раздела «{s['title']}»", {"section": section_id})
    await session.commit()
    return Response(data, media_type="application/zip",
                    headers={"Content-Disposition": f'attachment; filename="{section_id}.zip"'})


@router.get("/sections/{section_id}/prompt")
async def prompt(section_id: str, admin: AdminUser = Depends(editor), session: AsyncSession = Depends(get_session)):
    s = sec.get_section(section_id)
    ws = await drf.workspace(session)
    text = sec.ai_prompt(ws, s)
    await session.commit()
    return {"prompt": text}


# --- Герой целиком и скины (этап 6в-2) -----------------------------------------------------

def _hero_dir_files(ws, hero_id: str) -> list[str]:
    prefix = f"heroes/{hero_id}/"
    return sorted(p for p in ws.files() if p.startswith(prefix))


def _skin_base_files(ws, hero: dict, hero_id: str) -> list[str]:
    """Картинки обычного вида, которые копируются в новый скин: части скелета, портрет, полный арт."""
    out = []
    art = hero.get("art", {})
    for key in ("portrait", "full", "projectile"):
        if art.get(key):
            out.append(str(art[key]))
    try:
        skel = ws.read_json(str(art.get("skeleton", f"heroes/{hero_id}/skeleton.json")))
        for slot in skel.get("slots", []):
            out.append(f"heroes/{hero_id}/{slot['image']}")
    except (KeyError, ValueError):
        pass
    return sorted({p for p in out if ws.exists(p)})


@router.get("/heroes/{hero_id}/export")
async def export_hero(hero_id: str, request: Request, admin: AdminUser = Depends(editor),
                      session: AsyncSession = Depends(get_session)):
    """Герой целиком одним ZIP (формат патча): hero.json, скелет и анимации, все картинки и скины."""
    import io
    import zipfile
    ws = await drf.workspace(session)
    path = f"heroes/{hero_id}/hero.json"
    if not ws.exists(path):
        raise HTTPException(404, "Герой не найден")
    files = [p for p in _hero_dir_files(ws, hero_id) if p != path]
    patch = {"id": f"hero-{hero_id.replace('_', '-')}", "format_version": 1, "section": "heroes",
             "description": f"Герой «{ws.read_json(path).get('name', hero_id)}» целиком",
             "operations": [{"op": "update", "id": hero_id, "data": ws.read_json(path), "files": files}]}
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("patch.json", json.dumps(patch, ensure_ascii=False, indent=2))
        zf.writestr("README.txt", "Герой целиком. Замените картинки в files/ (те же имена и размеры, PNG с прозрачностью),\n"
                    "поправьте patch.json при необходимости и загрузите в админке: «ZIP-патч».\n"
                    "Скины лежат в files/heroes/<герой>/skins/<скин>/ — те же пути, что у обычного вида.\n")
        for p in files:
            zf.writestr("files/" + p, ws.read_bytes(p))
    await audit(session, request, admin, "export", f"Выгрузка героя «{hero_id}»", {"hero": hero_id})
    await session.commit()
    return Response(buf.getvalue(), media_type="application/zip",
                    headers={"Content-Disposition": f'attachment; filename="hero_{hero_id}.zip"'})


class NewSkinIn(BaseModel):
    skin: str = Field(pattern=r"^[a-z][a-z0-9_]{0,31}$")
    name: str = Field(min_length=1, max_length=60)
    free: bool = False


@router.post("/heroes/{hero_id}/skins")
async def create_skin(hero_id: str, body: NewSkinIn, request: Request, admin: AdminUser = Depends(editor),
                      session: AsyncSession = Depends(get_session)):
    """Новый скин = копия картинок обычного вида в heroes/<id>/skins/<скин>/ (дальше их заменяют)."""
    ws = await drf.workspace(session)
    path = f"heroes/{hero_id}/hero.json"
    if not ws.exists(path):
        raise HTTPException(404, "Герой не найден")
    if body.skin == "default":
        raise HTTPException(422, "«default» — обычный вид, выберите другое имя")
    hero = ws.read_json(path)
    skins = hero.setdefault("skins", [])
    if any(s["id"] == body.skin for s in skins):
        raise HTTPException(409, f"Скин «{body.skin}» уже есть")
    prefix = f"heroes/{hero_id}/"
    copied = 0
    try:
        for p in _skin_base_files(ws, hero, hero_id):
            rel = p[len(prefix):]
            await drf.put_file(session, admin.id, f"{prefix}skins/{body.skin}/{rel}", ws.read_bytes(p))
            copied += 1
        skins.append({"id": body.skin, "name": body.name, "free": body.free})
        await drf.put_json(session, admin.id, path, hero)
    except ContentError as e:
        raise content_error(e)
    await audit(session, request, admin, "skin_create", f"Герой «{hero_id}»: новый скин «{body.name}» ({copied} картинок)",
                {"hero": hero_id, "skin": body.skin})
    await session.commit()
    return {"ok": True, "skin": body.skin, "files": copied}


@router.delete("/heroes/{hero_id}/skins/{skin_id}")
async def delete_skin(hero_id: str, skin_id: str, request: Request, admin: AdminUser = Depends(editor),
                      session: AsyncSession = Depends(get_session)):
    ws = await drf.workspace(session)
    path = f"heroes/{hero_id}/hero.json"
    if not ws.exists(path):
        raise HTTPException(404, "Герой не найден")
    hero = ws.read_json(path)
    before = len(hero.get("skins", []))
    hero["skins"] = [s for s in hero.get("skins", []) if s["id"] != skin_id]
    if len(hero["skins"]) == before:
        raise HTTPException(404, "Такого скина нет")
    if not hero["skins"]:
        hero.pop("skins")
    try:
        await drf.put_json(session, admin.id, path, hero)
        for p in _hero_dir_files(ws, hero_id):
            if p.startswith(f"heroes/{hero_id}/skins/{skin_id}/"):
                await drf.delete_file(session, admin.id, p)
    except ContentError as e:
        raise content_error(e)
    await audit(session, request, admin, "skin_delete", f"Герой «{hero_id}»: удалён скин «{skin_id}»",
                {"hero": hero_id, "skin": skin_id})
    await session.commit()
    return {"ok": True}

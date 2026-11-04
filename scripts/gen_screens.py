#!/usr/bin/env python3
"""Раскладки экранов по умолчанию: content/ui/screens/<экран>.json и их копия в client/layouts/
(встроены в APK — на случай, если контент ещё не скачан). Повторяют прежний вид экранов.
Дальше раскладки правятся в админке («Конструктор экранов»). Запуск из корня: python3 scripts/gen_screens.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HUB = json.loads((ROOT / "content/ui/hub.json").read_text("utf-8"))


def title(text):
    return {"id": "title", "type": "label", "x": 0, "y": 36, "w": 720, "h": 56, "text": text, "size": 40, "color": "accent"}


def back(text="На главный экран", y=1180):
    return {"id": "back", "type": "button", "x": 48, "y": y, "w": 624, "h": 84, "text": text, "action": {"call": "back"}}


def content(y=100, h=1070):
    return {"id": "content", "type": "slot", "widget": "content", "x": 48, "y": y, "w": 624, "h": h,
            "note": "Живое содержимое экрана (списки, карточки, кнопки действий)"}


def menu(name, text, extra=None, content_h=1070):
    els = [title(text), content(h=content_h), back()]
    return {"screen": name, "title": text, "background": {"color": "background"}, "elements": els + (extra or [])}


def hub():
    els = [{"id": "city_map", "type": "slot", "widget": "city", "x": 0, "y": 0, "w": 720, "h": 1280,
            "note": "Город: фон и здания (здания двигаются в «Главный экран: двигать здания»)"},
           {"id": "shade", "type": "panel", "x": 0, "y": 0, "w": 720, "h": 210, "color": "#0A0819E6", "gradient": "down"},
           {"id": "avatar", "type": "slot", "widget": "avatar", "x": 14, "y": 30, "w": 128, "h": 128},
           {"id": "player_name", "type": "slot", "widget": "player_name", "x": 156, "y": 30, "w": 168, "h": 36},
           {"id": "stage", "type": "slot", "widget": "stage", "x": 156, "y": 66, "w": 170, "h": 48},
           {"id": "power", "type": "slot", "widget": "power", "x": 148, "y": 118, "w": 170, "h": 46},
           {"id": "gold", "type": "slot", "widget": "gold", "x": 330, "y": 30, "w": 180, "h": 52},
           {"id": "crystals", "type": "slot", "widget": "crystals", "x": 526, "y": 30, "w": 180, "h": 52}]
    x = 600
    for item in reversed(HUB.get("top_buttons", [])):
        els.append({"id": item["id"], "type": "button", "style": "icon", "icon": item["icon"], "text": item.get("title", ""),
                    "x": x, "y": 100, "w": 84, "h": 84, "action": item["action"], **({"badge": item["badge"]} if "badge" in item else {})})
        x -= 104
    for i, item in enumerate(HUB.get("side_menu", [])):
        els.append({"id": item["id"], "type": "button", "style": "tile", "icon": item["icon"], "text": item["title"],
                    "x": 8, "y": 214 + i * 116, "w": 108, "h": 108, "action": item["action"],
                    **({"badge": item["badge"]} if "badge" in item else {})})
    els.append({"id": "nav_bg", "type": "panel", "x": 6, "y": 1134, "w": 708, "h": 140, "color": "#171229F5",
                "border": "#C4923A", "border_width": 3, "radius": 26})
    nav = HUB.get("bottom_nav", [])
    cw = 708 / max(1, len(nav))
    for i, item in enumerate(nav):
        big = bool(item.get("big"))
        els.append({"id": item["id"], "type": "button", "style": "nav_big" if big else "nav", "icon": item["icon"],
                    "text": item["title"], "x": round(6 + i * cw + 4), "y": 1096 if big else 1138,
                    "w": round(cw - 8), "h": 174 if big else 132, "size": 24 if big else 22, "action": item["action"],
                    **({"badge": item["badge"]} if "badge" in item else {})})
    # Привязка групп: верхняя панель и левое меню — к верху, нижняя навигация — к низу, город — во весь экран
    for e in els:
        if e["id"] == "city_map":
            e["anchor"] = "stretch"
        elif e["id"] == "nav_bg" or e.get("style") in ("nav", "nav_big"):
            e["anchor"] = "bottom"
        else:
            e["anchor"] = "top"
    return {"screen": "hub", "title": "Главный экран", "background": {"color": "background"}, "elements": els}


def boot():
    return {"screen": "boot", "title": "Загрузка", "background": {"color": "background"}, "elements": [
        {"id": "logo", "type": "label", "x": 0, "y": 360, "w": 720, "h": 80, "text": "{game_name}", "size": 56, "color": "accent"},
        {"id": "subtitle", "type": "label", "x": 0, "y": 446, "w": 720, "h": 50, "text": "Легенды Урала оживают…", "size": 28},
        {"id": "status", "type": "slot", "widget": "status", "x": 48, "y": 760, "w": 624, "h": 130},
        {"id": "bar", "type": "slot", "widget": "bar", "x": 48, "y": 900, "w": 624, "h": 44},
        {"id": "size", "type": "slot", "widget": "size", "x": 48, "y": 956, "w": 624, "h": 40},
        {"id": "retry", "type": "slot", "widget": "retry", "x": 48, "y": 1010, "w": 624, "h": 96},
        {"id": "later", "type": "slot", "widget": "later", "x": 48, "y": 1114, "w": 624, "h": 80},
        {"id": "version", "type": "label", "x": 0, "y": 1210, "w": 720, "h": 40, "text": "Версия {version}", "size": 22,
         "anchor": "bottom"}]}


def _center(screen):
    for e in screen["elements"]:
        e.setdefault("anchor", "center")
    return screen


def battle():
    return {"screen": "battle", "title": "Бой", "background": {"color": "background", "image": "campaign/chapter_1/background.png", "alpha": 0.55},
            "elements": [
                {"id": "ground", "type": "panel", "x": 0, "y": 350, "w": 720, "h": 620, "color": "#1A291F8C"},
                {"id": "title", "type": "slot", "widget": "title", "x": 0, "y": 40, "w": 720, "h": 40},
                {"id": "timer", "type": "slot", "widget": "timer", "x": 0, "y": 84, "w": 720, "h": 40},
                {"id": "portraits", "type": "slot", "widget": "portraits", "x": 20, "y": 960, "w": 680, "h": 140,
                 "note": "Портреты своих героев: нажатие — ультимейт"},
                {"id": "controls", "type": "slot", "widget": "controls", "x": 20, "y": 1130, "w": 680, "h": 100,
                 "note": "Кнопки «Авто», скорость, «Пропустить»"}]}


SCREENS = {
    "hub": hub(), "boot": _center(boot()), "battle": battle(),
    "heroes": menu("heroes", "Герои"),
    "inventory": menu("inventory", "Инвентарь"),
    "summon": menu("summon", "Призыв героев", content_h=960, extra=[
        {"id": "to_heroes", "type": "button", "x": 48, "y": 1080, "w": 624, "h": 84, "text": "К героям", "action": {"scene": "heroes"}}]),
    "campaign": menu("campaign", "Кампания"),
    # {heading} — экран подставляет «Тестовый бой» или «Кампания — этап 1-1»
    "team_select": {**menu("team_select", "{heading}"), "elements": [title("{heading}"), content(h=1070), back("Назад")]},
}

def _check_unique(screens):
    for name, sc in screens.items():
        ids = [e["id"] for e in sc["elements"]]
        dup = {i for i in ids if ids.count(i) > 1}
        assert not dup, f"{name}: повторяются id {dup}"


if __name__ == "__main__":
    _check_unique(SCREENS)
    for d in (ROOT / "content/ui/screens", ROOT / "client/layouts"):
        d.mkdir(parents=True, exist_ok=True)
        for name, data in SCREENS.items():
            (d / f"{name}.json").write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", "utf-8")
    print("экраны:", ", ".join(SCREENS))

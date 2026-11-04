#!/usr/bin/env python3
"""Собирает docs/art-prompts.md — промпты для ИИ-генерации картинок игры.

Стиль взят из опроса по интерфейсу (docs/decisions.md). Список героев, глав и баннеров
читается из content/, поэтому после добавления героя достаточно перезапустить:

    python3 scripts/gen_art_prompts.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTENT = ROOT / "content"
OUT = ROOT / "docs" / "art-prompts.md"

STYLE = (
    "anime fantasy mobile game art, Bashkir folk epic setting (Ural mountains, steppe, birch and pine forests), "
    "rich emerald green and warm gold color palette, Bashkir ornament motifs (kushtirnak horns, tulip and "
    "wave patterns) as gold filigree accents, soft painterly shading, clean readable silhouettes, "
    "high detail, vibrant but not oversaturated"
)
NEGATIVE = (
    "text, letters, watermark, signature, logo, UI elements, frame borders (unless asked), photo, 3d render, "
    "chibi, blurry, low resolution, extra limbs, deformed hands, cropped head, modern objects, Japanese or "
    "Chinese architecture, European medieval castle"
)
KEY_BG = "isolated on a flat solid magenta (#FF00FF) background, no shadow on the background"

FACTION_LOOK = {
    "ural_batyrs": "Ural heroes: gold and emerald clothing, fur-trimmed kaftans, embroidered Bashkir patterns, mountain stone and living water motifs",
    "evil_spirits": "dark spirits: deep purple and wine-red, smoky aura, glowing eyes, eerie but stylish",
    "forest_spirits": "forest spirits: moss green and birch white, leaves, roots, water lilies, glowing fireflies",
    "steppe_nomads": "steppe nomads: terracotta and ochre, leather and felt, horsehair tassels, eagle feathers, wind",
    "sky_dwellers": "sky dwellers: white, pale gold and sky blue, bird wings and feathers, moonlight and clouds",
    "underworld": "underworld: obsidian black, lava orange, serpent scales, cave crystals",
}
ROLE_LOOK = {
    "tank": "massive armored defender with a big shield or club",
    "warrior": "agile melee fighter with a sword or spear",
    "assassin": "fast sneaky fighter with daggers or claws",
    "archer": "archer with a recurve composite bow",
    "mage": "spellcaster with glowing magic",
    "support": "healer / support with a staff or charm",
}
RARITY_LOOK = {
    "rare": "simple outfit",
    "elite": "ornate outfit with gold details",
    "legendary": "very ornate legendary outfit, glowing accents, heroic pose",
}
# Внешность героев (по описанию в hero.json). Новый герой без строки получит общий шаблон.
HERO_LOOK = {
    "aihylu": "young woman, daughter of the bird king, long silver hair, moonlight veil, crescent moon charm, small white wings",
    "albasty": "female evil spirit, extremely long black flowing hair hiding part of the face, pale skin, torn dark dress",
    "alpamysha": "giant hero, broad shoulders, heavy chainmail, round shield with gold ornament, calm strong face",
    "azhdaha": "fire-breathing serpent dragon, dark scales, glowing ember cracks, horns, coiled tail",
    "baksy": "old shaman, felt hat with feathers, frame drum (kubyz-like tambourine) with ornament, spirit wisps",
    "bisura": "small kind house spirit, round and fluffy, big bright eyes, tiny lantern",
    "deyeu": "huge horned div ogre, dark skin, iron bracers, heavy chain, servant of the underworld king",
    "forest_archer": "hunter spirit, bark-like armor, bow made of a rowan branch, leaf cloak",
    "humai": "young woman, daughter of the bird king Samrau, white and gold feathered dress, swan-like wings, healing light",
    "hyuhylu": "daughter of the water king, flowing blue-green hair like waves, pearls, water swirling around hands",
    "imp_evil": "small night ghoul, hunched, sharp teeth, ragged cloak, glowing red eyes",
    "katil": "underworld king, tall, black and gold armor with serpent motifs, crown of obsidian, cruel smile",
    "kusyak_biy": "wise stern steppe chieftain, grey beard, fur hat, rich kaftan, staff of authority",
    "mergen": "young horsewoman archer, braided hair, eagle feather, bow drawn, steppe wind in clothes",
    "militia_ural": "simple village defender, padded kaftan, wooden shield, spear",
    "samrau": "king of the birds, majestic old man with huge golden wings, sun and moon symbols, sky robes",
    "shulgen": "dark brother of Ural, warrior in black-green armor, corrupted gold ornament, serpent spear",
    "shurale": "forest trickster spirit with very long fingers, wooden horn on the forehead, bark skin, mischievous grin",
    "sky_guard": "young servant of the bird king, light armor with feathers, small wings, spear",
    "steppe_rider": "dashing nomad rider, leather armor, curved saber, fur-trimmed hat",
    "under_guard": "cave guard, stone-like armor with glowing crystals, heavy halberd",
    "ural_batyr": "legendary young hero, strong, gold-and-emerald kaftan with ornament, legendary sword, flask of living water on the belt",
    "urman_huzha": "ancient forest guardian, giant made of oak and roots, moss beard, glowing green eyes",
    "zarkum": "son of the serpent king, handsome young man with snake-like eyes, green scales on neck and hands, curved dagger",
    "zayatulyak": "skilled hunter, fur cloak, bow, water lily charm (loves a water maiden)",
}

CHAPTER_LOOK = {
    1: "old Ufa fortress city on a hill above the Belaya river, wooden walls, yurts and log houses",
    2: "Iremel mountain, rocky peaks, alpine tundra, fog, echoing gorges",
    3: "Shulgan-Tash cave, huge karst cave entrance, underground river, ancient wall paintings",
    4: "Yangan-Tau 'burnt mountain', hot steam from cracks, red rocks, glowing embers",
    5: "Lake Aslykul, wide blue lake surrounded by hills, mist over water, dark shadow under the surface",
}

BUILDINGS = [
    ("building_summon.png", "Призыв (Храм призыва)", "ancient sacred temple of summoning on a hill, stone and carved wood, tall roof with gold kushtirnak ornament, glowing portal light inside"),
    ("building_fortress.png", "Крепость (герои)", "wooden-stone Bashkir fortress with towers, banners with gold ornament, main gate"),
    ("building_tavern.png", "Таверна (доска заданий)", "cozy log tavern, smoke from chimney, quest notice board at the door, warm windows"),
    ("building_arena.png", "Арена", "round open arena with wooden stands and banners, sand field, festival flags (sabantuy feeling)"),
    ("building_campaign.png", "Кампания", "war camp with a map table under a felt tent, yurt, horses, signal fire"),
    ("building_dungeon.png", "Подземелья (Башня испытаний)", "dark stone tower growing out of a cave entrance, glowing runes, mysterious light"),
    ("building_guild.png", "Гильдия", "large ornate yurt-hall of the guild, gold and green felt, tribe banners"),
    ("building_forge.png", "Кузница (появится в 7а)", "blacksmith forge, anvil, glowing furnace, hanging tools and swords"),
]

ICONS = [
    ("icon_mail.png", "Почта", "sealed scroll letter with gold wax seal"),
    ("icon_quests.png", "Задания", "open parchment scroll with a feather quill and checkmark"),
    ("icon_tasks.png", "Ежедневные задания", "parchment with a sun symbol"),
    ("icon_events.png", "События", "festive golden drum with ribbons"),
    ("icon_rewards.png", "Награды", "small open chest with gold coins"),
    ("icon_battle_pass.png", "Боевой пропуск", "gold medallion on an ornamented ribbon"),
    ("icon_daily.png", "Ежедневный вход", "calendar tablet carved in wood with ornament"),
    ("icon_settings.png", "Настройки", "gold gear with Bashkir ornament"),
    ("icon_heroes.png", "Герои", "crossed sword and shield"),
    ("icon_inventory.png", "Сумка", "leather bag with ornament"),
    ("icon_world.png", "Кампания / мир", "rolled map with a compass"),
    ("icon_city.png", "Город", "small fortress tower"),
    ("icon_friends.png", "Друзья / чат (появится в 7а)", "two speech bubbles with gold ornament"),
]
CURRENCY = [
    ("icon_coin.png", "Золото", "gold coin with tulip ornament"),
    ("icon_crystal.png", "Кристаллы", "glowing emerald crystal"),
    ("icon_power.png", "Сила", "fist with lightning in a gold circle"),
    ("icon_plus.png", "Плюс (магазин)", "small round green button with a gold plus"),
]
ITEMS = [
    ("weapon_strength.png", "Оружие силы", "heavy broadsword"),
    ("weapon_agility.png", "Оружие ловкости", "curved saber and dagger"),
    ("weapon_mystic.png", "Магическое оружие", "magic staff with a crystal"),
    ("helmet.png", "Шлем", "pointed Bashkir warrior helmet with aventail"),
    ("armor.png", "Доспех", "chainmail with ornamented chest plate"),
    ("boots.png", "Сапоги", "leather riding boots with embroidery"),
    ("ore.png", "Руда", "chunk of ore with gold veins"),
    ("legacy_shards.png", "Осколки наследия", "glowing fragments of an ancient amulet"),
]
UI_KIT = [
    ("Панель окна (9-slice)", "ui/kit/panel.png", "1024×1024",
     "game UI window panel, dark emerald green velvet center, thick gold border with Bashkir ornament on edges and corners, the center is plain and empty, front view, flat, symmetric"),
    ("Кнопка (9-slice)", "ui/button.png", "768×256",
     "game UI button, rounded rectangle, emerald green gradient with gold rim and small ornament on the left and right ends, empty middle, front view, symmetric"),
    ("Разделитель", "ui/kit/divider.png", "1536×128",
     "horizontal decorative divider line, gold Bashkir ornament with a central kushtirnak motif, symmetric"),
    ("Нижнее меню (подложка)", "ui/kit/nav_bar.png", "1440×320",
     "bottom navigation bar background for a mobile game, dark green carved wood with gold ornament along the top edge, plain middle"),
    ("Рамка редкости: редкий", "ui/kit/frame_rare.png", "512×512",
     "square portrait frame, silver-blue metal, thin simple ornament, empty transparent center"),
    ("Рамка редкости: элитный", "ui/kit/frame_elite.png", "512×512",
     "square portrait frame, purple enamel and gold, medium Bashkir ornament on corners, empty center"),
    ("Рамка редкости: легендарный", "ui/kit/frame_legendary.png", "512×512",
     "square portrait frame, rich gold with glowing gems, dense Bashkir ornament, small wings on top corners, radiant glow, empty center"),
    ("Значок «новое» (красная точка)", "ui/kit/badge.png", "128×128",
     "small round red gem with a gold rim, glossy"),
]


def load_json(p):
    return json.loads(Path(p).read_text(encoding="utf-8"))


def block(text):
    return "```\n" + text + "\n```\n"


def main():
    heroes = [load_json(p) for p in sorted((CONTENT / "heroes").glob("*/hero.json"))]
    factions = {f["id"]: f for f in load_json(CONTENT / "factions" / "factions.json")["factions"]}
    chapters = [load_json(p) for p in sorted((CONTENT / "campaign").glob("*/chapter.json"))]
    banners = load_json(CONTENT / "summon" / "banners.json")["banners"]

    o = []
    w = o.append
    w("# Промпты для ИИ-генерации картинок\n")
    w("Файл собирается командой `python3 scripts/gen_art_prompts.py` (не правьте вручную — правки пропадут; "
      "меняйте сам скрипт). Стиль взят из опроса по интерфейсу: аниме-фэнтези, зелёный + золото, "
      "башкирский орнамент (`docs/decisions.md`).\n")
    w("## Как пользоваться\n")
    w("1. Скопируйте **общий стиль** и допишите к нему промпт картинки (стиль — в начало).")
    w("2. В поле «negative prompt» (если генератор его поддерживает) вставьте **запрет**.")
    w("3. Генерируйте в размере из колонки «Генерировать». В игре картинка сама уменьшится; "
      "важно соблюсти **пропорции** (соотношение сторон), иначе края обрежутся.")
    w("4. Картинки «на прозрачном фоне» почти все генераторы рисуют на сплошном цвете. Мы просим "
      "**пурпурный фон #FF00FF** — его нет в палитре игры, поэтому он легко удаляется: в админке "
      "(нарезчик 6в-3) или любым сервисом удаления фона. Сохраняйте в **PNG**.")
    w("5. Замена: админка → **Картинки игры** → группа → нажать картинку → «Заменить» → "
      "**Черновик** → «Опубликовать». Для новых файлов — «+ Загрузить новый файл» с путём из таблицы.")
    w("6. Чтобы картинки были в одном стиле, генерируйте серию (иконки, здания) в одном чате/сессии "
      "и прикладывайте уже готовую картинку как образец стиля (style reference), если генератор умеет.\n")
    w("Пометка «(появится в 7а)» — файла в игре ещё нет; его место появится на этапе интерфейса 7а. "
      "Сгенерировать можно заранее.\n")

    w("## Общий стиль (вставлять в начало каждого промпта)\n")
    w(block(STYLE))
    w("## Запрет (negative prompt)\n")
    w(block(NEGATIVE))

    w("## 1. Загрузка и вход\n")
    w("| Файл | Генерировать | Промпт |\n|---|---|---|")
    w(f"| `ui/loading_bg.png` | 1080×1920 (9:16) | vertical key art, Ural-batyr and Humai standing on a cliff above the Ural mountains at sunrise, golden light, epic atmosphere, empty space at the bottom third for a loading bar |")
    w(f"| `ui/logo.png` | 1024×1024 | game emblem: golden kushtirnak ornament around a stylized eagle and mountain, emerald gem in the center, {KEY_BG} |")
    w(f"| `ui/hub/emblem.png` | 1560×600 | wide decorative title plate, gold ornamented banner with emerald ribbon ends, empty center for the game name, {KEY_BG} |")
    w("")

    w("## 2. Главный экран (город)\n")
    w("Фон города — длинная вертикальная картинка, которую листают пальцем. **Здания на фон не рисуйте** — "
      "они отдельными картинками сверху (их места двигаются в админке). На фоне нужны пустые площадки.\n")
    w("| Файл | Генерировать | Промпт |\n|---|---|---|")
    w("| `ui/hub/background.webp` | 1440×2800 (≈1:1.94; если нельзя — 1080×1920 и дорисовать верх/низ) | "
      "top-down isometric view of a fantasy Bashkir valley town map, Belaya river winding through, green hills, "
      "birch groves, dirt roads connecting 8 empty flat clearings for buildings, mountains at the top edge, "
      "no buildings, game map background |")
    for f, name, p in BUILDINGS:
        w(f"| `ui/hub/{f}` — {name} | 1024×1024 | isometric game building, {p}, {KEY_BG} |")
    w("")
    w("### Иконки (боковое меню, верхняя панель, нижнее меню)\n")
    w("Общий хвост для всех иконок: `game icon, centered, bold silhouette, gold rim, " + KEY_BG + "`\n")
    w("| Файл | Что | Генерировать | Промпт |\n|---|---|---|---|")
    for f, name, p in ICONS:
        w(f"| `ui/hub/{f}` | {name} | 512×512 | {p} |")
    for f, name, p in CURRENCY:
        w(f"| `ui/hub/{f}` | {name} | 512×512 | {p} |")
    w("")

    w("## 3. Элементы интерфейса (рамки, кнопки, окна)\n")
    w("На этапе 7а эти элементы будут нарисованы кодом, а если загрузить файл по указанному пути — игра возьмёт картинку вместо кода "
      "(сейчас из них в игре есть только `ui/button.png`). "
      "**9-slice** — картинку растягивают за середину, поэтому орнамент только по краям и углам, середина ровная.\n")
    w("| Что | Файл | Генерировать | Промпт |\n|---|---|---|---|")
    for name, f, size, p in UI_KIT:
        w(f"| {name} | `{f}` | {size} | {p}, {KEY_BG} |")
    w("")

    w("## 4. Призыв\n")
    w("| Файл | Генерировать | Промпт |\n|---|---|---|")
    w("| `ui/summon/background.png` (появится в 7а) | 1080×1920 | interior of an ancient sacred temple, "
      "carved wooden pillars with gold ornament, glowing summoning circle on the floor, light beams from above, "
      "empty center for a hero |")
    for b in banners:
        feat = "; ".join(HERO_LOOK.get(x, x) for x in b.get("featured", []))
        if feat:
            subj = f"featured hero in the center: {feat}"
        elif b["type"] == "faction":
            subj = "group of heroes, " + "; ".join(FACTION_LOOK.get(f, f) for f in b["factions"])
        else:
            subj = "silhouettes of several heroes of different factions, mystery light"
        look = ""
        w(f"| `ui/summon/banner_{b['id']}.png` — {b['name']} (появится в 7а) | 1440×720 (2:1) | "
          f"horizontal summon banner art, {subj}{', ' + look if look else ''}, dramatic light, empty right third for text |")
    w("| Вспышки редкости | — | рисуются эффектом в коде, картинки не нужны |")
    w("")

    w("## 5. Кампания и бой\n")
    w("Карта главы — рисованная карта с тропой; точки этапов ставятся поверх в админке, на карте их не рисуйте. "
      "Фон главы используется и в бою — нижняя треть должна быть ровной землёй, где стоят герои.\n")
    w("| Файл | Генерировать | Промпт |\n|---|---|---|")
    for c in chapters:
        n = c["number"]
        look = CHAPTER_LOOK.get(n, c["title"])
        w(f"| `campaign/{c['id']}/map.png` — гл. {n} «{c['title']}» | 1440×800 (9:5) | hand-drawn fantasy "
          f"parchment map, {look}, winding dotted trail across the map, decorative gold ornament corners |")
        w(f"| `campaign/{c['id']}/background.png` — фон боя гл. {n} | 1080×1920 (9:16) | side view battle "
          f"background, {look}, flat ground in the lower third, no characters |")
    w("")

    w("## 6. Предметы (сумка, снаряжение)\n")
    w("| Файл | Что | Генерировать | Промпт |\n|---|---|---|---|")
    for f, name, p in ITEMS:
        w(f"| `ui/items/{f}` | {name} | 512×512 | game item icon, {p}, Bashkir ornament, gold rim, {KEY_BG} |")
    w("")

    w("## 7. Обучение\n")
    w("| Файл | Генерировать | Промпт |\n|---|---|---|")
    w(f"| `ui/tutorial/narrator.png` (появится в 7в) | 1024×1280 | old Bashkir storyteller sesen, white beard, "
      f"felt hat, holding a kurai flute, kind smile, waist-up, {KEY_BG} |")
    w("")

    w("## 8. Герои\n")
    w("На каждого героя три картинки:\n")
    w("- **Портрет** `heroes/<id>/portrait.png` — 512×512, лицо и плечи (в игре 128×128, в рамке редкости).")
    w("- **Полный арт** `heroes/<id>/full.png` — 1024×1280 (4:5), в полный рост, для экрана героя.")
    w("- **Лист для анимации** — 1024×1280, тот же герой **сбоку, смотрит вправо**, руки опущены и "
      "чуть отведены от тела, ноги слегка расставлены, оружие отдельно не перекрывает тело. Его режет нарезчик "
      "6в-3 на части (голова, туловище, руки, ноги, оружие) — загружать в админке «Герои» → герой (кнопка загрузки рисунка появится в 6в-3).\n")
    w("Хвосты к промпту героя:\n")
    w("- портрет: `bust portrait, face and shoulders, looking at viewer, " + KEY_BG + "`")
    w("- полный арт: `full body, dynamic heroic pose, " + KEY_BG + "`")
    w("- лист: `full body side view facing right, neutral standing pose, arms slightly away from the body, "
      "legs apart, weapon held clear of the body, flat even lighting, " + KEY_BG + "`")
    w("- скин: добавьте в конец `alternative skin: <тема, например winter festival outfit, white fur and blue ornament>` "
      "и загрузите в нужный скин героя.\n")
    w("| Герой | Фракция, роль, редкость | Промпт героя |\n|---|---|---|")
    for h in heroes:
        hid = h["id"]
        fac = factions.get(h.get("faction"), {})
        look = HERO_LOOK.get(hid, h.get("description", ""))
        parts = [look, FACTION_LOOK.get(h.get("faction"), ""), ROLE_LOOK.get(h.get("role"), ""),
                 RARITY_LOOK.get(h.get("rarity"), "")]
        prompt = ", ".join(p for p in parts if p)
        w(f"| **{h['name']}** (`{hid}`) | {fac.get('name', h.get('faction'))}, {h.get('role')}, {h.get('rarity')} | {prompt} |")
    w("")
    missing = [h["id"] for h in heroes if h["id"] not in HERO_LOOK]
    if missing:
        w("> Для героев " + ", ".join(f"`{m}`" for m in missing) +
          " нет описания внешности в скрипте — взят текст из hero.json. Допишите строку в `HERO_LOOK`.\n")

    OUT.write_text("\n".join(o) + "\n", encoding="utf-8")
    print(f"{OUT.relative_to(ROOT)}: {len(heroes)} героев, {len(chapters)} глав, {len(banners)} баннеров")


if __name__ == "__main__":
    main()

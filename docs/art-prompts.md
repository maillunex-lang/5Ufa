# Промпты для ИИ-генерации картинок

Файл собирается командой `python3 scripts/gen_art_prompts.py` (не правьте вручную — правки пропадут; меняйте сам скрипт). Стиль взят из опроса по интерфейсу: аниме-фэнтези, зелёный + золото, башкирский орнамент (`docs/decisions.md`).

## Как пользоваться

1. Скопируйте **общий стиль** и допишите к нему промпт картинки (стиль — в начало).
2. В поле «negative prompt» (если генератор его поддерживает) вставьте **запрет**.
3. Генерируйте в размере из колонки «Генерировать». В игре картинка сама уменьшится; важно соблюсти **пропорции** (соотношение сторон), иначе края обрежутся.
4. Картинки «на прозрачном фоне» почти все генераторы рисуют на сплошном цвете. Мы просим **пурпурный фон #FF00FF** — его нет в палитре игры, поэтому он легко удаляется: в админке (нарезчик 6в-3) или любым сервисом удаления фона. Сохраняйте в **PNG**.
5. Замена: админка → **Картинки игры** → группа → нажать картинку → «Заменить» → **Черновик** → «Опубликовать». Для новых файлов — «+ Загрузить новый файл» с путём из таблицы.
6. Чтобы картинки были в одном стиле, генерируйте серию (иконки, здания) в одном чате/сессии и прикладывайте уже готовую картинку как образец стиля (style reference), если генератор умеет.

Пометка «(появится в 7а)» — файла в игре ещё нет; его место появится на этапе интерфейса 7а. Сгенерировать можно заранее.

## Общий стиль (вставлять в начало каждого промпта)

```
anime fantasy mobile game art, Bashkir folk epic setting (Ural mountains, steppe, birch and pine forests), rich emerald green and warm gold color palette, Bashkir ornament motifs (kushtirnak horns, tulip and wave patterns) as gold filigree accents, soft painterly shading, clean readable silhouettes, high detail, vibrant but not oversaturated
```

## Запрет (negative prompt)

```
text, letters, watermark, signature, logo, UI elements, frame borders (unless asked), photo, 3d render, chibi, blurry, low resolution, extra limbs, deformed hands, cropped head, modern objects, Japanese or Chinese architecture, European medieval castle
```

## 1. Загрузка и вход

| Файл | Генерировать | Промпт |
|---|---|---|
| `ui/loading_bg.png` | 1080×1920 (9:16) | vertical key art, Ural-batyr and Humai standing on a cliff above the Ural mountains at sunrise, golden light, epic atmosphere, empty space at the bottom third for a loading bar |
| `ui/logo.png` | 1024×1024 | game emblem: golden kushtirnak ornament around a stylized eagle and mountain, emerald gem in the center, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background |
| `ui/hub/emblem.png` | 1560×600 | wide decorative title plate, gold ornamented banner with emerald ribbon ends, empty center for the game name, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background |

## 2. Главный экран (город)

Фон города — длинная вертикальная картинка, которую листают пальцем. **Здания на фон не рисуйте** — они отдельными картинками сверху (их места двигаются в админке). На фоне нужны пустые площадки.

| Файл | Генерировать | Промпт |
|---|---|---|
| `ui/hub/background.webp` | 1440×2800 (≈1:1.94; если нельзя — 1080×1920 и дорисовать верх/низ) | top-down isometric view of a fantasy Bashkir valley town map, Belaya river winding through, green hills, birch groves, dirt roads connecting 8 empty flat clearings for buildings, mountains at the top edge, no buildings, game map background |
| `ui/hub/building_summon.png` — Призыв (Храм призыва) | 1024×1024 | isometric game building, ancient sacred temple of summoning on a hill, stone and carved wood, tall roof with gold kushtirnak ornament, glowing portal light inside, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background |
| `ui/hub/building_fortress.png` — Крепость (герои) | 1024×1024 | isometric game building, wooden-stone Bashkir fortress with towers, banners with gold ornament, main gate, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background |
| `ui/hub/building_tavern.png` — Таверна (доска заданий) | 1024×1024 | isometric game building, cozy log tavern, smoke from chimney, quest notice board at the door, warm windows, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background |
| `ui/hub/building_arena.png` — Арена | 1024×1024 | isometric game building, round open arena with wooden stands and banners, sand field, festival flags (sabantuy feeling), isolated on a flat solid magenta (#FF00FF) background, no shadow on the background |
| `ui/hub/building_campaign.png` — Кампания | 1024×1024 | isometric game building, war camp with a map table under a felt tent, yurt, horses, signal fire, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background |
| `ui/hub/building_dungeon.png` — Подземелья (Башня испытаний) | 1024×1024 | isometric game building, dark stone tower growing out of a cave entrance, glowing runes, mysterious light, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background |
| `ui/hub/building_guild.png` — Гильдия | 1024×1024 | isometric game building, large ornate yurt-hall of the guild, gold and green felt, tribe banners, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background |
| `ui/hub/building_forge.png` — Кузница (появится в 7а) | 1024×1024 | isometric game building, blacksmith forge, anvil, glowing furnace, hanging tools and swords, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background |

### Иконки (боковое меню, верхняя панель, нижнее меню)

Общий хвост для всех иконок: `game icon, centered, bold silhouette, gold rim, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background`

| Файл | Что | Генерировать | Промпт |
|---|---|---|---|
| `ui/hub/icon_mail.png` | Почта | 512×512 | sealed scroll letter with gold wax seal |
| `ui/hub/icon_quests.png` | Задания | 512×512 | open parchment scroll with a feather quill and checkmark |
| `ui/hub/icon_tasks.png` | Ежедневные задания | 512×512 | parchment with a sun symbol |
| `ui/hub/icon_events.png` | События | 512×512 | festive golden drum with ribbons |
| `ui/hub/icon_rewards.png` | Награды | 512×512 | small open chest with gold coins |
| `ui/hub/icon_battle_pass.png` | Боевой пропуск | 512×512 | gold medallion on an ornamented ribbon |
| `ui/hub/icon_daily.png` | Ежедневный вход | 512×512 | calendar tablet carved in wood with ornament |
| `ui/hub/icon_settings.png` | Настройки | 512×512 | gold gear with Bashkir ornament |
| `ui/hub/icon_heroes.png` | Герои | 512×512 | crossed sword and shield |
| `ui/hub/icon_inventory.png` | Сумка | 512×512 | leather bag with ornament |
| `ui/hub/icon_world.png` | Кампания / мир | 512×512 | rolled map with a compass |
| `ui/hub/icon_city.png` | Город | 512×512 | small fortress tower |
| `ui/hub/icon_friends.png` | Друзья / чат (появится в 7а) | 512×512 | two speech bubbles with gold ornament |
| `ui/hub/icon_coin.png` | Золото | 512×512 | gold coin with tulip ornament |
| `ui/hub/icon_crystal.png` | Кристаллы | 512×512 | glowing emerald crystal |
| `ui/hub/icon_power.png` | Сила | 512×512 | fist with lightning in a gold circle |
| `ui/hub/icon_plus.png` | Плюс (магазин) | 512×512 | small round green button with a gold plus |

## 3. Элементы интерфейса (рамки, кнопки, окна)

На этапе 7а эти элементы будут нарисованы кодом, а если загрузить файл по указанному пути — игра возьмёт картинку вместо кода (сейчас из них в игре есть только `ui/button.png`). **9-slice** — картинку растягивают за середину, поэтому орнамент только по краям и углам, середина ровная.

| Что | Файл | Генерировать | Промпт |
|---|---|---|---|
| Панель окна (9-slice) | `ui/kit/panel.png` | 1024×1024 | game UI window panel, dark emerald green velvet center, thick gold border with Bashkir ornament on edges and corners, the center is plain and empty, front view, flat, symmetric, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background |
| Кнопка (9-slice) | `ui/button.png` | 768×256 | game UI button, rounded rectangle, emerald green gradient with gold rim and small ornament on the left and right ends, empty middle, front view, symmetric, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background |
| Разделитель | `ui/kit/divider.png` | 1536×128 | horizontal decorative divider line, gold Bashkir ornament with a central kushtirnak motif, symmetric, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background |
| Нижнее меню (подложка) | `ui/kit/nav_bar.png` | 1440×320 | bottom navigation bar background for a mobile game, dark green carved wood with gold ornament along the top edge, plain middle, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background |
| Рамка редкости: редкий | `ui/kit/frame_rare.png` | 512×512 | square portrait frame, silver-blue metal, thin simple ornament, empty transparent center, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background |
| Рамка редкости: элитный | `ui/kit/frame_elite.png` | 512×512 | square portrait frame, purple enamel and gold, medium Bashkir ornament on corners, empty center, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background |
| Рамка редкости: легендарный | `ui/kit/frame_legendary.png` | 512×512 | square portrait frame, rich gold with glowing gems, dense Bashkir ornament, small wings on top corners, radiant glow, empty center, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background |
| Значок «новое» (красная точка) | `ui/kit/badge.png` | 128×128 | small round red gem with a gold rim, glossy, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background |

## 4. Призыв

| Файл | Генерировать | Промпт |
|---|---|---|
| `ui/summon/background.png` (появится в 7а) | 1080×1920 | interior of an ancient sacred temple, carved wooden pillars with gold ornament, glowing summoning circle on the floor, light beams from above, empty center for a hero |
| `ui/summon/banner_normal.png` — Обычный призыв (появится в 7а) | 1440×720 (2:1) | horizontal summon banner art, silhouettes of several heroes of different factions, mystery light, dramatic light, empty right third for text |
| `ui/summon/banner_faction_ural_batyrs.png` — Призыв: Батыры Урала (появится в 7а) | 1440×720 (2:1) | horizontal summon banner art, group of heroes, Ural heroes: gold and emerald clothing, fur-trimmed kaftans, embroidered Bashkir patterns, mountain stone and living water motifs, dramatic light, empty right third for text |
| `ui/summon/banner_faction_evil_spirits.png` — Призыв: Нечисть (появится в 7а) | 1440×720 (2:1) | horizontal summon banner art, group of heroes, dark spirits: deep purple and wine-red, smoky aura, glowing eyes, eerie but stylish, dramatic light, empty right third for text |
| `ui/summon/banner_faction_forest_spirits.png` — Призыв: Лесные духи (появится в 7а) | 1440×720 (2:1) | horizontal summon banner art, group of heroes, forest spirits: moss green and birch white, leaves, roots, water lilies, glowing fireflies, dramatic light, empty right third for text |
| `ui/summon/banner_faction_steppe_nomads.png` — Призыв: Степные кочевники (появится в 7а) | 1440×720 (2:1) | horizontal summon banner art, group of heroes, steppe nomads: terracotta and ochre, leather and felt, horsehair tassels, eagle feathers, wind, dramatic light, empty right third for text |
| `ui/summon/banner_event_humai.png` — Баннер: Хумай (появится в 7а) | 1440×720 (2:1) | horizontal summon banner art, featured hero in the center: young woman, daughter of the bird king Samrau, white and gold feathered dress, swan-like wings, healing light, dramatic light, empty right third for text |
| Вспышки редкости | — | рисуются эффектом в коде, картинки не нужны |

## 5. Кампания и бой

Карта главы — рисованная карта с тропой; точки этапов ставятся поверх в админке, на карте их не рисуйте. Фон главы используется и в бою — нижняя треть должна быть ровной землёй, где стоят герои.

| Файл | Генерировать | Промпт |
|---|---|---|
| `campaign/chapter_1/map.png` — гл. 1 «Уфа» | 1440×800 (9:5) | hand-drawn fantasy parchment map, old Ufa fortress city on a hill above the Belaya river, wooden walls, yurts and log houses, winding dotted trail across the map, decorative gold ornament corners |
| `campaign/chapter_1/background.png` — фон боя гл. 1 | 1080×1920 (9:16) | side view battle background, old Ufa fortress city on a hill above the Belaya river, wooden walls, yurts and log houses, flat ground in the lower third, no characters |
| `campaign/chapter_2/map.png` — гл. 2 «Иремель» | 1440×800 (9:5) | hand-drawn fantasy parchment map, Iremel mountain, rocky peaks, alpine tundra, fog, echoing gorges, winding dotted trail across the map, decorative gold ornament corners |
| `campaign/chapter_2/background.png` — фон боя гл. 2 | 1080×1920 (9:16) | side view battle background, Iremel mountain, rocky peaks, alpine tundra, fog, echoing gorges, flat ground in the lower third, no characters |
| `campaign/chapter_3/map.png` — гл. 3 «Шульган-Таш» | 1440×800 (9:5) | hand-drawn fantasy parchment map, Shulgan-Tash cave, huge karst cave entrance, underground river, ancient wall paintings, winding dotted trail across the map, decorative gold ornament corners |
| `campaign/chapter_3/background.png` — фон боя гл. 3 | 1080×1920 (9:16) | side view battle background, Shulgan-Tash cave, huge karst cave entrance, underground river, ancient wall paintings, flat ground in the lower third, no characters |
| `campaign/chapter_4/map.png` — гл. 4 «Янган-Тау» | 1440×800 (9:5) | hand-drawn fantasy parchment map, Yangan-Tau 'burnt mountain', hot steam from cracks, red rocks, glowing embers, winding dotted trail across the map, decorative gold ornament corners |
| `campaign/chapter_4/background.png` — фон боя гл. 4 | 1080×1920 (9:16) | side view battle background, Yangan-Tau 'burnt mountain', hot steam from cracks, red rocks, glowing embers, flat ground in the lower third, no characters |
| `campaign/chapter_5/map.png` — гл. 5 «Озеро Аслыкуль» | 1440×800 (9:5) | hand-drawn fantasy parchment map, Lake Aslykul, wide blue lake surrounded by hills, mist over water, dark shadow under the surface, winding dotted trail across the map, decorative gold ornament corners |
| `campaign/chapter_5/background.png` — фон боя гл. 5 | 1080×1920 (9:16) | side view battle background, Lake Aslykul, wide blue lake surrounded by hills, mist over water, dark shadow under the surface, flat ground in the lower third, no characters |

## 6. Предметы (сумка, снаряжение)

| Файл | Что | Генерировать | Промпт |
|---|---|---|---|
| `ui/items/weapon_strength.png` | Оружие силы | 512×512 | game item icon, heavy broadsword, Bashkir ornament, gold rim, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background |
| `ui/items/weapon_agility.png` | Оружие ловкости | 512×512 | game item icon, curved saber and dagger, Bashkir ornament, gold rim, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background |
| `ui/items/weapon_mystic.png` | Магическое оружие | 512×512 | game item icon, magic staff with a crystal, Bashkir ornament, gold rim, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background |
| `ui/items/helmet.png` | Шлем | 512×512 | game item icon, pointed Bashkir warrior helmet with aventail, Bashkir ornament, gold rim, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background |
| `ui/items/armor.png` | Доспех | 512×512 | game item icon, chainmail with ornamented chest plate, Bashkir ornament, gold rim, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background |
| `ui/items/boots.png` | Сапоги | 512×512 | game item icon, leather riding boots with embroidery, Bashkir ornament, gold rim, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background |
| `ui/items/ore.png` | Руда | 512×512 | game item icon, chunk of ore with gold veins, Bashkir ornament, gold rim, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background |
| `ui/items/legacy_shards.png` | Осколки наследия | 512×512 | game item icon, glowing fragments of an ancient amulet, Bashkir ornament, gold rim, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background |

## 7. Обучение

| Файл | Генерировать | Промпт |
|---|---|---|
| `ui/tutorial/narrator.png` (появится в 7в) | 1024×1280 | old Bashkir storyteller sesen, white beard, felt hat, holding a kurai flute, kind smile, waist-up, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background |

## 8. Герои

На каждого героя три картинки:

- **Портрет** `heroes/<id>/portrait.png` — 512×512, лицо и плечи (в игре 128×128, в рамке редкости).
- **Полный арт** `heroes/<id>/full.png` — 1024×1280 (4:5), в полный рост, для экрана героя.
- **Лист для анимации** — 1024×1280, тот же герой **сбоку, смотрит вправо**, руки опущены и чуть отведены от тела, ноги слегка расставлены, оружие отдельно не перекрывает тело. Его режет нарезчик 6в-3 на части (голова, туловище, руки, ноги, оружие) — загружать в админке «Герои» → герой (кнопка загрузки рисунка появится в 6в-3).

Хвосты к промпту героя:

- портрет: `bust portrait, face and shoulders, looking at viewer, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background`
- полный арт: `full body, dynamic heroic pose, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background`
- лист: `full body side view facing right, neutral standing pose, arms slightly away from the body, legs apart, weapon held clear of the body, flat even lighting, isolated on a flat solid magenta (#FF00FF) background, no shadow on the background`
- скин: добавьте в конец `alternative skin: <тема, например winter festival outfit, white fur and blue ornament>` и загрузите в нужный скин героя.

| Герой | Фракция, роль, редкость | Промпт героя |
|---|---|---|
| **Айхылыу** (`aihylu`) | Небожители, support, legendary | young woman, daughter of the bird king, long silver hair, moonlight veil, crescent moon charm, small white wings, sky dwellers: white, pale gold and sky blue, bird wings and feathers, moonlight and clouds, healer / support with a staff or charm, very ornate legendary outfit, glowing accents, heroic pose |
| **Албасты** (`albasty`) | Нечисть, assassin, legendary | female evil spirit, extremely long black flowing hair hiding part of the face, pale skin, torn dark dress, dark spirits: deep purple and wine-red, smoky aura, glowing eyes, eerie but stylish, fast sneaky fighter with daggers or claws, very ornate legendary outfit, glowing accents, heroic pose |
| **Алпамыша** (`alpamysha`) | Батыры Урала, tank, legendary | giant hero, broad shoulders, heavy chainmail, round shield with gold ornament, calm strong face, Ural heroes: gold and emerald clothing, fur-trimmed kaftans, embroidered Bashkir patterns, mountain stone and living water motifs, massive armored defender with a big shield or club, very ornate legendary outfit, glowing accents, heroic pose |
| **Аждаха** (`azhdaha`) | Нечисть, mage, legendary | fire-breathing serpent dragon, dark scales, glowing ember cracks, horns, coiled tail, dark spirits: deep purple and wine-red, smoky aura, glowing eyes, eerie but stylish, spellcaster with glowing magic, very ornate legendary outfit, glowing accents, heroic pose |
| **Баксы** (`baksy`) | Степные кочевники, mage, legendary | old shaman, felt hat with feathers, frame drum (kubyz-like tambourine) with ornament, spirit wisps, steppe nomads: terracotta and ochre, leather and felt, horsehair tassels, eagle feathers, wind, spellcaster with glowing magic, very ornate legendary outfit, glowing accents, heroic pose |
| **Бисура** (`bisura`) | Лесные духи, support, legendary | small kind house spirit, round and fluffy, big bright eyes, tiny lantern, forest spirits: moss green and birch white, leaves, roots, water lilies, glowing fireflies, healer / support with a staff or charm, very ornate legendary outfit, glowing accents, heroic pose |
| **Дейеу** (`deyeu`) | Нечисть, tank, legendary | huge horned div ogre, dark skin, iron bracers, heavy chain, servant of the underworld king, dark spirits: deep purple and wine-red, smoky aura, glowing eyes, eerie but stylish, massive armored defender with a big shield or club, very ornate legendary outfit, glowing accents, heroic pose |
| **Лесной стрелок** (`forest_archer`) | Лесные духи, archer, rare | hunter spirit, bark-like armor, bow made of a rowan branch, leaf cloak, forest spirits: moss green and birch white, leaves, roots, water lilies, glowing fireflies, archer with a recurve composite bow, simple outfit |
| **Хумай** (`humai`) | Батыры Урала, support, legendary | young woman, daughter of the bird king Samrau, white and gold feathered dress, swan-like wings, healing light, Ural heroes: gold and emerald clothing, fur-trimmed kaftans, embroidered Bashkir patterns, mountain stone and living water motifs, healer / support with a staff or charm, very ornate legendary outfit, glowing accents, heroic pose |
| **Хыухылу** (`hyuhylu`) | Лесные духи, mage, legendary | daughter of the water king, flowing blue-green hair like waves, pearls, water swirling around hands, forest spirits: moss green and birch white, leaves, roots, water lilies, glowing fireflies, spellcaster with glowing magic, very ornate legendary outfit, glowing accents, heroic pose |
| **Упырь** (`imp_evil`) | Нечисть, assassin, rare | small night ghoul, hunched, sharp teeth, ragged cloak, glowing red eyes, dark spirits: deep purple and wine-red, smoky aura, glowing eyes, eerie but stylish, fast sneaky fighter with daggers or claws, simple outfit |
| **Катил-падиша** (`katil`) | Подземное царство, warrior, legendary | underworld king, tall, black and gold armor with serpent motifs, crown of obsidian, cruel smile, underworld: obsidian black, lava orange, serpent scales, cave crystals, agile melee fighter with a sword or spear, very ornate legendary outfit, glowing accents, heroic pose |
| **Кусяк-бий** (`kusyak_biy`) | Степные кочевники, tank, legendary | wise stern steppe chieftain, grey beard, fur hat, rich kaftan, staff of authority, steppe nomads: terracotta and ochre, leather and felt, horsehair tassels, eagle feathers, wind, massive armored defender with a big shield or club, very ornate legendary outfit, glowing accents, heroic pose |
| **Мерген** (`mergen`) | Степные кочевники, archer, legendary | young horsewoman archer, braided hair, eagle feather, bow drawn, steppe wind in clothes, steppe nomads: terracotta and ochre, leather and felt, horsehair tassels, eagle feathers, wind, archer with a recurve composite bow, very ornate legendary outfit, glowing accents, heroic pose |
| **Ополченец Урала** (`militia_ural`) | Батыры Урала, warrior, rare | simple village defender, padded kaftan, wooden shield, spear, Ural heroes: gold and emerald clothing, fur-trimmed kaftans, embroidered Bashkir patterns, mountain stone and living water motifs, agile melee fighter with a sword or spear, simple outfit |
| **Самрау** (`samrau`) | Небожители, mage, legendary | king of the birds, majestic old man with huge golden wings, sun and moon symbols, sky robes, sky dwellers: white, pale gold and sky blue, bird wings and feathers, moonlight and clouds, spellcaster with glowing magic, very ornate legendary outfit, glowing accents, heroic pose |
| **Шульген** (`shulgen`) | Нечисть, warrior, legendary | dark brother of Ural, warrior in black-green armor, corrupted gold ornament, serpent spear, dark spirits: deep purple and wine-red, smoky aura, glowing eyes, eerie but stylish, agile melee fighter with a sword or spear, very ornate legendary outfit, glowing accents, heroic pose |
| **Шурале** (`shurale`) | Лесные духи, assassin, legendary | forest trickster spirit with very long fingers, wooden horn on the forehead, bark skin, mischievous grin, forest spirits: moss green and birch white, leaves, roots, water lilies, glowing fireflies, fast sneaky fighter with daggers or claws, very ornate legendary outfit, glowing accents, heroic pose |
| **Небесный страж** (`sky_guard`) | Небожители, support, rare | young servant of the bird king, light armor with feathers, small wings, spear, sky dwellers: white, pale gold and sky blue, bird wings and feathers, moonlight and clouds, healer / support with a staff or charm, simple outfit |
| **Степной всадник** (`steppe_rider`) | Степные кочевники, warrior, rare | dashing nomad rider, leather armor, curved saber, fur-trimmed hat, steppe nomads: terracotta and ochre, leather and felt, horsehair tassels, eagle feathers, wind, agile melee fighter with a sword or spear, simple outfit |
| **Подземный страж** (`under_guard`) | Подземное царство, tank, rare | cave guard, stone-like armor with glowing crystals, heavy halberd, underworld: obsidian black, lava orange, serpent scales, cave crystals, massive armored defender with a big shield or club, simple outfit |
| **Урал-батыр** (`ural_batyr`) | Батыры Урала, warrior, legendary | legendary young hero, strong, gold-and-emerald kaftan with ornament, legendary sword, flask of living water on the belt, Ural heroes: gold and emerald clothing, fur-trimmed kaftans, embroidered Bashkir patterns, mountain stone and living water motifs, agile melee fighter with a sword or spear, very ornate legendary outfit, glowing accents, heroic pose |
| **Урман-хужа** (`urman_huzha`) | Лесные духи, tank, legendary | ancient forest guardian, giant made of oak and roots, moss beard, glowing green eyes, forest spirits: moss green and birch white, leaves, roots, water lilies, glowing fireflies, massive armored defender with a big shield or club, very ornate legendary outfit, glowing accents, heroic pose |
| **Заркум** (`zarkum`) | Подземное царство, assassin, legendary | son of the serpent king, handsome young man with snake-like eyes, green scales on neck and hands, curved dagger, underworld: obsidian black, lava orange, serpent scales, cave crystals, fast sneaky fighter with daggers or claws, very ornate legendary outfit, glowing accents, heroic pose |
| **Заятуляк** (`zayatulyak`) | Батыры Урала, archer, legendary | skilled hunter, fur cloak, bow, water lily charm (loves a water maiden), Ural heroes: gold and emerald clothing, fur-trimmed kaftans, embroidered Bashkir patterns, mountain stone and living water motifs, archer with a recurve composite bow, very ornate legendary outfit, glowing accents, heroic pose |


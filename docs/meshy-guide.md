# Meshy: подготовка 3D-героев

Пилот — Урал-батыр (`ural_batyr`). Существующий 2D-герой остаётся запасным вариантом. Интерфейс Meshy может меняться: названия ниже сверены с [официальной инструкцией Meshy по ригу](https://help.meshy.ai/en/articles/16231707-how-to-create-3d-animation-with-auto-rigging) и [импорту моделей](https://help.meshy.ai/en/articles/11973241-import-meshy-models-into-any-engine-unity-unreal-roblox-godot). Платные операции и стоимость смотрите в Meshy перед запуском.

## 1. Рисунок Урал-батыра

1. В `docs/art-prompts.md` найдите строку «Урал-батыр». Используйте её промпт героя и сделайте цельный рисунок в полный рост. Для рига удобны фронтальный или близкий к фронтальному вид, нейтральная поза, отдельно видимые руки и ноги; оружие не должно сливаться с телом.
2. Сохраните рисунок на своём устройстве. Проверьте: персонаж целиком виден, части тела не обрезаны; фон и посторонние предметы не мешают силуэту.

## 2. Модель в Meshy

1. Откройте https://www.meshy.ai/workspace и войдите в свой аккаунт. Выберите **Model → Image to 3D**, загрузите рисунок PNG/JPG/WebP размером до 20 МБ. Если фон мешает, воспользуйтесь **Remove Background**.
2. В **Model Type** выберите **Smart Topology** для игровой модели. Для человекоподобного Урал-батыра в настройке **Pose**, если она доступна, выберите **T-Pose** или **A-Pose**. Нажмите **Generate** и дождитесь модели в списке справа.
3. Начальная модель может быть белой: нажмите **Texture**, чтобы получить текстуры. До текстурирования при необходимости используйте **Remesh** для уменьшения числа полигонов.
4. Осмотрите модель со всех сторон. Проверьте лицо, силуэт, пальцы, оружие и отсутствие лишних частей. При необходимости исправьте исходный рисунок или повторите генерацию.
5. Выберите доступные настройки экспорта, стремясь к бюджету до 10 000 треугольников и текстурам не больше 1024×1024. Если такие точные настройки недоступны, экспортируйте доступный вариант: админка покажет предупреждение о превышении.
6. Сохраните текстурированную модель в формате GLB. Проверка: файл открывается в программе просмотра 3D и текстуры встроены в него.

## 3. Скелет и анимации

1. Откройте **Animate / Auto Rigging** для модели. Для Урал-батыра выберите **Humanoid** и нажмите **Rig**. Проверьте в предпросмотре деформации плеч, локтей, коленей и кистей; если версия Meshy предлагает изменить точки суставов, проверьте и их.
2. Выберите в библиотеке движений Meshy клипы из таблицы ниже. Названия в библиотеке могут отличаться: выбирайте по смыслу движения, а не по написанию.
3. Скачайте модель с ригом и анимациями как GLB. Если Meshy отдаёт анимации отдельно, сохраните GLB-файлы вместе и упакуйте в ZIP. Используйте файлы одной модели с совместимым скелетом; если скелеты различаются, перенос движения может не работать.
4. В админке откройте героя → «3D-модель», загрузите GLB или ZIP, выберите основной файл, сверьте предупреждения и сопоставьте движения. При необходимости отметьте момент удара, настройте размер, поворот, высоту и точки крепления.
5. Сохраните настройки в черновик → отправьте на тест → проверьте на тестовом аккаунте. Настоящий внешний вид Meshy и анимации на телефоне необходимо проверять на вашем GLB.

## Движения по ролям

| Событие | Танк / воин | Стрелок | Маг / поддержка | Убийца |
|---|---|---|---|---|
| idle | стойка с оружием | стойка лучника | спокойная стойка | лёгкая боевая стойка |
| walk | ходьба с оружием | ходьба с луком | ходьба с посохом | быстрая ходьба |
| attack | удар мечом / щитом | выстрел из лука | взмах посоха | удар кинжалами |
| skill | боевой приём | прицельный выстрел | заклинание | быстрый выпад |
| ultimate | сильный удар | мощный выстрел | большое заклинание | серия ударов |
| hit | реакция на удар | реакция на удар | реакция на удар | реакция на удар |
| death | падение | падение | падение | падение |
| victory | победная стойка | победная стойка | победная стойка | победная стойка |

Для негуманоидного персонажа сначала попробуйте подходящий Meshy риг. Если скелета нет, файл можно хранить как статичную модель; движения кодом добавляются на этапе 3D-2.

## Промпты для рисунков всех героев

Используйте описание соответствующего героя ниже вместе с общим стилем аниме-фэнтези из `docs/art-prompts.md`. Для Image to 3D нужен изображённый целиком персонаж, без обрезанных ног и скрытых рук.

| Герой | Описание для изображения |
|---|---|
| **Айхылыу** (`aihylu`) | young woman, daughter of the bird king, long silver hair, moonlight veil, crescent moon charm, small white wings, sky dwellers: white, pale gold and sky blue, bird wings and feathers, moonlight and clouds, healer / support with a staff or charm, very ornate legendary outfit, glowing accents, heroic pose |
| **Албасты** (`albasty`) | female evil spirit, extremely long black flowing hair hiding part of the face, pale skin, torn dark dress, dark spirits: deep purple and wine-red, smoky aura, glowing eyes, eerie but stylish, fast sneaky fighter with daggers or claws, very ornate legendary outfit, glowing accents, heroic pose |
| **Алпамыша** (`alpamysha`) | giant hero, broad shoulders, heavy chainmail, round shield with gold ornament, calm strong face, Ural heroes: gold and emerald clothing, fur-trimmed kaftans, embroidered Bashkir patterns, mountain stone and living water motifs, massive armored defender with a big shield or club, very ornate legendary outfit, glowing accents, heroic pose |
| **Аждаха** (`azhdaha`) | fire-breathing serpent dragon, dark scales, glowing ember cracks, horns, coiled tail, dark spirits: deep purple and wine-red, smoky aura, glowing eyes, eerie but stylish, spellcaster with glowing magic, very ornate legendary outfit, glowing accents, heroic pose |
| **Баксы** (`baksy`) | old shaman, felt hat with feathers, frame drum (kubyz-like tambourine) with ornament, spirit wisps, steppe nomads: terracotta and ochre, leather and felt, horsehair tassels, eagle feathers, wind, spellcaster with glowing magic, very ornate legendary outfit, glowing accents, heroic pose |
| **Бисура** (`bisura`) | small kind house spirit, round and fluffy, big bright eyes, tiny lantern, forest spirits: moss green and birch white, leaves, roots, water lilies, glowing fireflies, healer / support with a staff or charm, very ornate legendary outfit, glowing accents, heroic pose |
| **Дейеу** (`deyeu`) | huge horned div ogre, dark skin, iron bracers, heavy chain, servant of the underworld king, dark spirits: deep purple and wine-red, smoky aura, glowing eyes, eerie but stylish, massive armored defender with a big shield or club, very ornate legendary outfit, glowing accents, heroic pose |
| **Лесной стрелок** (`forest_archer`) | hunter spirit, bark-like armor, bow made of a rowan branch, leaf cloak, forest spirits: moss green and birch white, leaves, roots, water lilies, glowing fireflies, archer with a recurve composite bow, simple outfit |
| **Хумай** (`humai`) | young woman, daughter of the bird king Samrau, white and gold feathered dress, swan-like wings, healing light, Ural heroes: gold and emerald clothing, fur-trimmed kaftans, embroidered Bashkir patterns, mountain stone and living water motifs, healer / support with a staff or charm, very ornate legendary outfit, glowing accents, heroic pose |
| **Хыухылу** (`hyuhylu`) | daughter of the water king, flowing blue-green hair like waves, pearls, water swirling around hands, forest spirits: moss green and birch white, leaves, roots, water lilies, glowing fireflies, spellcaster with glowing magic, very ornate legendary outfit, glowing accents, heroic pose |
| **Упырь** (`imp_evil`) | small night ghoul, hunched, sharp teeth, ragged cloak, glowing red eyes, dark spirits: deep purple and wine-red, smoky aura, glowing eyes, eerie but stylish, fast sneaky fighter with daggers or claws, simple outfit |
| **Катил-падиша** (`katil`) | underworld king, tall, black and gold armor with serpent motifs, crown of obsidian, cruel smile, underworld: obsidian black, lava orange, serpent scales, cave crystals, agile melee fighter with a sword or spear, very ornate legendary outfit, glowing accents, heroic pose |
| **Кусяк-бий** (`kusyak_biy`) | wise stern steppe chieftain, grey beard, fur hat, rich kaftan, staff of authority, steppe nomads: terracotta and ochre, leather and felt, horsehair tassels, eagle feathers, wind, massive armored defender with a big shield or club, very ornate legendary outfit, glowing accents, heroic pose |
| **Мерген** (`mergen`) | young horsewoman archer, braided hair, eagle feather, bow drawn, steppe wind in clothes, steppe nomads: terracotta and ochre, leather and felt, horsehair tassels, eagle feathers, wind, archer with a recurve composite bow, very ornate legendary outfit, glowing accents, heroic pose |
| **Ополченец Урала** (`militia_ural`) | simple village defender, padded kaftan, wooden shield, spear, Ural heroes: gold and emerald clothing, fur-trimmed kaftans, embroidered Bashkir patterns, mountain stone and living water motifs, agile melee fighter with a sword or spear, simple outfit |
| **Самрау** (`samrau`) | king of the birds, majestic old man with huge golden wings, sun and moon symbols, sky robes, sky dwellers: white, pale gold and sky blue, bird wings and feathers, moonlight and clouds, spellcaster with glowing magic, very ornate legendary outfit, glowing accents, heroic pose |
| **Шульген** (`shulgen`) | dark brother of Ural, warrior in black-green armor, corrupted gold ornament, serpent spear, dark spirits: deep purple and wine-red, smoky aura, glowing eyes, eerie but stylish, agile melee fighter with a sword or spear, very ornate legendary outfit, glowing accents, heroic pose |
| **Шурале** (`shurale`) | forest trickster spirit with very long fingers, wooden horn on the forehead, bark skin, mischievous grin, forest spirits: moss green and birch white, leaves, roots, water lilies, glowing fireflies, fast sneaky fighter with daggers or claws, very ornate legendary outfit, glowing accents, heroic pose |
| **Небесный страж** (`sky_guard`) | young servant of the bird king, light armor with feathers, small wings, spear, sky dwellers: white, pale gold and sky blue, bird wings and feathers, moonlight and clouds, healer / support with a staff or charm, simple outfit |
| **Степной всадник** (`steppe_rider`) | dashing nomad rider, leather armor, curved saber, fur-trimmed hat, steppe nomads: terracotta and ochre, leather and felt, horsehair tassels, eagle feathers, wind, agile melee fighter with a sword or spear, simple outfit |
| **Подземный страж** (`under_guard`) | cave guard, stone-like armor with glowing crystals, heavy halberd, underworld: obsidian black, lava orange, serpent scales, cave crystals, massive armored defender with a big shield or club, simple outfit |
| **Урал-батыр** (`ural_batyr`) | legendary young hero, strong, gold-and-emerald kaftan with ornament, legendary sword, flask of living water on the belt, Ural heroes: gold and emerald clothing, fur-trimmed kaftans, embroidered Bashkir patterns, mountain stone and living water motifs, agile melee fighter with a sword or spear, very ornate legendary outfit, glowing accents, heroic pose |
| **Урман-хужа** (`urman_huzha`) | ancient forest guardian, giant made of oak and roots, moss beard, glowing green eyes, forest spirits: moss green and birch white, leaves, roots, water lilies, glowing fireflies, massive armored defender with a big shield or club, very ornate legendary outfit, glowing accents, heroic pose |
| **Заркум** (`zarkum`) | son of the serpent king, handsome young man with snake-like eyes, green scales on neck and hands, curved dagger, underworld: obsidian black, lava orange, serpent scales, cave crystals, fast sneaky fighter with daggers or claws, very ornate legendary outfit, glowing accents, heroic pose |
| **Заятуляк** (`zayatulyak`) | skilled hunter, fur cloak, bow, water lily charm (loves a water maiden), Ural heroes: gold and emerald clothing, fur-trimmed kaftans, embroidered Bashkir patterns, mountain stone and living water motifs, archer with a recurve composite bow, very ornate legendary outfit, glowing accents, heroic pose |

# Meshy: подготовка 3D-героев

Пилот — Урал-батыр (`ural_batyr`). Существующий 2D-герой остаётся запасным вариантом, пока в черновике нет принятой 3D-модели.

Интерфейс Meshy меняется. Названия кнопок ниже сверены со справкой Meshy (октябрь 2026), а не придуманы:

- [How to Use Meshy Image to 3D](https://help.meshy.ai/en/articles/9996860-how-to-use-meshy-image-to-3d) — обновлено на неделе проверки
- [A-Pose, T-Pose or Custom Poses](https://help.meshy.ai/en/articles/10255659-how-to-generate-3d-models-with-a-pose-t-pose-or-custom-poses)
- [Auto Rigging](https://help.meshy.ai/en/articles/16231707-how-to-create-3d-animation-with-auto-rigging) — обновлено на неделе проверки
- [Import into Godot](https://help.meshy.ai/en/articles/11973241-import-meshy-models-into-any-engine-unity-unreal-roblox-godot) — 28 июля 2026
- [Несколько анимаций одним файлом](https://help.meshy.ai/en/articles/11725598-how-do-i-export-multiple-animations-into-a-single-file-for-blender) — 27 июля 2026

Если кнопки на экране называются иначе, следуйте справке, а не этой странице. Платные операции и стоимость смотрите в Meshy перед запуском. Файл, скачанный из Meshy, этой инструкцией ещё не проверен: приёмка — загрузка вашего GLB в админку.

## Что админка вообще примет

Не любой GLB. Сервер до предпросмотра требует:

- один файл GLB версии 2.0, не больше 50 МиБ;
- геометрию и текстуры внутри файла, без внешних ссылок;
- без разреженных данных glTF (sparse) и без сжатия Draco, meshopt и Basis Universal (`KHR_texture_basisu`);
- ZIP, если анимации лежат отдельно: только файлы `.glb`, от 1 до 16, без пароля, без путей `..`, суммарно не больше 50 МиБ после распаковки.

Если файл не подходит, админка напишет причину и ничего не сохранит. Если сервер файл принял, а Godot в предпросмотре пишет ошибку — модель для игры ещё не годится. Ориентир бюджета: до 10 000 треугольников и текстура не больше 1024×1024. Превышение не блокирует загрузку, но показывается предупреждением. Число треугольников считается с повторами одной и той же сетки на сцене.

## 1. Рисунок Урал-батыра

1. В `docs/art-prompts.md` найдите строку «Урал-батыр». Используйте её промпт героя и сделайте цельный рисунок в полный рост. Для рига удобны фронтальный или близкий к фронтальному вид, нейтральная поза, отдельно видимые руки и ноги; оружие не должно сливаться с телом.
2. Сохраните рисунок на своём устройстве. Проверьте: персонаж целиком виден, части тела не обрезаны; фон и посторонние предметы не мешают силуэту.

## 2. Модель в Meshy

1. Откройте https://www.meshy.ai/workspace и войдите в свой аккаунт. Выберите **Model → Image to 3D**, загрузите рисунок PNG/JPG/WebP размером до 20 МБ. Если фон мешает и на экране есть **Remove Background**, нажмите её.
2. В **Model Type** выберите **Smart Topology** (для игры; **Standard** — более тяжёлая сетка). Для человекоподобного Урал-батыра включите переключатель **T-Pose** или **A-Pose**. По справке Meshy это Pose Control платного плана: на бесплатном аккаунте переключателя нет. Нажмите **Generate** и дождитесь модели в списке справа.
3. Начальная модель может быть белой: нажмите **Texture**. Если полигонов слишком много, до текстуры нажмите **Remesh** (в справке по quad-сетке это значок Remesh на нижней панели).
4. Осмотрите модель со всех сторон. Проверьте лицо, силуэт, пальцы, оружие и отсутствие лишних частей. Рядом с **Texture** может быть повтор генерации (**Free Retry**). При необходимости исправьте исходный рисунок.
5. Нажмите **Download**, выберите **.GLB**, затем доступное разрешение и **Export**. Справка Meshy пишет, что `.GLB` уже содержит текстуры. Отдельного обещания «ровно 10 000 треугольников и 1024×1024» в справке нет: возьмите ближайший лёгкий вариант, админка покажет фактические числа.
6. Проверка у себя: файл открывается в программе просмотра 3D, текстуры видны без отдельных картинок рядом с файлом.

## 3. Скелет и анимации

1. Откройте авториг модели (в справке: инструмент Auto Rigging, либо **Animate** / **Rig** у модели). Для Урал-батыра выберите тип **Humanoid**. Для четвероногого — **Quadruped**, для существа вне этих типов — **Smart Rig (Beta)**. Нажмите **Rig**. Имена костей Meshy делает в соглашении Mixamo. Проверьте деформации плеч, локтей, коленей и кистей.
2. Добавьте движения из библиотеки Meshy по таблице ниже. Названия в библиотеке могут отличаться: выбирайте по смыслу, а не по написанию. Для Humanoid движений больше; у Quadruped справка прямо говорит, что сейчас доступна в основном ходьба.
3. Скачайте риг и анимации как **GLB**. Для нескольких клипов справка Meshy (статья про Blender) указывает пункт **Download → Animation → All Added → Single File** — один файл со всеми добавленными движениями. Формат снова **GLB**.
4. Если вместо одного файла скачались отдельные GLB, сложите их в один ZIP без пароля и без вложенных архивов. Это должны быть файлы одной и той же модели. Чужой скелет админка не будет молча «подгонять»: предпросмотр откажется проигрывать несовместимый клип.
5. В админке откройте героя → «3D-модель выбранного вида», загрузите GLB или ZIP, выберите основной файл, прочитайте предупреждения и сопоставьте движения. Отметьте момент удара, размер, поворот, высоту и точки крепления. Если скелета нет, точку можно поставить на «Корень модели» (`@root`).
6. Сохраните настройки в черновик → отправьте на тест → откройте героя ещё раз и убедитесь, что файл, клипы и точки на месте. На телефон 3D попадёт только на этапе 3D-2; сейчас проверяется админка. Настоящий вид вашего файла Meshy нельзя считать проверенным, пока вы сами не загрузите его.

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

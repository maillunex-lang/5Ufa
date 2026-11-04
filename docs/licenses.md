# Источники графики и лицензии

| Что | Источник | Лицензия | Где лежит |
| --- | --- | --- | --- |
| Модели героев: Knight, Barbarian, Mage, Rogue_Hooded (с анимациями внутри файла; Rogue из набора в игре больше не используется и убран из репозитория) | KayKit Character Pack: Adventurers 1.0, Kay Lousberg, https://kaylousberg.itch.io/kaykit-adventurers (зеркало автора: https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0) | CC0 (текст в `client/assets/models/LICENSE-KayKit-Adventurers.txt`) | `client/assets/models/` |
| Модели врагов: Skeleton_Warrior, Skeleton_Rogue, Skeleton_Mage | KayKit Character Pack: Skeletons 1.0, https://kaylousberg.itch.io/kaykit-skeletons (https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0) | CC0 (`LICENSE-KayKit-Skeletons.txt`) | `client/assets/models/` |

Указание автора (не обязательное): Kay Lousberg, www.kaylousberg.com.

| Спецэффекты (огненная комета, магический снаряд, лечение): текстуры flame_04/05, fire_01/02, smoke_04/06, magic_04/05, star_04, circle_02 | Kenney Particle Pack 1.1, Kenney Vleugels, https://kenney.nl/assets/particle-pack (скачано из пакета для Godot: https://github.com/Calinou/kenney-particle-pack, в нём лицензия автора) | CC0 (`client/assets/vfx/LICENSE-Kenney-ParticlePack.txt`) | `client/assets/vfx/` |
| Графика интерфейса боя: каменная круглая арена, диск, значки ролей, скрещённые мечи | Собственная работа проекта, генерируется скриптом `tools/gen_ui_assets.py` (Pillow) | Принадлежит проекту, внешних ограничений нет | `client/assets/ui/` |
| Горный фон арены «Cold mountain» | OpenGameArt, набор Oil painting landscapes, https://opengameart.org/content/oil-painting-landscapes | CC0 | `client/assets/backgrounds/arena_mountains.png` |
| Прежний временный фон «Wizard tower» (в бою больше не используется) | | OpenGameArt, набор Oil painting landscapes, https://opengameart.org/content/oil-painting-landscapes | CC0 (указано на странице набора) | `client/assets/backgrounds/arena_wizardtower.png` |

## Соответствие моделей ролям (временное, утверждается владельцем)
Танк: Knight · Боец: Barbarian · Стрелок: Rogue_Hooded · Маг: Mage · Целитель: Priest (Meshy, сгенерирован 04.11.2026, см. ниже).
Враги: боец: Skeleton_Warrior · стрелок: Skeleton_Rogue · маг: Skeleton_Mage · **босс: Skeleton_Warrior, увеличен (отдельной модели босса в наборах нет)**.

## Проверено при скачивании (04.11.2026)
В каждом файле персонажа уже есть 76 анимаций (герои) и 95 (скелеты): `Idle`, `Running_A`, `1H_Melee_Attack_*`, `1H_Ranged_Shoot`, `Spellcast_*`, `Hit_A`, `Death_A` и др. Отдельный набор Character Animations для первой версии не нужен.

## Не скачано и почему
- Kenney UI Pack и Fantasy UI Borders: сайт kenney.nl недоступен из среды разработки (отвечает 403). Particle Pack получен через пакет для Godot на GitHub; для UI-наборов нужно искать зеркало с лицензией или скачать вручную.
- Рисованные фоны Kalponic: лицензия запрещает выкладку исходных файлов в публичный репозиторий и экспортируемые пакеты; хранить вне репозитория (см. спецификацию, раздел 9).

## Образец стиля
Запись экрана игры-образца (камера, расположение панелей, баннер умения) использована владельцем только как пример компоновки. Её графика, интерфейс и персонажи в проект не копируются.

## Meshy (пробная модель целителя)
Статус: **проба выполнена**, файл `client/assets/models/Priest.glb` (4,4 МБ, ~9,8 тыс. треугольников, скелет Mixamo из 24 костей, 7 анимаций: Idle_11, Running, Walking, Attack, Charged_Spell_Cast, Hit_Reaction, Dead). Модель Meshy T2.5, запрос в стиле KayKit (см. `docs/meshy-pilot.md`).
**Не записано (нужно от владельца):** какой тариф Meshy использовался и разрешает ли он коммерческое использование результата. Пока модель помечена тестовой (`visual._test`). Без подтверждения прав этот файл нельзя считать окончательным.

## Портреты героев
Не хранятся как файлы: рисуются при запуске боя из самих 3D-моделей (`client/portrait.gd`), поэтому следуют лицензиям моделей.

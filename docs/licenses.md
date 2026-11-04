# Источники графики и лицензии

| Что | Источник | Лицензия | Где лежит |
| --- | --- | --- | --- |
| Модели героев: Knight, Barbarian, Mage, Rogue, Rogue_Hooded (с анимациями внутри файла) | KayKit Character Pack: Adventurers 1.0, Kay Lousberg, https://kaylousberg.itch.io/kaykit-adventurers (зеркало автора: https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0) | CC0 (текст в `client/assets/models/LICENSE-KayKit-Adventurers.txt`) | `client/assets/models/` |
| Модели врагов: Skeleton_Warrior, Skeleton_Rogue, Skeleton_Mage | KayKit Character Pack: Skeletons 1.0, https://kaylousberg.itch.io/kaykit-skeletons (https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0) | CC0 (`LICENSE-KayKit-Skeletons.txt`) | `client/assets/models/` |

Указание автора (не обязательное): Kay Lousberg, www.kaylousberg.com.

## Соответствие моделей ролям (временное, утверждается владельцем)
Танк: Knight · Боец: Barbarian · Стрелок: Rogue_Hooded · Маг: Mage · **Целитель: Rogue (в наборе нет модели жреца, нужен подбор или своя)**.
Враги: боец: Skeleton_Warrior · стрелок: Skeleton_Rogue · маг: Skeleton_Mage · **босс: Skeleton_Warrior, увеличен (отдельной модели босса в наборах нет)**.

## Проверено при скачивании (04.11.2026)
В каждом файле персонажа уже есть 76 анимаций (герои) и 95 (скелеты): `Idle`, `Running_A`, `1H_Melee_Attack_*`, `1H_Ranged_Shoot`, `Spellcast_*`, `Hit_A`, `Death_A` и др. Отдельный набор Character Animations для первой версии не нужен.

## Не скачано и почему
- Kenney (UI Pack, Fantasy UI Borders, Particle Pack): сайт kenney.nl недоступен из среды разработки (отвечает 403); нужен другой способ получения.
- Рисованные фоны Kalponic: лицензия запрещает выкладку исходных файлов в публичный репозиторий и экспортируемые пакеты; хранить вне репозитория (см. спецификацию, раздел 9).

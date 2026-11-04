# spine-animation-ai (вендорный код)

Источник: https://github.com/GenielabsOpenSource/spine-animation-ai
(коммит 702b71689cac826efee942ee4564fef9560d6ef8, 2026-08-26).

Required Notice: Copyright (c) 2025 Spine Animation AI Contributors

Лицензия — PolyForm Noncommercial 1.0.0 (файл `LICENSE` рядом). **Только некоммерческое использование.**
До коммерческого релиза игры нужна лицензия Genielabs или замена этого кода (`docs/decisions.md`).

Что взято и что изменено (файл `atlas.py`):
- промпт «разобрать персонажа на отдельные части» из `scripts/split_character.py` — дополнен списком
  частей нашего шаблона скелета и требованием «смотрит вправо»;
- выделение частей на листе (связные области на белом фоне) из `split_character.py` — без записи файлов,
  возвращает картинки в памяти;
- поиск места части на исходном рисунке (SIFT + RANSAC, запасной вариант — поиск по шаблону) из
  `scripts/position_parts.py` — дополнительно возвращает матрицу преобразования, чтобы перенести часть
  на холст исходного рисунка.
Запрос к Gemini делается не через пакет google-genai, а через REST (`app/ai/gemini.py`).

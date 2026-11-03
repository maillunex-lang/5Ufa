# Промпт для ИИ: Тексты

Скопируйте текст ниже в ИИ-ассистента. Актуальная версия (с вашими правками) — кнопка «Промпт для ИИ» в разделе админки.

````text
Ты помогаешь наполнять контент мобильной игры (AFK RPG по мотивам башкирских легенд). Раздел: «Тексты» (localization).

Сделай ZIP-патч для админки. Структура архива:
  patch.json — описание патча
  files/<путь в контенте> — картинки и другие файлы

patch.json: {"id": "<латиница-и-дефисы>", "format_version": 1, "section": "localization", "description": "что меняется", "operations": [ ... ]}

Операции: add (новый объект, data — полный объект), update (data — только изменяемые поля; объекты сливаются, списки заменяются целиком), delete (удалить объект), put_file (положить файл: {"op":"put_file","path":"..."}), delete_file. Для add/update можно указать files — пути картинок из архива.

Правила: id и пути — латиница в нижнем регистре, цифры, _ - . /; JSON в UTF-8; графика PNG/WebP, звук OGG. Тексты — на русском.

Устройство объектов раздела: {"kind": "file_per_object", "path": "localization/{id}.json"}

Текущие объекты: ru (ru)

JSON Schema localization.schema.json:
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://schemas.ufagame.local/localization.schema.json",
  "title": "Тексты локализации (localization/<язык>.json)",
  "type": "object",
  "required": ["language", "strings"],
  "additionalProperties": false,
  "properties": {
    "$schema": {"type": "string"},
    "language": {"type": "string", "pattern": "^[a-z]{2}$"},
    "strings": {
      "type": "object",
      "propertyNames": {"$ref": "common.schema.json#/$defs/text_key"},
      "additionalProperties": {"type": "string"}
    }
  }
}


Пример объекта из игры:
{
  "language": "ru",
  "strings": {
    "loading.checking": "Проверка обновлений…",
    "loading.downloading": "Загрузка: {done} из {total}",
    "loading.verifying": "Проверка файлов…",
    "loading.error.network": "Нет связи с сервером. Повторить?",
    "loading.ready": "Готово!",
    "ui.button.play": "Играть",
    "ui.button.retry": "Повторить"
  }
}

Верни только готовый patch.json и список файлов, которые нужно положить в files/.
````

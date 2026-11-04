"""Безопасное чтение метаданных GLB 2.0 без исполнения стороннего кода."""
from __future__ import annotations

import io
import json
import struct
from PIL import Image, UnidentifiedImageError

MAX_GLB_BYTES = 50 * 1024 * 1024
MAX_IMAGE_PIXELS = 16_777_216
MAX_ITEMS = 100_000


class ModelError(ValueError):
    pass


def _list(document: dict, key: str) -> list:
    value = document.get(key, [])
    if not isinstance(value, list) or len(value) > MAX_ITEMS:
        raise ModelError(f"Неверный или слишком большой список {key}")
    return value


def _get(items: list, index, what: str) -> dict:
    if type(index) is not int or not 0 <= index < len(items) or not isinstance(items[index], dict):
        raise ModelError(f"Некорректная ссылка: {what}")
    return items[index]


def inspect_glb(data: bytes) -> dict:
    if len(data) > MAX_GLB_BYTES:
        raise ModelError("GLB больше 50 МиБ")
    if len(data) < 20:
        raise ModelError("GLB слишком короткий")
    magic, version, length = struct.unpack_from("<4sII", data)
    if magic != b"glTF" or version != 2 or length != len(data):
        raise ModelError("Ожидается корректный GLB версии 2")
    offset = 12
    chunks = []
    while offset < len(data):
        if offset + 8 > len(data):
            raise ModelError("Обрезан заголовок блока GLB")
        size, kind = struct.unpack_from("<I4s", data, offset)
        offset += 8
        if size % 4 or offset + size > len(data):
            raise ModelError("Некорректная длина блока GLB")
        chunks.append((kind, data[offset:offset + size]))
        offset += size
    if not chunks or chunks[0][0] != b"JSON" or sum(k == b"JSON" for k, _ in chunks) != 1:
        raise ModelError("В GLB должен быть один первый блок JSON")
    if sum(k == b"BIN\x00" for k, _ in chunks) > 1:
        raise ModelError("В GLB не может быть несколько блоков BIN")
    try:
        doc = json.loads(chunks[0][1].decode("utf-8").rstrip(" \t\r\n\x00"))
    except (UnicodeDecodeError, json.JSONDecodeError, RecursionError) as exc:
        raise ModelError("Повреждён JSON модели") from exc
    if not isinstance(doc, dict) or not isinstance(doc.get("asset"), dict) or doc["asset"].get("version") != "2.0":
        raise ModelError("Файл не соответствует glTF 2.0")
    blob = next((v for k, v in chunks if k == b"BIN\x00"), b"")
    buffers = _list(doc, "buffers")
    views = _list(doc, "bufferViews")
    accessors = _list(doc, "accessors")
    nodes = _list(doc, "nodes")
    images = _list(doc, "images")
    skins = _list(doc, "skins")
    animations = _list(doc, "animations")
    meshes = _list(doc, "meshes")
    for i, buf in enumerate(buffers):
        if not isinstance(buf, dict) or "uri" in buf:
            raise ModelError("Внешние буферы и ссылки в GLB не поддерживаются: вложите данные в файл")
        if i != 0 or type(buf.get("byteLength")) is not int or not 0 <= buf["byteLength"] <= len(blob):
            raise ModelError("Повреждён буфер GLB")
    for view in views:
        if not isinstance(view, dict) or view.get("buffer") != 0 or not buffers:
            raise ModelError("Некорректный буфер данных")
        start, size = view.get("byteOffset", 0), view.get("byteLength")
        if type(start) is not int or type(size) is not int or start < 0 or size < 0 or start + size > buffers[0]["byteLength"]:
            raise ModelError("Буфер выходит за пределы GLB")
    components = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
    widths = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}
    for accessor in accessors:
        if not isinstance(accessor, dict):
            raise ModelError("Некорректное описание данных модели")
        count, component, shape = accessor.get("count"), accessor.get("componentType"), accessor.get("type")
        if (type(count) is not int or not 0 <= count <= 100_000_000 or
                type(component) is not int or component not in components or not isinstance(shape, str) or shape not in widths):
            raise ModelError("Некорректный формат данных модели")
        if "sparse" in accessor:
            raise ModelError("Разреженные данные glTF пока не поддерживаются: экспортируйте обычный GLB")
        view = _get(views, accessor.get("bufferView"), "данные модели")
        start = accessor.get("byteOffset", 0)
        # Матрицы с однобайтовыми/двухбайтовыми компонентами требуют отдельного выравнивания.
        if shape in ("MAT2", "MAT3") and components[component] < 4:
            raise ModelError("Такой формат матрицы glTF пока не поддерживается")
        width = components[component] * widths[shape]
        stride = view.get("byteStride", width)
        if type(start) is not int or type(stride) is not int or start < 0 or stride < width:
            raise ModelError("Некорректное смещение данных модели")
        needed = start + ((count - 1) * stride + width if count else 0)
        if needed > view["byteLength"]:
            raise ModelError("Данные модели выходят за границы буфера")
    mesh_triangles = []
    for mesh in meshes:
        if not isinstance(mesh, dict) or not isinstance(mesh.get("primitives"), list):
            raise ModelError("Некорректная сетка модели")
        triangles_for_mesh = 0
        for primitive in mesh["primitives"]:
            if not isinstance(primitive, dict) or not isinstance(primitive.get("attributes"), dict):
                raise ModelError("Некорректная геометрия модели")
            pos = _get(accessors, primitive["attributes"].get("POSITION"), "POSITION")
            if pos.get("type") != "VEC3":
                raise ModelError("Позиции вершин должны содержать три координаты")
            acc = _get(accessors, primitive["indices"], "индексы") if "indices" in primitive else pos
            if "indices" in primitive and (acc.get("type") != "SCALAR" or acc.get("componentType") not in (5121, 5123, 5125)):
                raise ModelError("Некорректный формат индексов сетки")
            count = acc.get("count")
            if type(count) is not int or count < 0 or count > 100_000_000:
                raise ModelError("Некорректное количество вершин")
            mode = primitive.get("mode", 4)
            if mode == 4:
                triangles_for_mesh += count // 3
            elif mode in (5, 6):
                triangles_for_mesh += max(0, count - 2)
        mesh_triangles.append(triangles_for_mesh)
    triangles = 0
    mesh_instances = 0
    for node in nodes:
        if not isinstance(node, dict):
            raise ModelError("Некорректный узел модели")
        if "mesh" in node:
            _get(meshes, node["mesh"], "сетка узла")
            triangles += mesh_triangles[node["mesh"]]
            mesh_instances += 1
    image_sizes = []
    for item in images:
        if not isinstance(item, dict) or "uri" in item or "bufferView" not in item:
            raise ModelError("Текстуры должны быть встроены в GLB, внешние ссылки не поддерживаются")
        view = _get(views, item["bufferView"], "изображение")
        start = view.get("byteOffset", 0)
        raw = blob[start:start + view["byteLength"]]
        try:
            with Image.open(io.BytesIO(raw)) as im:
                w, h = im.size
                if w <= 0 or h <= 0 or w * h > MAX_IMAGE_PIXELS:
                    raise ModelError("Текстура слишком большая для безопасной проверки")
                im.verify()
                image_sizes.append({"width": w, "height": h, "format": im.format})
        except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError) as exc:
            if isinstance(exc, ModelError):
                raise
            raise ModelError("Не удалось прочитать встроенную текстуру") from exc
    clips = []
    for i, anim in enumerate(animations):
        if not isinstance(anim, dict):
            raise ModelError("Некорректная анимация")
        name = anim.get("name") or f"animation_{i}"
        if not isinstance(name, str) or len(name) > 200:
            raise ModelError("Некорректное имя анимации")
        samplers = anim.get("samplers", [])
        channels = anim.get("channels", [])
        if not isinstance(samplers, list) or not isinstance(channels, list) or len(samplers) > MAX_ITEMS or len(channels) > MAX_ITEMS:
            raise ModelError("Некорректные каналы анимации")
        for sampler in samplers:
            if not isinstance(sampler, dict):
                raise ModelError("Некорректная анимация")
            _get(accessors, sampler.get("input"), "время анимации")
            _get(accessors, sampler.get("output"), "значения анимации")
        for channel in channels:
            if not isinstance(channel, dict) or not isinstance(channel.get("target"), dict):
                raise ModelError("Некорректная цель анимации")
            _get(samplers, channel.get("sampler"), "канал анимации")
            target = channel["target"]
            _get(nodes, target.get("node"), "узел анимации")
            if target.get("path") not in ("translation", "rotation", "scale", "weights"):
                raise ModelError("Неподдерживаемое свойство анимации")
        clips.append(name)
    bone_names = []
    for skin in skins:
        if not isinstance(skin, dict) or not isinstance(skin.get("joints"), list):
            raise ModelError("Некорректный скелет")
        for joint in skin["joints"]:
            node = _get(nodes, joint, "кость")
            name = node.get("name") or f"bone_{joint}"
            if isinstance(name, str) and name not in bone_names:
                bone_names.append(name)
    warnings = []
    if not meshes:
        warnings.append("В файле нет сетки: возможно, это отдельный файл анимации")
    elif not mesh_instances:
        warnings.append("Сетки не привязаны к узлам и могут не отображаться")
    if triangles > 10_000:
        warnings.append(f"Треугольников {triangles}: рекомендовано не более 10 000")
    if any(i["width"] > 1024 or i["height"] > 1024 for i in image_sizes):
        warnings.append("Есть текстура больше 1024×1024")
    if not bone_names:
        warnings.append("Скелет не найден: для неподвижной модели потребуются движения кодом")
    if not clips:
        warnings.append("Анимаций нет в этом файле")
    if doc.get("extensionsRequired"):
        warnings.append("Модель использует обязательные расширения glTF; совместимость нужно проверить в предпросмотре")
    return {"triangles": triangles, "textures": image_sizes, "bones": bone_names,
            "animations": clips, "meshes": len(meshes), "mesh_instances": mesh_instances, "warnings": warnings}

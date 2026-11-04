"""Маленькие синтетические GLB для тестов. Это не экспорт Meshy."""
from __future__ import annotations

import json
import math
import struct
from pathlib import Path


def glb(doc: dict, blob: bytes = b"") -> bytes:
    raw = json.dumps({"asset": {"version": "2.0"}, **doc}, separators=(",", ":")).encode()
    raw += b" " * (-len(raw) % 4)
    blob += b"\0" * (-len(blob) % 4)
    size = 20 + len(raw) + (8 + len(blob) if blob else 0)
    return (struct.pack("<4sII", b"glTF", 2, size) + struct.pack("<I4s", len(raw), b"JSON") + raw
            + (struct.pack("<I4s", len(blob), b"BIN\0") + blob if blob else b""))


def _pack(parts: list[bytes]) -> tuple[bytes, list[dict]]:
    chunks = []
    views = []
    offset = 0
    for part in parts:
        if offset % 4:
            pad = 4 - offset % 4
            chunks.append(b"\x00" * pad)
            offset += pad
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(part)})
        chunks.append(part)
        offset += len(part)
    return b"".join(chunks), views


def skinned_glb(bone: str = "Hips", extra_root: bool = False, clip: str = "Walk") -> bytes:
    """Один треугольник, одна кость и клип вращения. extra_root меняет путь скелета, но не имя кости."""
    positions = struct.pack("<9f", -0.5, 0, 0, 0.5, 0, 0, 0, 1, 0)
    indices = struct.pack("<3H", 0, 1, 2)
    joints = bytes([0, 0, 0, 0] * 3)
    weights = struct.pack("<12f", *([1, 0, 0, 0] * 3))
    times = struct.pack("<2f", 0.0, 1.0)
    half = math.sin(math.pi / 4)
    rots = struct.pack("<8f", 0, 0, 0, 1, 0, half, 0, math.cos(math.pi / 4))
    ibm = struct.pack("<16f", 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
    blob, views = _pack([positions, indices, joints, weights, times, rots, ibm])
    if extra_root:
        nodes = [
            {"name": "Extra", "children": [1]},
            {"name": "Armature", "children": [2, 3]},
            {"name": bone},
            {"name": "Mesh", "mesh": 0, "skin": 0},
        ]
        joint, skeleton, scene = 2, 1, [0]
    else:
        nodes = [
            {"name": "Armature", "children": [1, 2]},
            {"name": bone},
            {"name": "Mesh", "mesh": 0, "skin": 0},
        ]
        joint, skeleton, scene = 1, 0, [0]
    doc = {
        "scene": 0,
        "scenes": [{"nodes": scene}],
        "nodes": nodes,
        "meshes": [{"name": "Body", "primitives": [{"attributes": {"POSITION": 0, "JOINTS_0": 2, "WEIGHTS_0": 3}, "indices": 1}]}],
        "skins": [{"name": "Armature", "skeleton": skeleton, "joints": [joint], "inverseBindMatrices": 6}],
        "animations": [{"name": clip, "samplers": [{"input": 4, "output": 5, "interpolation": "LINEAR"}],
                        "channels": [{"sampler": 0, "target": {"node": joint, "path": "rotation"}}]}],
        "buffers": [{"byteLength": len(blob)}],
        "bufferViews": views,
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-0.5, 0, 0], "max": [0.5, 1, 0]},
            {"bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"},
            {"bufferView": 2, "componentType": 5121, "count": 3, "type": "VEC4"},
            {"bufferView": 3, "componentType": 5126, "count": 3, "type": "VEC4"},
            {"bufferView": 4, "componentType": 5126, "count": 2, "type": "SCALAR", "min": [0], "max": [1]},
            {"bufferView": 5, "componentType": 5126, "count": 2, "type": "VEC4"},
            {"bufferView": 6, "componentType": 5126, "count": 1, "type": "MAT4"},
        ],
    }
    return glb(doc, blob)


def write_client_fixtures(root: Path) -> None:
    folder = root / "client" / "tests" / "fixtures"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "model3d_skinned.glb").write_bytes(skinned_glb())
    (folder / "model3d_skinned_repath.glb").write_bytes(skinned_glb(extra_root=True))
    (folder / "model3d_skinned_mismatch.glb").write_bytes(skinned_glb(bone="Spin"))

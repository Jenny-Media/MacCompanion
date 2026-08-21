#!/usr/bin/env python3

import hashlib
import json
from pathlib import Path


class DuplicateKeyError(ValueError):
    pass


def closed_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateKeyError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


repository = Path(__file__).resolve().parents[1]
fixture_root = repository / "spec" / "fixtures"
manifest_path = fixture_root / "manifest.json"

manifest = json.loads(
    manifest_path.read_text(encoding="utf-8"),
    object_pairs_hook=closed_pairs,
)

seen = set()
for fixture in manifest["fixtures"]:
    relative = fixture["path"]
    if relative in seen:
        raise ValueError(f"duplicate fixture path: {relative}")
    seen.add(relative)

    path = (fixture_root / relative).resolve()
    if fixture_root.resolve() not in path.parents:
        raise ValueError(f"fixture escapes authoritative root: {relative}")
    if not path.is_file():
        raise FileNotFoundError(path)
    try:
        value = json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=closed_pairs,
        )
    except (UnicodeDecodeError, json.JSONDecodeError, DuplicateKeyError):
        if fixture["expect"] == "valid":
            raise
        continue

    expected_hash = fixture.get("canonicalSHA256")
    if expected_hash is not None:
        canonical = json.dumps(
            value,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        ).encode("utf-8")
        actual_hash = hashlib.sha256(canonical).hexdigest()
        if actual_hash != expected_hash:
            raise ValueError(
                f"canonical hash mismatch for {relative}: {actual_hash} != {expected_hash}"
            )

print(f"validated {len(seen)} indexed JSON fixtures")

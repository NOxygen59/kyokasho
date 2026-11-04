#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""Import directly written Codex translation batches, bound to the frozen source text list.

TSV: source-text index, English, Simplified Chinese. For an existing `Anglais :` source label,
two columns suffice: index, Chinese; English is retained verbatim from the source.
No translation model, network, or dictionary mutation is involved.
"""
import argparse
import json
from pathlib import Path


def import_batch(text_list, cache_path, batch_path, english_only=False):
    source = json.loads(text_list.read_text())
    cache = json.loads(cache_path.read_text()) if cache_path.exists() else {
        "source_sha256": source["source_sha256"], "translations": {}, "provider": "Codex direct translation"}
    if cache["source_sha256"] != source["source_sha256"]:
        raise ValueError("Wrong source revision")
    additions = {}
    for line in batch_path.read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        parts = line.split("\t")
        index = int(parts[0])
        if index < 0 or index >= len(source["texts"]) or index in additions:
            raise ValueError("Invalid or duplicate text index")
        text = source["texts"][index]
        if len(parts) == 2 and english_only:
            value = {"en": parts[1]}
        elif len(parts) == 2 and text.startswith("Anglais : "):
            value = {"en": text[len("Anglais : "):], "zh-Hans": parts[1]}
        elif len(parts) == 3:
            value = {"en": parts[1], "zh-Hans": parts[2]}
        else:
            raise ValueError(f"Invalid columns at index {index}")
        if not all(s.strip() for s in value.values()):
            raise ValueError("Empty translation")
        if text in cache["translations"] and cache["translations"][text] != value:
            raise ValueError(f"Conflicting translation at index {index}")
        additions[index] = value
    for index, value in additions.items():
        cache["translations"][source["texts"][index]] = value
    tmp = cache_path.with_suffix(".tmp")
    tmp.write_text(json.dumps(cache, ensure_ascii=False, indent=1))
    tmp.replace(cache_path)
    print(f"{len(additions)} texts imported; {len(cache['translations'])}/{len(source['texts'])} complete")


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--texts", type=Path, required=True)
    p.add_argument("--cache", type=Path, required=True)
    p.add_argument("--batch", type=Path, required=True)
    p.add_argument("--english-only", action="store_true")
    args = p.parse_args()
    import_batch(args.texts, args.cache, args.batch, args.english_only)

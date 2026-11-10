#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""Build translated Yomitan archives from an exact source archive and a checked translation cache.

No dictionary is versioned. Only Python's standard library is used; translations are written directly by Codex.
Never fall back silently to untranslated definitions. Chinese contains literal equivalents only.

`--extra` adds the terms found in the manual (a .jsonl file outside the repository) to the English archive only:
they get their own source tag, the page and a warning, and no French definition. The Chinese archive is out of
scope for this revision and is left as it is.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import sys
import zipfile

# Étape « manuel » partagée avec la fabrication du lexique français : mêmes lignes, mêmes étiquettes, un seul endroit.
TOOLS = Path(__file__).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))
import build_domain_lexicon as lexicon

AI = "Explication rédigée par une IA, à vérifier."
TITLES = {"en": "Interior design lexicon (Wikipedia, Wiktionary) [en]",
          "zh-Hans": "室内设计词典（维基百科、维基词典）[zh-Hans]"}
WARNINGS = {"en": "AI-written explanation; please verify.", "zh-Hans": "由人工智能撰写的解释，请核实。"}
MACHINE = {"en": "Machine translation; verify technical meanings.", "zh-Hans": "机器翻译，请核实专业术语的含义。"}
# Libellé de l'étiquette « man » (termes du manuel) : la source française du .zip ne la connaît qu'en français.
MANUAL_LABELS = {"en": "Manual: automatic extraction, please verify", "zh-Hans": "手册：自动提取，请核实"}
LINKS = {
    "en": {"Source : Wiktionnaire": "Source: Wiktionary", "Source : Wikipédia en français": "Source: French Wikipedia",
           "Source : Wikipédia en japonais": "Source: Japanese Wikipedia", "Source : Wikidata": "Source: Wikidata",
           "Source : e-Gov 法令検索": "Source: e-Gov 法令検索"},
    "zh-Hans": {"Source : Wiktionnaire": "来源：维基词典", "Source : Wikipédia en français": "来源：法语维基百科",
                "Source : Wikipédia en japonais": "来源：日语维基百科", "Source : Wikidata": "来源：维基数据",
                "Source : e-Gov 法令検索": "来源：e-Gov 法令検索"}}


def read_source(path):
    with zipfile.ZipFile(path) as z:
        index = json.loads(z.read("index.json"))
        tags = json.loads(z.read("tag_bank_1.json"))
        rows = []
        for name in sorted((n for n in z.namelist() if n.startswith("term_bank_")),
                           key=lambda n: int(n.split("_")[-1].split(".")[0])):
            rows.extend(json.loads(z.read(name)))
    return index, tags, rows


def source_hash(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def texts(rows):
    return sorted({s for row in rows for s in row[5] if isinstance(s, str) and s != AI})


def localize(index, tags, rows, cache, lang):
    translations = cache["translations"]
    literals = cache.get("literalTranslations", {})
    missing = ([str(row[6]) for row in rows if not literals.get(str(row[6]))] if lang == "zh-Hans"
               else [s for s in texts(rows) if not translations.get(s, {}).get(lang)])
    if missing:
        raise ValueError(f"{len(missing)} untranslated texts ({lang}); archive not produced")
    result = copy.deepcopy(rows)
    for row in result:
        glossary = [literals[str(row[6])]] if lang == "zh-Hans" else []
        for value in row[5]:
            if isinstance(value, str):
                if value == AI:
                    glossary.append(WARNINGS[lang])
                elif lang != "zh-Hans":
                    glossary.append(translations[value][lang])
            else:
                # Preserve the URL and structure; only localize the visible source label.
                link = value["content"]
                link["content"] = LINKS[lang][link["content"]]
                glossary.append(value)
        row[5] = glossary + [MACHINE[lang]]
    idx = copy.deepcopy(index)
    idx.update(title=TITLES[lang], targetLanguage=lang,
               revision=index["revision"] + "." + lang + ".1")
    idx["description"] = ("Japanese interior design glossary. Machine translations from the original French and Japanese; verify technical meanings."
                          if lang == "en" else "日语室内设计词典。提供词语的简体中文对应词，不含完整释义。请核实专业术语。")
    # Original legal attribution remains verbatim, followed by a localized description of the adaptation.
    idx["attribution"] += "\n" + ("English machine translation by Kyōkasho; source links and CC BY-SA attribution retained."
                                           if lang == "en" else "Kyōkasho 简体中文机器翻译；保留来源链接和 CC BY-SA 署名。")
    tag_labels = {"en": ["French Wiktionary, CC BY-SA 4.0", "French/Japanese Wikipedia, CC BY-SA 4.0", "Wikidata, CC0", "Japanese laws, e-Gov", "Interior design and architecture",
                         MANUAL_LABELS["en"]],
                  "zh-Hans": ["法语维基词典，CC BY-SA 4.0", "法语／日语维基百科，CC BY-SA 4.0", "维基数据，CC0", "日本法律，e-Gov", "室内设计与建筑",
                              MANUAL_LABELS["zh-Hans"]]}
    out_tags = copy.deepcopy(tags)
    for tag, label in zip(out_tags, tag_labels[lang]):
        tag[3] = label
    return idx, out_tags, result


def build(args):
    cache = json.loads(Path(args.cache).read_text())
    if cache["source_sha256"] != source_hash(args.source):
        raise ValueError("Source archive changed; refusing stale translations")
    index, tags, rows = read_source(args.source)
    # Fichier hors dépôt : les termes du manuel ne sont jamais dans le dépôt, seule leur place dans le .zip compte.
    manual = lexicon.read_manual_terms(args.extra) if getattr(args, "extra", None) else []
    base_revision = getattr(args, "revision", None) or index["revision"]
    # Prepare both before writing anything: no partially translated deliverable.
    languages = args.language or list(TITLES)
    localized = {lang: localize(index, tags, rows, cache, lang) for lang in languages}
    added = {}
    for lang, (idx, out_tags, out_rows) in localized.items():
        idx["revision"] = f"{base_revision}.{lang}.1"
        if manual and lang == "en":
            out_tags = lexicon.with_manual_tag(out_tags)
            for tag in out_tags:
                if tag[0] == lexicon.MANUAL_TAG:
                    tag[3] = MANUAL_LABELS[lang]
            out_rows, added[lang] = lexicon.merge_manual_rows(out_rows, manual, "en")
            idx["description"] += " Terms found in the manual are automatic extractions, to verify."
            idx["attribution"] += "\n" + lexicon.MANUAL_ATTRIBUTION + "\n" + lexicon.MANUAL_ATTRIBUTION_EN
        localized[lang] = (idx, out_tags, out_rows)
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    for lang in localized:
        path = output / f"lexique-interieur-{lang}.zip"
        if path.exists():
            raise FileExistsError(f"Refusing to overwrite {path}; choose a new output directory")
    for lang, (idx, out_tags, out_rows) in localized.items():
        path = output / f"lexique-interieur-{lang}.zip"
        with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr("index.json", json.dumps(idx, ensure_ascii=False))
            z.writestr("tag_bank_1.json", json.dumps(out_tags, ensure_ascii=False))
            for start in range(0, len(out_rows), 2000):
                z.writestr(f"term_bank_{start//2000+1}.json", json.dumps(out_rows[start:start+2000], ensure_ascii=False))
        verify(args.source, path, lang, len(added.get(lang, [])))
        print(path, source_hash(path), f"{len(out_rows)} entries ({len(added.get(lang, []))} from the manual)")


def verify(source, target, lang, manual_terms=0):
    """Le .zip produit garde chaque entrée du source, et les entrées ajoutées viennent toutes du manuel."""
    original, _, rows = read_source(source)
    index, _, translated = read_source(target)
    if (len(translated) != len(rows) + manual_terms or index["targetLanguage"] != lang
            or index["title"] != TITLES[lang]):
        raise ValueError("Wrong entry count or language identity")
    for old, new in zip(rows, translated):
        if old[:5] != new[:5] or old[6:] != new[6:]:
            raise ValueError("Japanese terms, readings, tags or sequence changed")
        old_links = [v["content"]["href"] for v in old[5] if isinstance(v, dict)]
        new_links = [v["content"]["href"] for v in new[5] if isinstance(v, dict)]
        if old_links != new_links or (AI in old[5] and WARNINGS[lang] not in new[5]):
            raise ValueError("Source link or AI warning lost")
    for extra in translated[len(rows):]:
        # A manual entry must stay identifiable: its own tag and its visible warning, never a bare translation.
        if extra[2] != lexicon.MANUAL_TAG or not any(isinstance(v, str) and "manual" in v for v in extra[5]):
            raise ValueError("Manual term lost its tag or its warning")
    if original["attribution"] not in index["attribution"]:
        raise ValueError("Source attribution lost")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for command in ["build"]:
        p = sub.add_parser(command)
        p.add_argument("--source", required=True)
        p.add_argument("--cache", required=True)
        p.add_argument("--output", required=True)
        p.add_argument("--language", action="append", choices=list(TITLES))
        p.add_argument("--extra", help="termes relevés dans le manuel (.jsonl, hors dépôt), ajoutés à l'anglais")
        p.add_argument("--revision", help="révision de base (par défaut celle du .zip source)")
    args = parser.parse_args()
    build(args)

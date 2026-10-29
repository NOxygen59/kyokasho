#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59

"""Petit dictionnaire Yomitan du design d'intérieur, tiré de sources ouvertes (#50, lot D4 piste B).

Deux étapes, toujours sur le Mac et hors du dépôt (aucun dictionnaire n'est versionné) :

  fetch  : relève les pages de catégories choisies du Wiktionnaire français (sens en français) et de
           Wikipédia en japonais (première phrase, titres équivalents en français et en anglais) ;
           le brut est gardé dans un dossier de travail, pour reconstruire sans retélécharger.
  build  : fabrique le .zip Yomitan (index.json, tag_bank_1.json, term_bank_N.json) depuis ce brut.

Sources sous licence CC BY-SA 4.0 : l'attribution est écrite dans index.json et chaque entrée renvoie
à sa page. Le fichier produit se publie à part, avec l'accord de NOxygen59.
"""

import argparse
import datetime
import json
from pathlib import Path
import re
import subprocess
import time
from urllib.parse import quote, urlencode
import zipfile


USER_AGENT = "KyokashoLexiconBuilder/1.0 (https://github.com/NOxygen59/kyokasho)"
WIKTIONARY = "https://fr.wiktionary.org"
WIKIPEDIA = "https://ja.wikipedia.org"

WIKTIONARY_CATEGORIES = (
    "Lexique en japonais de l’architecture",
    "Lexique en japonais de la construction",
    "Édifices en japonais",
    "Meubles en japonais",
    "Pièces de la maison en japonais",
    "Matériaux en japonais",
    "Lexique en japonais de la menuiserie",
    "Couleurs en japonais",
    "Lexique en japonais du textile",
)
WIKIPEDIA_CATEGORIES = (
    "建築用語",
    "インテリア",
    "家具",
    "日本の住宅",
    "建築材料",
    "照明器具",
)

TITLE = "Lexique du design d'intérieur (Wikipédia, Wiktionnaire)"
ATTRIBUTION = (
    "Extraits du Wiktionnaire en français (fr.wiktionary.org) et de Wikipédia en japonais (ja.wikipedia.org), "
    "sous licence CC BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/). Auteurs : contributeurs de "
    "chaque page, dont l'adresse est donnée avec l'entrée. Assemblé avec tools/build_domain_lexicon.py (Kyōkasho)."
)
TERMS_PER_BANK = 2000
EXCERPT_LIMIT = 160

KANA = re.compile(r"^[ぁ-ゖァ-ヺー・ゝゞヽヾ]+$")
HAS_JAPANESE = re.compile(r"[ぁ-ゖァ-ヺ㐀-鿿]")
SKIPPED_TITLE = re.compile(r"一覧|曖昧さ回避|^\d")
# Noms propres (bâtiments, lieux, sociétés, personnes, œuvres) : ce ne sont pas des termes du métier.
PROPER_NOUN = re.compile(r"にある|に所在|に位置|に建つ|の企業|株式会社|会社である|メーカー|建築家|協同組合|論文|の人物|の作品|法人|財団|かつて存在")


# --- Analyse (fonctions pures, testées) ---

def is_kana(text):
    return bool(text) and bool(KANA.match(text))


def clean_wikitext(text):
    """Texte lisible d'une définition du Wiktionnaire : liens résolus, modèles et mise en forme retirés."""
    while re.search(r"\{\{[^{}]*\}\}", text):  # modèles imbriqués : de l'intérieur vers l'extérieur
        text = re.sub(r"\{\{[^{}]*\}\}", "", text)
    text = re.sub(r"\[\[(?:[^\]|]*\|)?([^\]]*)\]\]", r"\1", text)
    text = re.sub(r"'{2,}", "", text)
    text = re.sub(r"<[^>]+>", "", text)
    return re.sub(r"\s+", " ", text).strip(" .;:") + ("." if text.strip().endswith(".") else "")


def wiktionary_reading(section, expression):
    """Lecture en kana d'une section japonaise : ja-trans (hira= ou 2e paramètre), sinon la clé de tri."""
    for match in re.finditer(r"\{\{ja-trans\|([^}]*)\}\}", section):
        parameters = match.group(1).split("|")
        for parameter in parameters:
            if parameter.startswith(("hira=", "kata=")) and is_kana(parameter.split("=", 1)[1]):
                return parameter.split("=", 1)[1]
        positional = [p for p in parameters if "=" not in p]
        for candidate in positional[:2]:
            if is_kana(candidate):
                return candidate
    key = re.search(r"clé=([^|}]+)", section)
    if key and is_kana(key.group(1)):
        return key.group(1)
    return expression if is_kana(expression) else ""


def wiktionary_entries(title, wikitext):
    """Entrées japonaises d'une page du Wiktionnaire : [(terme, lecture, partie du discours, [sens])]."""
    start = wikitext.find("== {{langue|ja}} ==")
    if start < 0:
        return []
    following = re.search(r"\n== \{\{langue\|", wikitext[start + 1:])
    section = wikitext[start: start + 1 + following.start()] if following else wikitext[start:]
    entries = []
    for block in re.split(r"\n(?==== \{\{S\|)", section):
        header = re.match(r"=== \{\{S\|([^|}]+)\|ja", block)
        if not header or header.group(1) in ("étymologie", "prononciation", "références", "voir aussi"):
            continue
        senses = [clean_wikitext(line[1:]) for line in block.splitlines() if re.match(r"#(?![*:#])", line)]
        senses = [sense for sense in senses if re.search(r"\w", sense)]
        if senses:
            entries.append((title, wiktionary_reading(block, title), header.group(1), senses))
    return entries


def wikipedia_title(title):
    return re.sub(r"\s*\([^)]*\)$", "", title).strip()


def wikipedia_reading(term, extract):
    """Lecture donnée entre parenthèses après le titre, au début de l'article : 「欄間（らんま）は、…」."""
    if is_kana(term):
        return term
    match = re.search(r"[（(]([^）)]*)[）)]", extract[:200])
    if not match:
        return ""
    candidate = re.split(r"[、,，;；/・ 　]", match.group(1).strip())[0]
    return candidate if is_kana(candidate) else ""


def first_sentence(extract):
    sentence = extract.strip().split("\n")[0]
    end = sentence.find("。")
    if end >= 0:
        sentence = sentence[: end + 1]
    return sentence if len(sentence) <= EXCERPT_LIMIT else sentence[: EXCERPT_LIMIT - 1] + "…"


def page_url(site, title):
    return f"{site}/wiki/{quote(title.replace(' ', '_'))}"


def term_rows(wiktionary_pages, wikipedia_pages):
    """Lignes term_bank (format 3) : [terme, lecture, étiquettes, règles, score, sens, séquence, étiquettes du terme]."""
    rows = []
    for page in sorted(wiktionary_pages, key=lambda p: p["title"]):
        for term, reading, _, senses in wiktionary_entries(page["title"], page.get("wikitext", "")):
            glossary = senses + [f"Source : {page_url(WIKTIONARY, page['title'])}"]
            rows.append([term, reading, "wikt", "", 2, glossary, 0, "interieur"])
    for page in sorted(wikipedia_pages, key=lambda p: p["title"]):
        term = wikipedia_title(page["title"])
        if SKIPPED_TITLE.search(term) or not HAS_JAPANESE.search(term) or len(term) > 20:
            continue
        links = page.get("langlinks", {})
        glossary = [f"{label} : {links[code]}" for code, label in (("fr", "Français"), ("en", "Anglais")) if code in links]
        excerpt = first_sentence(page.get("extract", ""))
        if PROPER_NOUN.search(excerpt):
            continue
        if excerpt:
            glossary.append(excerpt)
        if not glossary:
            continue
        glossary.append(f"Source : {page_url(WIKIPEDIA, page['title'])}")
        rows.append([term, wikipedia_reading(term, page.get("extract", "")), "wp", "", 1, glossary, 0, "interieur"])
    for sequence, row in enumerate(rows, start=1):
        row[6] = sequence
    return rows


def build(raw, output, revision):
    wiktionary = json.loads((raw / "wiktionary.json").read_text(encoding="utf-8"))
    wikipedia = json.loads((raw / "wikipedia.json").read_text(encoding="utf-8"))
    rows = term_rows(wiktionary, wikipedia)
    index = {
        "title": TITLE,
        "revision": revision,
        "format": 3,
        "sequenced": True,
        "author": "Contributeurs du Wiktionnaire et de Wikipédia ; assemblé par NOxygen59",
        "description": "Termes de l'architecture, de l'intérieur, du mobilier et des matériaux. Sens en français "
                       "(Wiktionnaire) ; pour Wikipédia, titres équivalents en français et en anglais, et première phrase.",
        "attribution": ATTRIBUTION,
        "sourceLanguage": "ja",
        "targetLanguage": "fr",
    }
    tags = [
        ["wikt", "source", 0, "Wiktionnaire en français, CC BY-SA 4.0", 0],
        ["wp", "source", 0, "Wikipédia en japonais, CC BY-SA 4.0", 0],
        ["interieur", "domain", 0, "Design d'intérieur et architecture", 0],
    ]
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("index.json", json.dumps(index, ensure_ascii=False, indent=1))
        archive.writestr("tag_bank_1.json", json.dumps(tags, ensure_ascii=False))
        for number, start in enumerate(range(0, max(len(rows), 1), TERMS_PER_BANK), start=1):
            archive.writestr(f"term_bank_{number}.json", json.dumps(rows[start: start + TERMS_PER_BANK], ensure_ascii=False))
    return len(rows)


# --- Relevé (réseau, poli : une requête par seconde, nouvel essai si le site limite) ---

def api(site, **parameters):
    parameters.update(format="json", formatversion="2", maxlag="5")
    url = f"{site}/w/api.php?{urlencode(parameters)}"
    for attempt in range(5):
        time.sleep(1 + attempt * 4)
        result = subprocess.run(["curl", "-sS", "--fail", "-A", USER_AGENT, url], capture_output=True)
        if result.returncode == 0 and result.stdout.startswith(b"{"):
            data = json.loads(result.stdout)
            if data.get("error", {}).get("code") != "maxlag":
                return data
    raise RuntimeError(f"{site} ne répond pas : {parameters}")


def query_all(site, **parameters):
    """Toutes les réponses d'une requête, suite (« continue ») comprise."""
    following = {}
    while True:
        data = api(site, action="query", **parameters, **following)
        yield data.get("query", {})
        if "continue" not in data:
            return
        following = data["continue"]


def category_pages(site, categories, depth):
    seen, pages = set(), set()
    pending = [(category, 0) for category in categories]
    while pending:
        category, level = pending.pop(0)
        if category in seen:
            continue
        seen.add(category)
        for chunk in query_all(site, list="categorymembers", cmtitle=f"Category:{category}", cmlimit="500",
                               cmnamespace="0|14"):
            for member in chunk.get("categorymembers", []):
                if member["ns"] == 14 and level < depth:
                    pending.append((member["title"].split(":", 1)[1], level + 1))
                elif member["ns"] == 0:
                    pages.add(member["title"])
    return sorted(pages)


def batches(items, size):
    for start in range(0, len(items), size):
        yield items[start: start + size]


def fetch_wiktionary(categories, depth):
    pages = []
    for titles in batches(category_pages(WIKTIONARY, categories, depth), 50):
        for chunk in query_all(WIKTIONARY, prop="revisions", rvprop="content", rvslots="main", titles="|".join(titles)):
            for page in chunk.get("pages", []):
                revisions = page.get("revisions") or [{}]
                text = revisions[0].get("slots", {}).get("main", {}).get("content", "")
                if text:
                    pages.append({"title": page["title"], "wikitext": text})
    return pages


def fetch_wikipedia(categories, depth):
    pages = {}
    for titles in batches(category_pages(WIKIPEDIA, categories, depth), 20):
        for chunk in query_all(WIKIPEDIA, prop="extracts|langlinks", exintro="1", explaintext="1", exlimit="20",
                               lllimit="max", titles="|".join(titles)):
            for page in chunk.get("pages", []):
                entry = pages.setdefault(page["title"], {"title": page["title"], "extract": "", "langlinks": {}})
                entry["extract"] = page.get("extract") or entry["extract"]
                for link in page.get("langlinks", []):
                    if link["lang"] in ("fr", "en"):
                        entry["langlinks"][link["lang"]] = link["title"]
    return list(pages.values())


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    fetch = commands.add_parser("fetch", help="relever les pages (réseau)")
    fetch.add_argument("--raw", type=Path, required=True, help="dossier de travail, hors du dépôt")
    fetch.add_argument("--depth", type=int, default=1, help="profondeur des sous-catégories (1 par défaut)")
    make = commands.add_parser("build", help="fabriquer le .zip Yomitan")
    make.add_argument("--raw", type=Path, required=True)
    make.add_argument("--output", type=Path, required=True, help="fichier .zip, hors du dépôt")
    make.add_argument("--revision", default=datetime.date.today().isoformat())
    arguments = parser.parse_args()
    if arguments.command == "fetch":
        arguments.raw.mkdir(parents=True, exist_ok=True)
        for name, pages in (("wiktionary", fetch_wiktionary(WIKTIONARY_CATEGORIES, arguments.depth)),
                            ("wikipedia", fetch_wikipedia(WIKIPEDIA_CATEGORIES, arguments.depth))):
            (arguments.raw / f"{name}.json").write_text(json.dumps(pages, ensure_ascii=False, indent=1), encoding="utf-8")
            print(f"{name} : {len(pages)} pages")
    else:
        print(f"{build(arguments.raw, arguments.output, arguments.revision)} entrées : {arguments.output}")


if __name__ == "__main__":
    main()

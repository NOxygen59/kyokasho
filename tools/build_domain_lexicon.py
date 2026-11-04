#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59

"""Petit dictionnaire Yomitan du design d'intérieur, tiré de sources ouvertes (#50, lot D4 piste B).

Trois étapes, toujours sur le Mac et hors du dépôt (aucun dictionnaire n'est versionné) :

  fetch  : relève les pages de catégories choisies du Wiktionnaire français (sens en français) et de
           Wikipédia en japonais (première phrase, titres équivalents en français et en anglais) ;
           le brut est gardé dans un dossier de travail, pour reconstruire sans retélécharger.
  enrich : ajoute les définitions de Wikipédia en français, les libellés et la nature des pages (Wikidata, CC0)
           et des termes de Wikidata absents des catégories ;
  laws   : relève les définitions légales de e-Gov 法令検索 (loi et décret sur les normes de construction) ;
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
import xml.etree.ElementTree as ElementTree
import zipfile


USER_AGENT = "KyokashoLexiconBuilder/1.0 (https://github.com/NOxygen59/kyokasho)"
WIKTIONARY = "https://fr.wiktionary.org"
WIKIPEDIA = "https://ja.wikipedia.org"
WIKIPEDIA_FR = "https://fr.wikipedia.org"
WIKIDATA = "https://www.wikidata.org"
WIKIDATA_SPARQL = "https://query.wikidata.org/sparql"

# Pas de « Lexique du textile » : ses sous-catégories (habillement, couture) amenaient surtout des vêtements.
WIKTIONARY_CATEGORIES = (
    "Lexique en japonais de l’architecture",
    "Lexique en japonais de la construction",
    "Édifices en japonais",
    "Meubles en japonais",
    "Lexique en japonais de la menuiserie",
    "Lexique en japonais de la maçonnerie",
    "Lexique en japonais du bois",
    "Couleurs en japonais",
    "Textiles en japonais",
)
WIKIPEDIA_CATEGORIES = (
    "建築用語",
    "インテリア",
    "インテリアデザイン",
    "家具",
    "建具",
    "壁",
    "屋根",
    "窓",
    "階段",
    "照明",
    "建築材料",
    "塗料",
    "建築設備",
    "建築構造",
    "防火",
    "製図",
    "日本の住宅",
)
# Mots courants du métier que les catégories ne ramènent pas toujours (天井, 壁, 床…) : pages demandées par leur titre.
SEED_TERMS = tuple("""
内装 内装材 内装制限 天井 壁 床 床材 材料 採光 不燃 準不燃 難燃 防炎 耐火 準耐火 防火 耐震 免震 制震 換気 断熱 遮音 吸音 防音
結露 湿気 通風 間取り 間仕切り 収納 押入れ クローゼット 和室 洋室 居間 リビング ダイニング 寝室 台所 キッチン 浴室 洗面所 便所 玄関
廊下 階段 手摺 窓 サッシ 扉 ドア 引き戸 障子 襖 畳 敷居 鴨居 欄間 床の間 縁側 柱 梁 基礎 土台 屋根 外壁 内壁 壁紙 クロス 巾木 廻り縁
塗装 左官 漆喰 珪藻土 合板 集成材 無垢材 木材 石材 タイル カーペット フローリング クッションフロア ガラス 金属 鋼材 コンクリート モルタル
石膏ボード 照明 照度 輝度 ダウンライト シャンデリア 間接照明 色温度 演色性 色彩 色相 明度 彩度 補色 カーテン ブラインド ロールスクリーン
家具 椅子 机 テーブル ソファ 棚 箪笥 図面 平面図 立面図 断面図 展開図 天井伏図 縮尺 寸法 尺 建築 建物 建築物 住宅 集合住宅 マンション
用途地域 建蔽率 容積率 建築基準法 消防法 建築士 インテリアコーディネーター 人間工学 バリアフリー ユニバーサルデザイン 動線 空調 給排水
配管 配線 コンセント シックハウス症候群 ホルムアルデヒド
工法 仕上 鉄筋 鉄骨 鉄骨造 木造 構造体 接合部 塗装仕上 左官仕上 壁仕上 床仕上 天井仕上 屋根仕上 外部建具 内部建具 室内建具 木製建具 建具枠 建具金物 金物 断熱性 気密性 遮音性
防犯性 防水性 防火性能 遮音性能 断熱性能 吸音性能 耐久性 耐摩耗性 耐水性 耐火性 耐候性 耐熱性 耐薬品性 耐衝撃性 耐朽性 耐蟻性 防滑性 保温性 樹種 ヒノキ ケヤキ チーク カラマツ アカマツ
クロマツ ベイマツ ラワン 木質系 繊維板 軟質繊維板 接着剤 含浸 フラッシュ戸 片引 片開 両開 内開 内倒 出窓 引手 取手 握玉 旗丁番 普通丁番 ピボットヒンジ モノロック レバーハンドル シリンダー
ペアガラス 複層ガラス 網入 フロートガラス 中空層 空気層 水蒸気 日射 日射量 日照時間 直射日光 対流 伝導 放射 温度差 外気温 室温 熱移動 熱損失 熱貫流抵抗 換気量 給気 排気 周波数
音圧 波長 騒音 吸音材 吸音材料 空間 畳床 畳表 天井板 床板 床組 床下地 下地材 構造材 構造用合板 通し柱 東立 ルバー ベネシャンブラインド アルミサッシ ガラスブロック ビニルタイル プラスター ガラスウール
ロックウール ポリスチレンフォーム ウレタン 種石 上塗 下塗 希釈剤 裏打 壁紙貼 織物壁紙 紙壁紙 襖紙 和紙 ボイル プレハブ スパン ボルト 高力ボルト 重量鉄骨 軽量鉄骨 デッキプレート 壁式構造 剛接合 耐震改修
断熱改修 石造 鉄平石 砕石 蛇紋岩 硬石 軟石 吸水率 収縮率 繊維方向 乾燥収縮 カーテンボックス スペースユニット トイレユニット 押入 屋内階段 直階段 鉄骨階段 木造階段 紫外線 赤外線 可視光線 二酸化炭素 一酸化炭素
水蒸気圧 飽和水蒸気圧 放射温度 温熱環境 照度分布 日影曲線 比視感度曲線 人工照明 室内環境 音環境 光環境 熱環境 環境工学 構法 下地 開口部 部材 施工 造作 根太 大引 床束 胴差 管柱
軒桁 母屋 野地板 横架材 軸組 在来軸組構法 枠組壁工法 ツーバイフォー 小屋組 和小屋 洋小屋 仕口 継手 野縁 内法 長押 床柱 床框 床脇 竿縁天井 畳寄 雑巾摺 框戸 舞良戸
丁番 段板 踏面 段鼻 ノンスリップ ガラリ トップライト 心材 辺材 木取 柾目 板目 木口 針葉樹 広葉樹 含水率 繊維飽和点 気乾状態 腐朽菌 躯体 スラブ 型枠 配筋 ブレース
耐火被覆 プレカット 乾式工法 湿式工法 間仕切 防湿層 勾配 見切 面取 目透 目地 化粧 ラスボード シーラー エマルションペイント テラゾー 本磨 水磨 割肌 磁器質タイル 火成岩 水成岩 変成岩 安山岩
グレモンボルト デッドボルト ラッチ フロアヒンジ ドレーキップ 熱伝導率 熱伝達率 熱貫流率 熱抵抗 熱容量 露点温度 絶対湿度 相対湿度 空気線図 表面結露 着衣量 代謝量 温熱環境六要素 作用温度 必要換気量 換気回数 自然換気 機械換気 風力換気
シックハウス 外皮平均日射熱取得率 日射侵入率 直達日射 残響時間 透過損失 吸音率 コインシデンス効果 デシベル ラウドネス カンデラ 光束発散度 視感度 明所視 暗所視 錐状体 杆状体 光幕反射
""".split())

# Élément d'architecture, matériau de construction, meuble : leurs sous-classes apportent des termes supplémentaires.
WIKIDATA_CLASSES = ("Q391414", "Q206615", "Q14745")
# Nature (P31) d'une page qui n'est pas un terme du métier : personne, organisation, lieu, œuvre.
NOT_A_TERM = frozenset({"Q5", "Q43229", "Q4830453", "Q783794", "Q891723", "Q486972", "Q515", "Q3957", "Q532", "Q1115575",
                        "Q3918", "Q38723", "Q571", "Q7725634", "Q11424", "Q5398426", "Q7889", "Q7366", "Q134556", "Q482994",
                        "Q33506", "Q207694", "Q1190554", "Q2221906"})
# Sous-classes de Wikidata sans intérêt ici : isotopes, précisions entre parenthèses, termes numérotés.
WIKIDATA_NOISE = re.compile(r"isotope|[()（）]|\d")
TAXON = "Q16521"
USEFUL_TAXON = re.compile(r"木材|建材|建築|家具|内装")

# (identifiant e-Gov, nom court, article, numéros retenus) : définitions utiles au métier, sans l'urbanisme ni le droit des plans.
LAW_DEFINITIONS = (
    ("325AC0000000201", "建築基準法", "2", ("1", "2", "3", "4", "5", "6", "7", "7_2", "8", "9", "9_2", "9_3", "12", "13", "14", "15")),
    ("325CO0000000338", "建築基準法施行令", "1", ("1", "2", "3", "4", "5", "6")),
)
EGOV_API = "https://laws.e-gov.go.jp/api/2/law_data"
EGOV_LAW = "https://laws.e-gov.go.jp/law"
LAW_TEXT_LIMIT = 300

TITLE = "Lexique du design d'intérieur (Wikipédia, Wiktionnaire)"
ATTRIBUTION = (
    "Extraits du Wiktionnaire en français (fr.wiktionary.org) et de Wikipédia en français et en japonais "
    "(fr.wikipedia.org, ja.wikipedia.org), "
    "sous licence CC BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/). Auteurs : contributeurs de "
    "chaque page, dont l'adresse est donnée avec l'entrée. Libellés de Wikidata (CC0). Textes de loi japonais tirés de e-Gov 法令検索. Assemblé avec tools/build_domain_lexicon.py (Kyōkasho)."
)
TERMS_PER_BANK = 2000
EXCERPT_LIMIT = 160
FRENCH_LIMIT = 320

KANA = re.compile(r"^[ぁ-ゖァ-ヺー・ゝゞヽヾ]+$")
HAS_JAPANESE = re.compile(r"[ぁ-ゖァ-ヺ㐀-鿿]")
SKIPPED_TITLE = re.compile(r"一覧|曖昧さ回避|^\d")
# Noms propres (bâtiments, lieux, sociétés, personnes, œuvres) : ce ne sont pas des termes du métier.
PROPER_NOUN = re.compile(r"にある|に所在|に位置|に建つ|の企業|株式会社|会社である|メーカー|建築家|協同組合|論文|の人物|の作品|法人|財団|かつて存在"
                         r"|生まれ|出身|\\d+月\\d+日\\s*[-－–—]|番組|小説|漫画|映画|アニメ|テレビ|歌手|タレント|政治家|の町|市の|区の|県の"
                         r"|神社|寺院|大学|学校|教育機関|研究所|博物館|美術館|鉄道")
PROPER_NOUN_TITLE = re.compile(r"大学|駅|神社|寺$|城$|ホテル|タワー|★|大会|キャンパス|研究所|アカデミー|図書室|プレイ")


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


def french_definition(extract):
    """Première phrase utile d'un article français ; rien pour une page d'homonymie."""
    text = re.sub(r"\s+", " ", extract or "").strip()
    if not text or re.search(r"peut (?:aussi )?(?:désigner|faire référence)|page d.homonymie", text[:160]):
        return ""
    # Fin de phrase : un point suivi d'une majuscule, pas une abréviation d'une lettre (« J. Dupont »).
    match = re.search(r"(?<=[^\s.]{2})\.(?=\s+[A-ZÀ-Ý«])", text)
    sentence = text[: match.end()] if match else text
    if len(sentence) <= FRENCH_LIMIT:
        return sentence
    return sentence[: FRENCH_LIMIT - 1].rsplit(" ", 1)[0] + "…"


def is_trade_term(item, extract):
    """Faux pour une personne, un lieu, une organisation, une œuvre, ou une espèce sans rapport avec le bâtiment."""
    natures = set((item or {}).get("natures", []))
    if natures & NOT_A_TERM:
        return False
    return TAXON not in natures or bool(USEFUL_TAXON.search(extract or ""))


def law_definitions(xml_text, law_id, law_name, article, numbers):
    """Définitions d'un article à deux colonnes (terme, définition) du XML officiel des lois japonaises."""
    root = ElementTree.fromstring(xml_text)
    definitions = []
    for element in root.iter("Article"):
        if element.get("Num") != article:
            continue
        for item in element.iter("Item"):
            columns = item.find("ItemSentence")
            columns = columns.findall("Column") if columns is not None else []
            if item.get("Num") not in numbers or len(columns) != 2:
                continue
            term, text = ("".join(column.itertext()).strip() for column in columns)
            # Le reste de l'article complète souvent la définition (sous-points イ, ロ) : on garde le début de l'énoncé.
            title = item.findtext("ItemTitle", "").strip()
            definitions.append({"term": re.sub(r"\s+", "", term), "text": re.sub(r"\s+", "", text),
                                "source": f"{law_name} 第{article}条第{title}号", "url": f"{EGOV_LAW}/{law_id}"})
        break
    return definitions


def page_url(site, title):
    return f"{site}/wiki/{quote(title.replace(' ', '_'))}"


def source_link(name, url):
    """Lien court vers la page d'origine (attribution CC BY-SA) : une adresse brute déborde de la bulle."""
    return {"type": "structured-content", "content": {"tag": "a", "href": url, "content": f"Source : {name}"}}


def term_rows(wiktionary_pages, wikipedia_pages, enrichment=None):
    """Lignes term_bank (format 3) : [terme, lecture, étiquettes, règles, score, sens, séquence, étiquettes du terme]."""
    enrichment = enrichment or {}
    items = enrichment.get("items", {})
    french = enrichment.get("french", {})
    rows = []
    for page in sorted(wiktionary_pages, key=lambda p: p["title"]):
        for term, reading, _, senses in wiktionary_entries(page["title"], page.get("wikitext", "")):
            glossary = senses + [source_link("Wiktionnaire", page_url(WIKTIONARY, page["title"]))]
            rows.append([term, reading, "wikt", "", 2, glossary, 0, "interieur"])
    for page in sorted(wikipedia_pages, key=lambda p: p["title"]):
        if page.get("disambiguation"):
            continue
        term = wikipedia_title(page["title"])
        if SKIPPED_TITLE.search(term) or not HAS_JAPANESE.search(term) or len(term) > 20:
            continue
        # Demandé par son titre : le mot compte même si son article cite un lieu ou une école.
        chosen = term in SEED_TERMS or any(alias in SEED_TERMS for alias in page.get("aliases", []))
        if not chosen and PROPER_NOUN_TITLE.search(term):
            continue
        item = items.get(page["title"], {})
        excerpt = first_sentence(page.get("extract", ""))
        if not chosen and (PROPER_NOUN.search(excerpt) or not is_trade_term(item, page.get("extract", ""))):
            continue
        links = page.get("langlinks", {})
        french_title = links.get("fr") or item.get("label", "")
        definition = french_definition(french.get(links.get("fr", ""), ""))
        # Le français d'abord : c'est lui qui fait comprendre le terme ; le japonais reste pour l'étude.
        glossary = [f"Français : {wikipedia_title(french_title)}"] if french_title else []
        if definition:
            glossary.append(definition)
        elif item.get("description"):
            glossary.append(item["description"])
        if "en" in links:
            glossary.append(f"Anglais : {links['en']}")
        if excerpt:
            glossary.append(excerpt)
        if not glossary:
            continue
        if definition:
            glossary.append(source_link("Wikipédia en français", page_url(WIKIPEDIA_FR, links["fr"])))
        glossary.append(source_link("Wikipédia en japonais", page_url(WIKIPEDIA, page["title"])))
        reading = wikipedia_reading(term, page.get("extract", ""))
        score = 3 if definition else 1
        rows.append([term, reading, "wp", "", score, glossary, 0, "interieur"])
        # Autre graphie qui mène à cette page : même définition, cherchée sous les deux formes.
        for alias in page.get("aliases", []):
            if alias != term and HAS_JAPANESE.search(alias):
                rows.append([alias, "", "wp", "", score, glossary, 0, "interieur"])
    known = {row[0] for row in rows}
    for extra in sorted(enrichment.get("extra", []), key=lambda e: e["term"]):
        term = extra["term"]
        if term in known or SKIPPED_TITLE.search(term) or not HAS_JAPANESE.search(term) or len(term) > 20:
            continue
        if WIKIDATA_NOISE.search(term) or WIKIDATA_NOISE.search(extra.get("description", "")):
            continue
        known.add(term)
        glossary = [f"Français : {extra['french']}"]
        if extra.get("description"):
            glossary.append(extra["description"])
        glossary.append(source_link("Wikidata", f"{WIKIDATA}/wiki/{extra['item']}"))
        rows.append([term, term if is_kana(term) else "", "wd", "", 1, glossary, 0, "interieur"])
    # Rédigé à la main pour des termes essentiels sans article français : signalé comme tel à l'écran.
    written = {row[0]: row for row in rows if row[2] != "wikt"}
    for term, entry in sorted(enrichment.get("written", {}).items()):
        glossary = [f"Français : {entry['french']}", entry["definition"], "Explication rédigée par une IA, à vérifier."]
        row = written.get(term)
        if row:
            row[5] = glossary + [g for g in row[5] if not (isinstance(g, str) and g.startswith("Français :"))]
            row[4] = 3
        else:
            rows.append([term, entry.get("reading", ""), "wp", "", 3, glossary, 0, "interieur"])
    # Texte officiel : ajouté à l'entrée existante du terme, avec son article.
    latest = {row[0]: row for row in rows if row[2] != "wikt"}
    for law in enrichment.get("laws", []):
        text = law["text"] if len(law["text"]) <= LAW_TEXT_LIMIT else law["text"][: LAW_TEXT_LIMIT - 1] + "…"
        lines = [f"Définition légale ({law['source']}) : {text}", source_link("e-Gov 法令検索", law["url"])]
        row = latest.get(law["term"])
        if row:
            row[5] = row[5] + lines
        else:
            rows.append([law["term"], "", "law", "", 2, lines, 0, "interieur"])
    for sequence, row in enumerate(rows, start=1):
        row[6] = sequence
    return rows


def build(raw, output, revision, written=None):
    wiktionary = json.loads((raw / "wiktionary.json").read_text(encoding="utf-8"))
    wikipedia = json.loads((raw / "wikipedia.json").read_text(encoding="utf-8"))
    enrichment_file = raw / "enrichment.json"
    enrichment = json.loads(enrichment_file.read_text(encoding="utf-8")) if enrichment_file.exists() else {}
    if written is None:
        written = json.loads(Path(__file__).with_name("lexique_definitions_fr.json").read_text(encoding="utf-8"))
    enrichment["written"] = written
    laws_file = raw / "laws.json"
    if laws_file.exists():
        enrichment["laws"] = json.loads(laws_file.read_text(encoding="utf-8"))
    rows = term_rows(wiktionary, wikipedia, enrichment)
    index = {
        "title": TITLE,
        "revision": revision,
        "format": 3,
        "sequenced": True,
        "author": "Contributeurs du Wiktionnaire et de Wikipédia ; assemblé par NOxygen59",
        "description": "Termes de l'architecture, de l'intérieur, du mobilier et des matériaux. Définitions en français "
                       "(Wikipédia, Wiktionnaire), libellés de Wikidata et première phrase de l'article japonais.",
        "attribution": ATTRIBUTION,
        "sourceLanguage": "ja",
        "targetLanguage": "fr",
    }
    tags = [
        ["wikt", "source", 0, "Wiktionnaire en français, CC BY-SA 4.0", 0],
        ["wp", "source", 0, "Wikipédia en français et en japonais, CC BY-SA 4.0", 0],
        ["wd", "source", 0, "Wikidata, CC0", 0],
        ["law", "source", 0, "Textes de loi japonais, e-Gov 法令検索", 0],
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


def fetch_wiktionary(categories, depth, seeds=SEED_TERMS):
    pages = []
    titles_to_read = sorted(set(category_pages(WIKTIONARY, categories, depth)) | set(seeds))
    for titles in batches(titles_to_read, 50):
        for chunk in query_all(WIKTIONARY, prop="revisions", rvprop="content", rvslots="main", titles="|".join(titles)):
            for page in chunk.get("pages", []):
                revisions = page.get("revisions") or [{}]
                text = revisions[0].get("slots", {}).get("main", {}).get("content", "")
                if text:
                    pages.append({"title": page["title"], "wikitext": text})
    return pages


def fetch_wikipedia(categories, depth, seeds=SEED_TERMS):
    pages = {}
    titles_to_read = sorted(set(category_pages(WIKIPEDIA, categories, depth)) | set(seeds))
    for titles in batches(titles_to_read, 20):
        for chunk in query_all(WIKIPEDIA, prop="extracts|langlinks|pageprops", exintro="1", explaintext="1", exlimit="20",
                               lllimit="max", ppprop="disambiguation", redirects="1", titles="|".join(titles)):
            for page in chunk.get("pages", []):
                if page.get("missing"):
                    continue
                entry = pages.setdefault(page["title"], {"title": page["title"], "extract": "", "langlinks": {}, "aliases": []})
                entry["extract"] = page.get("extract") or entry["extract"]
                entry["disambiguation"] = "disambiguation" in page.get("pageprops", {})
                for link in page.get("langlinks", []):
                    if link["lang"] in ("fr", "en"):
                        entry["langlinks"][link["lang"]] = link["title"]
            for redirect in chunk.get("redirects", []):
                entry = pages.setdefault(redirect["to"], {"title": redirect["to"], "extract": "", "langlinks": {}, "aliases": []})
                if redirect["from"] not in entry["aliases"]:
                    entry["aliases"].append(redirect["from"])
    return list(pages.values())


def fetch_enrichment(wikipedia_pages):
    """Définitions françaises, nature des pages, et termes de Wikidata absents des catégories."""
    titles = [page["title"] for page in wikipedia_pages]
    item_of = {}
    for batch in batches(titles, 50):
        for chunk in query_all(WIKIPEDIA, prop="pageprops", ppprop="wikibase_item", titles="|".join(batch)):
            for page in chunk.get("pages", []):
                identifier = page.get("pageprops", {}).get("wikibase_item")
                if identifier:
                    item_of[page["title"]] = identifier
    entities = {}
    for batch in batches(sorted(set(item_of.values())), 50):
        data = api(WIKIDATA, action="wbgetentities", ids="|".join(batch), props="labels|descriptions|claims", languages="fr")
        for identifier, entity in data.get("entities", {}).items():
            natures = [claim["mainsnak"]["datavalue"]["value"]["id"] for claim in entity.get("claims", {}).get("P31", [])
                       if claim.get("mainsnak", {}).get("datavalue")]
            entities[identifier] = {"label": entity.get("labels", {}).get("fr", {}).get("value", ""),
                                    "description": entity.get("descriptions", {}).get("fr", {}).get("value", ""),
                                    "natures": natures}
    items = {title: entities[identifier] for title, identifier in item_of.items() if identifier in entities}
    french = {}
    french_titles = sorted({page["langlinks"]["fr"] for page in wikipedia_pages if page.get("langlinks", {}).get("fr")})
    for batch in batches(french_titles, 20):
        for chunk in query_all(WIKIPEDIA_FR, prop="extracts", exintro="1", explaintext="1", exlimit="20", redirects="1",
                               titles="|".join(batch)):
            redirected = {r["to"]: r["from"] for r in chunk.get("redirects", [])}
            for page in chunk.get("pages", []):
                if page.get("extract"):
                    french[page["title"]] = page["extract"]
                    if page["title"] in redirected:
                        french[redirected[page["title"]]] = page["extract"]
    extra, seen = [], set()
    for root in WIKIDATA_CLASSES:
        query = (f"SELECT ?i ?ja ?fr ?d WHERE {{ ?i wdt:P279* wd:{root} . ?i rdfs:label ?ja . FILTER(LANG(?ja)='ja') "
                 "?i rdfs:label ?fr . FILTER(LANG(?fr)='fr') "
                 "OPTIONAL { ?i schema:description ?d . FILTER(LANG(?d)='fr') } }")
        time.sleep(2)
        result = subprocess.run(["curl", "-sS", "--fail", "-m", "90", "-A", USER_AGENT, "-H", "Accept: application/sparql-results+json",
                                 "-G", WIKIDATA_SPARQL, "--data-urlencode", f"query={query}"], capture_output=True)
        if result.returncode != 0:
            raise RuntimeError(f"Wikidata ne répond pas : {root}")
        for row in json.loads(result.stdout)["results"]["bindings"]:
            term = row["ja"]["value"]
            if term not in seen:
                seen.add(term)
                extra.append({"term": term, "french": row["fr"]["value"], "description": row.get("d", {}).get("value", ""),
                              "item": row["i"]["value"].rsplit("/", 1)[-1]})
    return {"items": items, "french": french, "extra": extra}


def fetch_laws():
    definitions = []
    for law_id, name, article, numbers in LAW_DEFINITIONS:
        time.sleep(1)
        result = subprocess.run(["curl", "-sS", "--fail", "-m", "90", "-A", USER_AGENT,
                                 f"{EGOV_API}/{law_id}?response_format=xml&law_full_text_format=xml"], capture_output=True)
        if result.returncode != 0:
            raise RuntimeError(f"e-Gov ne répond pas : {law_id}")
        definitions += law_definitions(result.stdout, law_id, name, article, numbers)
    return definitions


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    fetch = commands.add_parser("fetch", help="relever les pages (réseau)")
    fetch.add_argument("--raw", type=Path, required=True, help="dossier de travail, hors du dépôt")
    fetch.add_argument("--depth", type=int, default=1, help="profondeur des sous-catégories (1 par défaut)")
    enrich = commands.add_parser("enrich", help="ajouter le français et Wikidata au relevé (réseau)")
    enrich.add_argument("--raw", type=Path, required=True)
    laws = commands.add_parser("laws", help="relever les définitions légales (réseau)")
    laws.add_argument("--raw", type=Path, required=True)
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
    elif arguments.command == "laws":
        definitions = fetch_laws()
        (arguments.raw / "laws.json").write_text(json.dumps(definitions, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"{len(definitions)} définitions légales")
    elif arguments.command == "enrich":
        wikipedia = json.loads((arguments.raw / "wikipedia.json").read_text(encoding="utf-8"))
        enrichment = fetch_enrichment(wikipedia)
        (arguments.raw / "enrichment.json").write_text(json.dumps(enrichment, ensure_ascii=False, indent=1), encoding="utf-8")
        print({key: len(value) for key, value in enrichment.items()})
    else:
        print(f"{build(arguments.raw, arguments.output, arguments.revision)} entrées : {arguments.output}")


if __name__ == "__main__":
    main()

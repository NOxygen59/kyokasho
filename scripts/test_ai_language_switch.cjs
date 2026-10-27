// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59
// Test synthétique du script exact de bascule 日本語 / Français (AILayoutView.languageSwitchScript, Issue #17).
// Lancer : node scripts/test_ai_language_switch.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('App/Study/AILayoutView.swift', 'utf8');
const script = source.match(/static let languageSwitchScript = """([\s\S]*?)"""/)[1];

// Mise en page factice : seul le bloc de la langue affichée occupe de la hauteur, blocs empilés depuis 0.
function page(jaHeights, frHeights, shown) {
  const langs = {className: shown};
  const container = (id, heights) => {
    const blocks = heights.map((h, i) => ({dataset: {b: String(i)}, h}));
    blocks.forEach((el, i) => {
      el.getBoundingClientRect = () => {
        if (langs.className !== id) return {top: 0, height: 0};
        const top = blocks.slice(0, i).reduce((sum, b) => sum + b.h, 0);
        return {top, height: el.h};
      };
    });
    return {querySelectorAll: () => blocks, blocks};
  };
  const ja = container('ja', jaHeights), fr = container('fr', frHeights);
  const document = {
    getElementById: id => ({langs, ja, fr})[id],
    body: {get scrollHeight() { return (langs.className === 'ja' ? ja : fr).blocks.reduce((s, b) => s + b.h, 0); }},
  };
  const context = vm.createContext({window: {scrollY: 0}, document});
  vm.runInContext(script, context);
  return {langs, run: (fr, y) => vm.runInContext(`window.__kyokashoSwitchLanguage(${fr},${y})`, context)};
}

// Même nombre de blocs : on retrouve le bloc lu, à la même fraction de sa hauteur.
let p = page([100, 200, 100], [60, 120, 60], 'ja');
let r = p.run(true, 200);                 // milieu du bloc 1 japonais (100..300)
assert.equal(p.langs.className, 'fr');
assert.equal(r.y, 60 + 60);               // bloc 1 français : 60..180, milieu = 120
assert.equal(r.h, 240);
r = p.run(false, 120);                    // retour : milieu du bloc 1 français
assert.equal(r.y, 200);
assert.equal(r.h, 400);

// En haut de la page (y ≤ 0) : bascule seule, position inchangée.
r = p.run(true, 0);
assert.equal(p.langs.className, 'fr');
assert.equal(r.y, 0);

// Langue déjà affichée : rien ne bouge.
r = p.run(true, 50);
assert.equal(r.y, 50);
assert.equal(p.langs.className, 'fr');

// Nombre de blocs différent : position proportionnelle à la hauteur.
p = page([100, 100, 100, 100], [100, 100], 'ja');
r = p.run(true, 200);
assert.equal(r.y, 200 / 400 * 200);

// Pas de page à deux langues : rien.
const empty = vm.createContext({window: {}, document: {getElementById: () => null}});
vm.runInContext(script, empty);
assert.equal(vm.runInContext('window.__kyokashoSwitchLanguage(true, 10)', empty), null);
console.log('PASS: bloc retrouvé à la même fraction, retour, haut de page, langue inchangée, proportionnel, page simple');

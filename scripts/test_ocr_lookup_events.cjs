// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59
// Test synthétique du script exact des événements du dictionnaire (RubyWebView.lookupEventsScript, Issue #13).
// Lancer : node scripts/test_ocr_lookup_events.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('App/Study/FuriganaText.swift', 'utf8');
const script = source.match(/static let lookupEventsScript = """([\s\S]*?)"""/)[1];

const listeners = new Map(), messages = [];
function word(q, x) {
  const el = {dataset: {q}, classList: {add() {}, remove() {}},
              getBoundingClientRect: () => ({left: x, top: 10, width: 20, height: 18})};
  el.closest = sel => (sel === 'span[data-q]' ? el : null);
  return el;
}
const blank = {closest: () => null};
const context = vm.createContext({
  window: {webkit: {messageHandlers: {kyokasho: {postMessage: m => messages.push(m)}}}},
  document: {
    addEventListener(kind, callback) { listeners.set(kind, callback); },
    querySelectorAll: () => [],
  },
});
vm.runInContext(script, context);
const move = (target, shiftKey, buttons = 0) => listeners.get('mousemove')({target, shiftKey, buttons});
const opens = () => messages.filter(m => m.type === 'lookup').length;
const A = word('学校', 40), B = word('図', 80);

// Survol avec Maj : ouverture une seule fois par mot, rectangle transmis.
move(A, true); move(A, true);
assert.equal(opens(), 1);
assert.deepEqual({...messages[0].rect}, {x: 40, y: 10, w: 20, h: 18});
assert.equal(messages[0].hover, true);

// Cycle de la revue : Maj relâchée sans bouger → Swift ferme la bulle et réinitialise → Maj + même mot rouvre.
vm.runInContext('window.__kyokashoResetHover()', context);
move(A, true);
assert.equal(opens(), 2, 'le même mot rouvre la bulle après réinitialisation');

// Quitter le mot ou relâcher Maj pendant un mouvement : hoverEnd, une seule fois.
move(blank, true); move(blank, true);
assert.equal(messages.filter(m => m.type === 'hoverEnd').length, 1);
move(B, false);
assert.equal(opens(), 2, 'sans Maj, le survol n’ouvre rien');

// Bouton appuyé (glisser pour défiler) : ignoré.
move(B, true, 1);
assert.equal(opens(), 2);

// Clic explicite sur un mot, puis hors d'un mot.
listeners.get('click')({target: B});
assert.equal(messages.at(-1).type, 'lookup');
assert.equal(messages.at(-1).hover, false);
listeners.get('click')({target: blank});
assert.equal(messages.at(-1).type, 'tapOutside');
console.log('PASS: survol Maj, réinitialisation et réouverture du même mot, hoverEnd, glisser ignoré, clic et tapOutside');

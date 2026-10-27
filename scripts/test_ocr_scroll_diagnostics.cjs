// Synthetic lifecycle test of the exact script injected by RubyWebView.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('App/Study/FuriganaText.swift', 'utf8');
const script = source.match(/private static let scrollDiagnosticScript = """([\s\S]*?)"""/)[1];
const listeners = new Map(), messages = [];
let now = 1000;
const context = vm.createContext({
  window: {webkit: {messageHandlers: {kyokasho: {postMessage: m => messages.push(m)}}}},
  Date: {now: () => now},
  document: {
    addEventListener(kind, callback, options) {
      assert.deepEqual({...options}, {capture: true, passive: true});
      assert.ok(!listeners.has(kind), 'no duplicate listeners');
      listeners.set(kind, callback);
    },
    removeEventListener(kind, callback, capture) {
      assert.equal(listeners.get(kind), callback);
      assert.equal(capture, true);
      listeners.delete(kind);
    }
  }
});
assert.equal(listeners.size, 0);
vm.runInContext(script, context);
assert.equal(listeners.size, 4);
vm.runInContext(script, context);
assert.equal(listeners.size, 4);
listeners.get('scroll')(); listeners.get('scroll')();
assert.equal(messages.length, 1);
now += 500; listeners.get('scroll')();
assert.equal(messages.length, 2);
vm.runInContext('window.__kyokashoRemoveScrollDiagnostic?.();', context);
assert.equal(listeners.size, 0);
vm.runInContext('window.__kyokashoRemoveScrollDiagnostic?.();', context);
vm.runInContext(script, context);
assert.equal(listeners.size, 4);
vm.runInContext('window.__kyokashoRemoveScrollDiagnostic?.();', context);
assert.equal(listeners.size, 0);
console.log('PASS: install, idempotence, throttle, removal, reactivation; synthetic DOM only');

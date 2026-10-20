// Exporte les règles de déconjugaison japonaises de Yomitan en JSON (données, pas de code).
import {japaneseTransforms} from '../yomitan/ext/js/language/ja/japanese-transforms.js';
const out = {language: japaneseTransforms.language, conditions: {}, transforms: []};
for (const [key, c] of Object.entries(japaneseTransforms.conditions)) {
  out.conditions[key] = {name: c.name, isDictionaryForm: !!c.isDictionaryForm, subConditions: c.subConditions ?? null};
}
for (const [id, t] of Object.entries(japaneseTransforms.transforms)) {
  const rules = t.rules.map((r) => {
    const src = r.isInflected.source;
    let from, to;
    if (r.type === 'suffix') { from = src.replace(/\$$/, ''); to = r.deinflected; }
    else if (r.type === 'prefix') { from = src.replace(/^\^/, ''); to = r.deinflect(from); }
    else if (r.type === 'wholeWord') { from = src.replace(/^\^/, '').replace(/\$$/, ''); to = r.deinflect(from); }
    else throw new Error('type inconnu ' + r.type);
    if (/[\\\[\]\(\)\|\*\+\?\.]/.test(from)) throw new Error('motif non littéral: ' + from);
    return {type: r.type, from, to, conditionsIn: r.conditionsIn, conditionsOut: r.conditionsOut};
  });
  out.transforms.push({id, name: t.name, description: t.description ?? null, rules});
}
process.stdout.write(JSON.stringify(out));

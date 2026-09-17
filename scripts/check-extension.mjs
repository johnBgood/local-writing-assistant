import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
vm.runInThisContext(fs.readFileSync(new URL('../extension/core.js',import.meta.url),'utf8'));
const {validEdit,applyEdits}=globalThis.LocalWriterCore;
const text='👋 A speling mistake.';
const edit={start:5,length:7,original:'speling',replacement:'spelling'};
assert(validEdit(text,edit));assert.equal(applyEdits(text,[edit]),'👋 A spelling mistake.');
assert(!validEdit('changed',edit));assert.throws(()=>applyEdits(text,[edit,edit]));
assert.throws(()=>applyEdits(text,[{...edit,start:-1}]));
console.log('PASS: extension Unicode offsets, stale edits, overlapping edits');

const {selectionRange}=globalThis.LocalWriterCore;
assert.deepEqual(selectionRange('👋 She don’t know.','She don’t know.'),{start:3,length:15,original:'She don’t know.'});
assert.equal(selectionRange('Same. Same.','Same.'),null);
assert.equal(selectionRange('Hello.','Missing.'),null);
assert.equal(selectionRange('Hello.',''),null);
const phrase='She don’t know.';
const phraseEdit={...selectionRange(phrase,phrase),replacement:'She does not know.'};
assert.equal(applyEdits(phrase,[phraseEdit]),'She does not know.');
assert(!validEdit('She knows.',phraseEdit));
console.log('PASS: whole-selection replacement, Unicode positions, ambiguous and stale selections');

const {preserveSelectionWhitespace}=LocalWriterCore;
assert.equal(preserveSelectionWhitespace('Sentence.\n','Improved sentence.'),'Improved sentence.\n');
assert.equal(preserveSelectionWhitespace('  Sentence.\n\n','Better.'),'  Better.\n\n');
assert.equal(preserveSelectionWhitespace('Sentence.','Better.'),'Better.');
console.log('PASS: selected paragraph boundaries are preserved during rewrite');

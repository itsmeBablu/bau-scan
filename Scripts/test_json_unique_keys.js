const { test } = require('node:test');
const assert = require('node:assert/strict');
const { parseUniqueKeys } = require('./json_unique_keys');
test('rejects repeated localization keys including escaped equivalents', () => {
    assert.throws(() => parseUniqueKeys('{"strings":{"Photo":1,"Photo":2}}'), /Duplicate/);
    assert.throws(() => parseUniqueKeys('{"a":1,"\\u0061":2}'), /Duplicate/);
});
test('permits independent nested keys and handles punctuation in strings', () => {
    const value = { a: [{ title: 'a:b,{}"' }, { title: 'B' }], nested: { a: true } };
    assert.deepEqual(parseUniqueKeys(JSON.stringify(value)), value);
});
test('still rejects malformed JSON', () => {
    assert.throws(() => parseUniqueKeys('{"broken":}'));
});

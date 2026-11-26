// Source-route regression only; this does not execute SwiftUI navigation.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
test('project details never routes to a scan button with an empty callback', () => {
    const source = fs.readFileSync(path.join(__dirname,'../RoomScanner/UI/Projects/ProjectDetailsEditor.swift'),'utf8');
    assert.doesNotMatch(source,/RenovationProjectPage\([^\n]*onScan:\s*\{\s*\}/);
});

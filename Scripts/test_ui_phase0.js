// Source-route regression only; this does not execute SwiftUI navigation.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
test('project details never routes to a scan button with an empty callback', () => {
    const source = fs.readFileSync(path.join(__dirname,'../RoomScanner/UI/Projects/ProjectDetailsEditor.swift'),'utf8');
    assert.doesNotMatch(source,/RenovationProjectPage\([^\n]*onScan:\s*\{\s*\}/);
});

// Source-level side-effect guard only; SwiftUI interaction still needs Apple tests.
test('export format selection configures a request without creating files', () => {
    const source = fs.readFileSync(path.join(__dirname,'../RoomScanner/UI/ExportSheet.swift'),'utf8');
    const start = source.indexOf('private func select(_ format: ExportFormat)');
    const end = source.indexOf('private func generate()',start);
    assert.ok(start > 0 && end > start);
    assert.doesNotMatch(source.slice(start,end),/runExport\(|Task[.(]|\.export\(|exportPhotos\(/);
    assert.match(source,/Button\("Generate"[^\n]*generate\(\)/);
});

test('export generation checks request identity and cancels its worker', () => {
    const source = fs.readFileSync(path.join(__dirname,'../RoomScanner/UI/ExportSheet.swift'),'utf8');
    assert.match(source,/requestID == request/);
    assert.match(source,/onCancel:\s*\{ worker\.cancel\(\) \}/);
    assert.match(source,/onDisappear[^\n]*generationTask\?\.cancel\(\)/);
});

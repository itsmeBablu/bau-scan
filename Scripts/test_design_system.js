const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname,'..');
const tokens = fs.readFileSync(path.join(root,'RoomScanner/DesignSystem/DS.swift'),'utf8');
const names = [...tokens.matchAll(/case \w+ = "([^"]+)"/g)].map(match => match[1]);
function load(name) {
    return JSON.parse(fs.readFileSync(path.join(root,'RoomScanner/DesignSystem/Colors.xcassets',name+'.colorset/Contents.json'),'utf8'));
}
function variant(entry) {
    const values = entry.appearances || [];
    return [values.some(x => x.appearance === 'luminosity' && x.value === 'dark'),values.some(x => x.appearance === 'contrast' && x.value === 'high')].join('/');
}
function rgb(name,dark,high) {
    const entry = load(name).colors.find(item => variant(item) === [dark,high].join('/'));
    const c = entry.color.components;
    assert.equal(Number(c.alpha),1);
    return ['red','green','blue'].map(key => Number(c[key]));
}
function luminance(color) {
    return color.map(x => x <= 0.04045 ? x/12.92 : ((x+0.055)/1.055)**2.4)
        .reduce((sum,x,i) => sum+x*[0.2126,0.7152,0.0722][i],0);
}
test('every semantic token has four explicit appearance variants', () => {
    assert.equal(names.length,21); assert.equal(new Set(names).size,names.length);
    for (const name of names) {
        const colors = load(name).colors;
        assert.equal(colors.length,4,name);
        assert.deepEqual(new Set(colors.map(variant)),new Set(['false/false','true/false','false/true','true/true']),name);
    }
});
test('declared text and UI pairs meet their source-RGB contrast thresholds', () => {
    for (const dark of [false,true]) for (const high of [false,true]) {
        const pairs = [['OnBrand','Brand',4.5],['OnAccent','AccentColor',4.5],['OnRecording','Recording',4.5],['TextPrimary','Selection',4.5]];
        for (const background of ['Surface','SurfaceGrouped','Card']) {
            for (const foreground of ['AccentColor','TextPrimary','TextSecondary','StatusSuccess','StatusWarning','StatusError','StatusInfo','Recording']) pairs.push([foreground,background,4.5]);
            pairs.push(['Separator',background,3]);
        }
        for (const [foreground,background,minimum] of pairs) {
            const a=luminance(rgb(foreground,dark,high)), b=luminance(rgb(background,dark,high));
            const ratio=(Math.max(a,b)+0.05)/(Math.min(a,b)+0.05);
            assert.ok(ratio>=minimum,`${foreground}/${background} dark=${dark} high=${high}: ${ratio.toFixed(2)} < ${minimum}`);
        }
    }
});
test('one app theme owns tints and replaces the old palette locations', () => {
    function visit(dir) {
        for (const entry of fs.readdirSync(dir,{withFileTypes:true})) {
            const file = path.join(dir,entry.name);
            if (entry.isDirectory()) { if (entry.name !== 'DesignSystem') visit(file); }
            else if (file.endsWith('.swift')) assert.doesNotMatch(fs.readFileSync(file,'utf8'),/\.tint\s*\(/,file);
        }
    }
    visit(path.join(root,'RoomScanner'));
    assert.equal(fs.existsSync(path.join(root,'RoomScanner/UI/AppTheme.swift')),false);
    assert.equal(fs.existsSync(path.join(root,'RoomScanner/Resources/Assets.xcassets/AccentColor.colorset')),false);
});

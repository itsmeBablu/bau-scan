// Dependency-free style ratchet. Rendering exceptions are deliberately file-specific.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname,'..'), baselinePath = 'Scripts/style_baseline.txt';
const rendering = new Map([
    ['RoomScanner/Viewer/AnnotationIcon.swift','RealityKit marker textures, not screen typography'],
    ['RoomScanner/Viewer/PlanSceneBuilder.swift','Fixed plan/3D materials; must not follow UI appearance'],
    ['RoomScanner/SceneEditing/StudioSceneBuilder.swift','SceneKit/RealityKit material conversion'],
    ['RoomScanner/SceneEditing/StudioEngineering.swift','Engineering presentation colors, separate from UI chrome'],
    ['RoomScanner/SceneEditing/StudioTechnicalData.swift','Technical model material descriptions'],
    ['RoomScanner/TechnicalRoom/TechnicalMeshAppearance.swift','Captured mesh texture/color generation'],
    ['RoomScanner/Scan/CapturePins.swift','UIKit projected AR marker overlay; migrate platform palette separately'],
    ['RoomScanner/Scan/HoldMicrophoneControl.swift','UIKit touch/recording overlay; no SwiftUI view styling'],
    ['RoomScanner/HouseRadiators/Capture/HouseRadiatorScanCoordinator.swift','Native AR measurement overlay'],
    ['RoomScanner/TechnicalRoom/Capture/TechnicalRoomScanCoordinator.swift','RealityKit annotation materials']
]);
const rules = {
    rgb: /\bColor\s*\(\s*(?:red\s*:|\.sRGB)/g,
    hex: /\bColor\s*\(\s*(?:hex\s*:|"#)/g,
    named: /\.(?:foregroundStyle|foregroundColor|background|tint)\s*\(\s*\.(?:red|green|blue|orange|yellow|purple|pink|mint|teal|cyan|indigo|brown|black|white|gray)\b/g,
    font: /\.font\s*\(\s*\.system\s*\(\s*size\s*:/g,
    radius: /(?:\.cornerRadius\s*\(\s*|RoundedRectangle\s*\(\s*cornerRadius\s*:\s*)[0-9]/g,
    material: /\.(?:background|fill)\s*\([^\n]*\.(?:ultraThinMaterial|thinMaterial|regularMaterial|thickMaterial|ultraThickMaterial)\b/g
};
function counts() {
    const result = new Map();
    function visit(folder) {
        for (const item of fs.readdirSync(folder,{withFileTypes:true})) {
            const full = path.join(folder,item.name),relative = path.relative(root,full).replaceAll('\\','/');
            if (item.isDirectory()) { if (relative !== 'RoomScanner/DesignSystem') visit(full); continue; }
            if (!full.endsWith('.swift') || relative.startsWith('RoomScanner/Export/') || rendering.has(relative)) continue;
            const text = fs.readFileSync(full,'utf8');
            for (const [rule,pattern] of Object.entries(rules)) {
                const number = [...text.matchAll(pattern)].length;
                if (number) result.set(relative+'|'+rule,number);
            }
        }
    }
    visit(path.join(root,'RoomScanner')); return result;
}
function parse(text) {
    return new Map(text.split(/\r?\n/).filter(line => line && !line.startsWith('#')).map(line => {
        const index = line.lastIndexOf('|'); return [line.slice(0,index),Number(line.slice(index+1))];
    }));
}
const actual = counts();
if (process.argv.includes('--write-baseline')) {
    const previous = fs.existsSync(path.join(root,baselinePath)) ? parse(fs.readFileSync(path.join(root,baselinePath),'utf8')) : null;
    if (previous) for (const [key,number] of actual) {
        if (number > (previous.get(key)||0)) throw new Error('Cannot grow baseline: '+key);
    }
    const comments = ['# Style ratchet: counts by file/rule, allowed only to shrink.',
        '# DesignSystem owns style definitions. Export/ is fixed drawing/format content.',
        ...[...rendering].map(([file,reason]) => '# '+file+': '+reason)];
    fs.writeFileSync(path.join(root,baselinePath),comments.join('\n')+'\n'+[...actual].sort().map(([key,n]) => key+'|'+n).join('\n')+'\n');
}
const baseline = parse(fs.readFileSync(path.join(root,baselinePath),'utf8'));
let failed = false;
for (const [key,number] of actual) if (number > (baseline.get(key)||0)) { console.error('New style literal:',key,number); failed = true; }
try {
    const previous = parse(cp.execFileSync('git',['show','HEAD^:'+baselinePath],{cwd:root,encoding:'utf8',stdio:['ignore','pipe','ignore']}));
    for (const [key,number] of baseline) if (number > (previous.get(key)||0)) { console.error('Baseline grew:',key); failed = true; }
} catch (error) { if (!('status' in error)) throw error; /* First introduction has no prior baseline. */ }
console.log(JSON.stringify({remaining:[...actual.values()].reduce((a,b)=>a+b,0),files:new Set([...actual.keys()].map(key=>key.split('|')[0])).size,baseline:[...baseline.values()].reduce((a,b)=>a+b,0)}));
if (failed) process.exitCode = 1;

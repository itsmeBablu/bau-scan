// No packages required: node Scripts/audit_localization.js [--strict]
// Static literal audit supplements Xcode extraction; runtime-generated labels need review.
const fs = require('fs'), path = require('path');
const { parseUniqueKeys } = require('./json_unique_keys');
const root = path.resolve(__dirname, '..');
const catalog = parseUniqueKeys(fs.readFileSync(path.join(root,'RoomScanner/Resources/Localizable.xcstrings'),'utf8'));
const missing = Object.entries(catalog.strings).filter(([,value]) => !value.localizations?.de?.stringUnit?.value);
const gaps = new Map();
for (const file of fs.readdirSync(path.join(root,'RoomScanner'),{recursive:true}).filter(x=>x.endsWith('.swift'))) {
    const text = fs.readFileSync(path.join(root,'RoomScanner',file),'utf8');
    for (const match of text.matchAll(/\b(?:Text|Button|Label|Toggle|Section|Picker|TextField|NavigationLink|Menu|LabeledContent|DisclosureGroup|ProgressView|ContentUnavailableView|confirmationDialog|alert|navigationTitle|accessibilityLabel|accessibilityHint|AppLanguage\.(?:text|format))\(\s*"([^"\n]*(?:\\.[^"\n]*)*)"/g)) {
        const key = match[1];
        if (!key || key.includes('\\(')) continue;
        if (!catalog.strings[key]?.localizations?.de?.stringUnit?.value) {
            const places = gaps.get(key) || []; places.push(file); gaps.set(key,places);
        }
    }
}
console.log(JSON.stringify({catalogKeys:Object.keys(catalog.strings).length,missingGerman:missing.map(([k])=>k),unextractedLiterals:[...gaps].map(([key,files])=>({key,files:[...new Set(files)]}))},null,2));
if (missing.length || (process.argv.includes('--strict') && gaps.size)) process.exitCode = 1;

// JSON.parse validates syntax but silently overwrites duplicate object keys.
function parseUniqueKeys(text) {
    const parsed = JSON.parse(text);
    const tokens = text.match(/"(?:\\.|[^"\\])*"|[{}\[\]:,]|[^\s{}\[\]:,"]+/g) || [];
    const stack = [];
    for (let i = 0; i < tokens.length; i++) {
        const token = tokens[i];
        if (token === '{') stack.push(new Set());
        else if (token === '[') stack.push(null);
        else if (token === '}' || token === ']') stack.pop();
        else if (token.startsWith('"') && tokens[i + 1] === ':') {
            const key = JSON.parse(token), keys = stack[stack.length - 1];
            if (keys.has(key)) throw new Error('Duplicate JSON key: ' + key);
            keys.add(key);
        }
    }
    return parsed;
}
module.exports = { parseUniqueKeys };

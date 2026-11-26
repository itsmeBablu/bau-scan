"""Source inventory, never a substitute for Swift concurrency/runtime analysis.

Masks comments and quoted literals while preserving positions. String interpolation
is masked with its surrounding literal; Swift regex literal parsing is unsupported.
Each site requires human ownership/cancellation/error-policy review.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess


def mask_literals(source):
    chars = list(source)
    index = 0
    def mask(start, end):
        for offset in range(start, end):
            if chars[offset] not in "\r\n":
                chars[offset] = " "
    while index < len(source):
        start = index
        if source.startswith("//", index):
            end = source.find("\n", index)
            index = len(source) if end < 0 else end
        elif source.startswith("/*", index):
            index += 2
            depth = 1
            while index < len(source) and depth:
                if source.startswith("/*", index):
                    depth += 1
                    index += 2
                elif source.startswith("*/", index):
                    depth -= 1
                    index += 2
                else:
                    index += 1
        elif source[index] == '"' or (source[index] == '#' and re.match(r'#+"', source[index:])):
            hashes = 0
            while index < len(source) and source[index] == '#':
                hashes += 1
                index += 1
            quote = '"""' if source.startswith('"""', index) else '"'
            index += len(quote)
            closing = quote + '#' * hashes
            while index < len(source):
                escape = '\\' + '#' * hashes
                if source.startswith(escape, index):
                    index += len(escape) + 1
                elif source.startswith(closing, index):
                    index += len(closing)
                    break
                else:
                    index += 1
        else:
            index += 1
            continue
        mask(start, min(index, len(source)))
    return ''.join(chars)


PATTERNS = {
    "detachedTask": r"\bTask\s*\.\s*detached\b",
    "optionalTry": r"\btry\s*\?",
    "mainActor": r"@MainActor\b",
}


def inventory(source, path):
    masked = mask_literals(source)
    lines = source.splitlines()
    sites = []
    for kind, pattern in PATTERNS.items():
        for match in re.finditer(pattern, masked):
            line = masked.count('\n', 0, match.start()) + 1
            beginning = masked.rfind('\n', 0, match.start()) + 1
            sites.append({"kind": kind, "file": path, "line": line,
                          "column": match.start() - beginning + 1,
                          "source": lines[line - 1].strip(),
                          "reviewStatus": "review-required",
                          "owner": None, "cancellationPolicy": None,
                          "errorPolicy": None, "decision": None})
    return sorted(sites, key=lambda site: (site['line'], site['column'], site['kind']))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    sites = []
    for path in sorted((root / 'RoomScanner').rglob('*.swift')):
        sites.extend(inventory(path.read_text(encoding='utf-8-sig'), path.relative_to(root).as_posix()))
    result = {"commit": subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
              "dirty": bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True).strip()),
              "method": "Position-preserving source inventory; interpolation/regex caveats in script docstring",
              "counts": {kind: sum(site['kind'] == kind for site in sites) for kind in PATTERNS},
              "sites": sites}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print(json.dumps(result['counts']))


if __name__ == '__main__':
    main()

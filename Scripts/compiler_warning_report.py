"""Record compiler diagnostics; enforce only explicitly supplied measured budgets."""
import argparse
import json
from pathlib import Path
import re


def report(log, swift_budget=None, build_budget=None):
    diagnostics = sorted(set(line for line in log.splitlines() if re.search(r'(?:^|:\s)warning:', line)))
    swift = [line for line in diagnostics if re.search(r'\.swift:\d+:\d+: warning:', line)]
    failures = []
    for label, count, budget in [('swift', len(swift), swift_budget), ('build', len(diagnostics), build_budget)]:
        if budget is not None and count > budget:
            failures.append(label)
    return {'uniqueSwiftWarnings': len(swift), 'uniqueBuildWarnings': len(diagnostics),
            'swiftBudget': swift_budget, 'buildBudget': build_budget,
            'status': 'exceeded' if failures else 'checked' if swift_budget is not None or build_budget is not None else 'baseline-only',
            'exceededBudgets': failures, 'diagnostics': diagnostics}


def budget(value):
    if not value.strip():
        return None
    if not value.strip().isdecimal():
        raise argparse.ArgumentTypeError('Budget must be a nonnegative measured integer or blank')
    return int(value.strip())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--swift-budget', type=budget, default=None)
    parser.add_argument('--build-budget', type=budget, default=None)
    args = parser.parse_args()
    result = report(args.log.read_text(encoding='utf-8', errors='replace'), args.swift_budget, args.build_budget)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({key: value for key, value in result.items() if key != 'diagnostics'}))
    return 1 if result['exceededBudgets'] else 0


if __name__ == '__main__':
    raise SystemExit(main())

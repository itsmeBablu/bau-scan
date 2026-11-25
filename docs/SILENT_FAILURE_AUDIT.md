# Silent failure audit — Phase 1

Application Swift sources, not tests; full-line comments are searched for TODO/FIXME only. These are source-pattern matches, not AST-derived proofs. Force-unwrap matches are candidates and may include operators/string content. No earlier count is reused.

| Kind | Count |
|---|---:|
| try? | 81 |
| try! | 0 |
| force unwrap candidate | 73 |
| fatalError | 0 |
| preconditionFailure | 0 |
| TODO | 0 |
| FIXME | 0 |

SILENT_FAILURE_INVENTORY.csv records every match with file/line, source, effect, severity, decision and verification. Cleanup and predicate-based try? are kept deliberately. Prioritized export overwrite/encoding, Mac deletion/subject errors and corrupt neutral scan fallback were fixed this phase. Remaining P1/P2 candidates are visible follow-up items; this inventory is not a claim that every error path is safe or dynamically verified.

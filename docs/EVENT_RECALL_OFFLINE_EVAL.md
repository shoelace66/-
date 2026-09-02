# Event recall offline release gate

`test/fixtures/event_recall_eval_v1.json` is a checked-in, deterministic
roleplay annotation set with 72 isolated samples. It covers keyword and
relation L0 recall, theme and ambiguous judge paths, recent-message
continuity, hot-node-to-cold-graph continuity, negative boundary cases, and
the 0/1/2 POST gates.

Run the evaluator from the repository root:

```powershell
D:\flutter_windows_3.41.2-stable\flutter\bin\flutter.bat test tool\eval_event_recall.dart --no-pub
```

The Flutter test runner is intentional: the production model types depend on
Flutter. The evaluator does not construct an HTTP client or call a provider.
Its fake model reads the coordinator's frozen `DATA=` JSON and returns only
catalog aliases and candidate aliases, so the run is offline and reproducible.
The call still goes through the real `EventRecallCoordinator` and
`MemoryRecallService`.

The fixture stores the release thresholds and a frozen old implementation
baseline. The evaluator fails non-zero unless all are satisfied:

| Gate | Result from the checked-in fixture |
| --- | ---: |
| Explicit structured Recall@5 | 100.0% (40 samples) |
| Overall Recall@5 | 100.0% (72 samples) |
| Old baseline | 93.8%; +6.3 percentage points |
| Average extra POST | 0.444 (limit 0.5) |
| Second-call rate | 11.1% (limit 15%) |
| 0 / 1 / 2 POST gates | 48 / 16 / 8 samples; exact counts |

To evaluate another fixture without changing the script, set
`EVENT_RECALL_FIXTURE` before invoking the same command.

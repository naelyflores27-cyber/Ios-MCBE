# Entity Validation

**Live validation status: Blocked.** No controlled iPhone session, packet capture, test-server log, or source event stream was provided. No live entity identity or coordinate has been claimed.

| Test case | Expected observation | Actual observation | Result | Evidence / limitation |
|---|---|---|---|---|
| Two same-type fixture entities | Distinct runtime IDs; both retained | IDs 100 and 101 coexist as `minecraft:cow` | Pass (fixture) | `tests/unit/test_entity_tracker.c`; not game observations |
| Position update and rotation | Valid latest values replace prior values | Position and rotation update retained | Pass (fixture) | Same deterministic test |
| Missing initial position | Entity must not appear in positioned snapshot | Incomplete entity excluded | Pass (fixture) | `has_position` remains false; no origin default |
| Invalid coordinate | Reject event; preserve last valid state | NaN position rejected | Pass (fixture) | Deterministic test |
| Duplicate/out-of-order update | Must not roll state backward | Duplicate/older event ignored | Pass (fixture) | Per-entity sequence and timestamp checks |
| Removal | Entity removed only on explicit removal | Runtime ID 42 removed | Pass (fixture) | Removal counter increments |
| Stale observation | Excluded from current snapshot | Entity older than 100 ms excluded | Pass (fixture) | Stale count reported |
| Session change and ID reuse | Old state cleared; reused ID starts new generation | State cleared; ID 7 reused in generation 2 | Pass (fixture) | Old-session event rejected |
| Known cow/zombie/skeleton in live world | Spawn/move/remove correlate with ground truth | Not observed | Blocked | No controlled world, device observations, or ground-truth log |

Fixture timestamps are deterministic test values, not measured latency. There is no source update-frequency or position-tolerance result. A fixture pass validates the tracker contract only.
# Architecture

`BNEDataSource` is the source lifecycle contract. A future transport/protocol adapter or verified in-process provider would normalize observations into `BNEObservation`; the current tests supply fixture observations explicitly. Production-source enum values are reserved labels, not implementations.

```text
source adapter (none in this lab)
  -> normalized BNEObservation
  -> BNEEntityTracker + synchronized snapshot provider
  -> copied, age-filtered BNESnapshot
  -> verified camera source (unavailable by default)
  -> BNEProjection
  -> touch-through in-process BNEESPOverlay
```

The tracker keys instances by runtime ID within the current session. Session reset clears the entity map and increments a generation. Updates must match the active session, carry an increasing per-entity sequence and nondecreasing timestamp, and use finite coordinates when a position is present. Position source and timestamp are retained separately from general entity updates. Missing positions remain explicitly absent; snapshots count incomplete entities separately from stale positioned entities and omit both. The tracker retains at most 256 instances.

Snapshot publication is a copy into caller-owned fixed-capacity storage. `BNEEntitySnapshotProvider` serializes tracker access with a mutex; the base tracker remains single-owner. Camera snapshots are copied under an unfair lock. The UIKit view accepts immutable copies and does not intercept touches. Source, camera, and snapshot timestamps must use the same monotonic time domain.

No packet decoder or verified camera producer is present because no capture, negotiated protocol, or live matrix evidence exists. The in-process overlay source is implemented, but it draws no boxes unless positioned observations and a current camera snapshot are published. It rejects fixture/server-ground-truth positions, stale data, out-of-range entities, and viewport mismatches. Bounds are a provisional `0.6 x 1.8 x 0.6` approximation; no precise hitbox claim is made. No private hook is present.
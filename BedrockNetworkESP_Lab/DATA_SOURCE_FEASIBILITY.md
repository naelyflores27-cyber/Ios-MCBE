# Data Source Feasibility

## Decision

**No-go for claiming a live network entity feed at this stage.** There is no authorized-session capture, negotiated protocol version, decoded entity packet, or ground-truth comparison in the workspace. Encryption is **Unknown**, not proven: no relevant live payload was observed. The selected implementation is the source-independent tracker with explicit fixture observations; production-source selection is blocked pending evidence.

| Source | Live positions now? | Version fit | Runtime / complexity | Server dependency | Update reliability | Real-time / iOS suitability |
|---|---|---|---|---|---|---|
| A. Passive capture | **Unknown; not demonstrated.** No capture is supplied. Transport metadata alone would not prove entity positions. | **Unknown:** negotiated protocol version absent. | Low capture overhead; decoding can be high complexity. | No, but requires legitimate access to controlled traffic. | Unknown until packet layouts and encryption are observed. | **Unknown:** no device capture test. |
| B. Protocol decoder | **Unknown; no decoder tested.** | **Unknown:** no target protocol selection or library compatibility proof. | High until RakNet, Bedrock framing, encryption, and packets are accounted for. | Usually no, if valid client-side data is available. | Packet library must be kept version-aligned. | Unknown; iOS integration not attempted. |
| C. In-process decoded boundary | Existing native providers accept snapshots/matrices, but no verified producer boundary is available. | Static findings concern supplied app 1.26.33 only. | High risk and version-sensitive if based on private internals. | No. | Poor without a supported stable API. | Existing loader runs in-process, but usable entity/camera API is not verified. |
| D. Controlled server/API ground truth | **Not tested.** Server-side events could provide known positions for validation. | Server/API version unknown. | Moderate; requires controlled server or enabled script environment. | **Yes** for server-sourced observations. | Depends on supported API/server. | Does not by itself supply client-only observations or camera projection. |
| Fixture source | **Yes, synthetic only.** Tracker lifecycle and projection pipeline pass deterministic tests. | Independent of game protocol. | Low and measured by offline tests. | No. | Deterministic; does not establish live reliability. | Portable host C tests pass; not an iOS runtime integration. |

## Evidence and next decision

**Verified:** existing `CLEntityProvider` has no producer in the inspected source and starts unavailable. `CLCameraProvider` has no default camera matrix and starts unavailable. The supplied diagnostic reports no captured entities and no available candidate loader bridge methods. Static analysis describes Minecraft-owned Script API names but did not establish a callable loader API, private entity accessor, or camera matrix accessor.

**Unknown:** whether an authorized capture in a controlled session exposes decodable entity lifecycle and movement data; whether payload encryption applies in a particular test setup; and whether a specific protocol library supports the negotiated build/protocol.

The most useful next experiment is a controlled, non-sensitive capture plus matching server-side ground-truth log, with game version, protocol version, and entity spawn/move/despawn sequence recorded. Do not collect or export authentication tokens/session keys. If payload content is unavailable or encrypted, stop packet decoding and evaluate a supported Bedrock Script API test pack/server feed as ground truth; that would not prove client-only ESP viability. No undocumented hook, guessed packet layout, or offset is implemented here.
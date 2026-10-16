# Protocol Findings

**Verified:** the supplied app binary is an arm64 Minecraft iOS 1.26.33 build `1.26.33.01`. **Unknown:** negotiated Bedrock protocol version, actual transport for a target session, packet framing visible to a capture point, session encryption state, and entity packet payload fields.

No packet capture or packet library compatibility test exists in the workspace. Therefore there is no measured RakNet header, Bedrock packet ID, entity runtime ID, entity type, spawn coordinate, movement update, rotation, or removal packet. No packet IDs or field layouts are guessed in this project. The existing type registry lists definitions only.

The existing static-analysis report finds compiled Script API and ECS/camera-related names, but explicitly does not establish callable APIs, layouts, pointers, or a live camera matrix. Existing loader JavaScript runs in a separate `JSContext` and the supplied diagnostic found no exposed entity/camera bridge methods. These facts do not determine whether a controlled packet capture can be decoded.

Next evidence needed: an authorized, non-sensitive capture of a controlled session paired with exact app/protocol versions and independent entity ground truth. Do not include authentication/session secrets. If payloads cannot be legitimately decoded, record that outcome and stop treating packet size/transport metadata as entity state.
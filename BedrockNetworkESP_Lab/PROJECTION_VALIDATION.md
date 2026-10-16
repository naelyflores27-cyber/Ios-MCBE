# Projection Validation

The lab's C projection is adapted from `ClientLoader/providers/CLProjection.c` into this isolated directory; no original file is included at build time or edited. It uses column-major matrix multiplication, positive clip `w`, NDC x/y in `[-1,1]`, caller-supplied depth bounds, and viewport origin/size.

| Check | Result | Evidence |
|---|---|---|
| Centered AABB with identity matrix | Pass; expected fixture rectangle | `tests/unit/test_projection.c` |
| Viewport origin/size change | Pass; coordinates scale/translate as expected | Same test |
| Out-of-frustum and behind-camera rejection | Pass | Same test |
| Non-finite matrix rejection | Pass | Same test |
| Actual game camera, orientation, safe area, and overlay alignment | **Unknown / not tested** | No verified camera source or device integration |
| Entity/camera timestamp synchronization | **Unknown / not tested** | No live source timestamps |

The native overlay source refuses to draw unless a camera snapshot is present, fresh, and viewport-aligned with the overlay. The identity matrix is synthetic and is not evidence of a Minecraft camera. No production camera producer exists, so the in-game view currently reports camera unavailable and draws no boxes. Existing `CLCameraProvider` likewise reports unavailable until a caller publishes a matrix.
# Bedrock Network ESP Lab

An isolated in-process diagnostic overlay experiment. Its hosted build produces a separately named lab dylib and a diagnostic build of the existing ClientLoader UI/bridge without overwriting the existing binary. It includes rotating native logs, startup/game-data/network/symbol/ESP reports, a source-independent tracker, and a fail-closed camera interface. No live entity source, protocol decoder, or verified camera producer is connected.

The supplied app payload is identified by its bundle metadata as Minecraft Bedrock 1.26.33 (`1.26.33.01`), arm64, minimum iOS 15.0. This is not evidence of the version installed on a test iPhone. No network capture or controlled test-server observation was present.

Start with [ARCHITECTURE_DECISION.md](ARCHITECTURE_DECISION.md), [DATA_SOURCE_FEASIBILITY.md](DATA_SOURCE_FEASIBILITY.md), [docs/3105_sample_findings.md](docs/3105_sample_findings.md), [ENVIRONMENT_REPORT.md](ENVIRONMENT_REPORT.md), and [PROJECT_ISOLATION.md](PROJECT_ISOLATION.md). Diagnostic report paths and limits are in [DIAGNOSTICS.md](DIAGNOSTICS.md).

Run offline checks with `make test`. The hosted workflow builds both diagnostic libraries and publishes them with `BuildManifest.json` and checksums. ClientLoader is built to `ClientLoader-diagnostic.dylib` using `CL_OUTPUT_PATH`, preserving the existing `ClientLoader.dylib`; the IPA packager stages both in a new unsigned IPA. Signing and device validation remain required. `sh tools/verify_originals.sh` verifies preserved original inputs and separately recorded diagnostic-source hashes.
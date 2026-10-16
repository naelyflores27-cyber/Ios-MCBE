# Bedrock Network ESP Lab

An isolated experiment for a separate in-process iOS dylib. It contains a source-independent tracker, synchronized snapshot boundary, fail-closed camera interface, non-interactive overlay, and fixture-only projection tests. There is no packet decoder, live entity source, verified camera source, iOS build, or device-verified rendering.

The supplied app payload is identified by its bundle metadata as Minecraft Bedrock 1.26.33 (`1.26.33.01`), arm64, minimum iOS 15.0. This is not evidence of the version installed on a test iPhone. No network capture or controlled test-server observation was present.

Start with [ARCHITECTURE_DECISION.md](ARCHITECTURE_DECISION.md), [DATA_SOURCE_FEASIBILITY.md](DATA_SOURCE_FEASIBILITY.md), [ENVIRONMENT_REPORT.md](ENVIRONMENT_REPORT.md), and [PROJECT_ISOLATION.md](PROJECT_ISOLATION.md). The code boundary and test commands are in [docs/architecture.md](docs/architecture.md) and [TESTING.md](TESTING.md).

Run offline checks with `make test`. On a macOS/Xcode host, `sh build_ios.sh` produces the separately named `build/BedrockNetworkESP_Lab.dylib`. `tools/package_experimental_ipa.py` stages it beside the original ClientLoader dylib in a new unsigned IPA; the original app bundle and loader are inputs only. All experimental sources and outputs stay inside this directory. `sh tools/verify_originals.sh` verifies recorded hashes of relevant original inputs.
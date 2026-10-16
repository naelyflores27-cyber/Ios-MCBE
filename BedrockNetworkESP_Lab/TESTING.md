# Testing

## Dependencies and commands

Requires Clang or GCC with C11 support, `make`, and `libm`; no packages need installing.

```sh
make test
```

Expected final lines:

```text
entity tracker tests passed
projection fixture tests passed (synthetic matrix only)
fixture pipeline passed; no live source or camera was exercised
snapshot provider tests passed
Ran 2 tests in ...
```

Executables are created under `build/` within this lab.

## Coverage

Tracker tests cover multiple same-type entities, position/rotation updates, explicit missing-position state and incomplete counts, invalid and unterminated fields, duplicate/out-of-order observations, removal, position-specific stale filtering, session reset, runtime ID reuse, and copied snapshot isolation. The snapshot-provider test checks synchronized publish/copy/reset behavior. Projection tests cover the synthetic identity matrix, viewport translation/resize, out-of-frustum/behind-camera rejection, and invalid matrices. The integration test routes fixture observations through tracker, snapshot, and projection, and verifies that incomplete state is not projected. Package tests stage two load commands, confirm the input app executable remains unchanged, and verify manifest hashes.

## Not tested

No binary packet parser exists, so malformed protocol input and fuzz testing are not applicable yet. No live network, server, iPhone, current paired iOS dylib build/sign, actual two-dylib load, device camera, overlay interaction, rendering performance, or memory-use measurement was performed. The previous downloaded lab dylib predates these diagnostics. UIKit source is not executable-tested on Linux. Fixture coordinates are not ground truth.
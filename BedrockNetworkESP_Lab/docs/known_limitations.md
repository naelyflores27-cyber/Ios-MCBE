# Known Limitations

- Fixture-only source; no live entity feed or protocol decoder.
- Encryption is untested and remains unknown; no claim that captured traffic is encrypted or decrypted.
- No actual iPhone version, iOS version, test-world topology, or network capture was supplied.
- No verified camera producer, camera timestamp, safe-area integration, or game-aligned projection.
- UIKit overlay and filters/range/labels exist in source but have not been built or exercised on iOS; no performance measurement exists.
- The snapshot-provider wrapper serializes tracker access; direct tracker callers must still serialize access themselves.
- Native diagnostics use `NSLog`; there is no report-file exporter or persistent lab log.
- No iOS cross-build was possible on the Linux host.
- The supplied 26.33 ZIP archive is empty; the extracted app payload is present.
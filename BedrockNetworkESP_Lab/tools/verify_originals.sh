#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
sha256sum --check tools/original_files.sha256
sha256sum --check tools/diagnostic_sources.sha256
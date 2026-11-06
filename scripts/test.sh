#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
export CLANG_MODULE_CACHE_PATH="$TASK_ROOT/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$TASK_ROOT/.build/swift-module-cache"
export SWIFTPM_CUSTOM_LIBS_DIR="$(python3 "$TASK_ROOT/scripts/prepare-toolchain.py")"
swift test --disable-sandbox --disable-xctest --enable-swift-testing \
    --cache-path "$TASK_ROOT/.swiftpm-cache" \
    --config-path "$TASK_ROOT/.swiftpm-cache/config" \
    --security-path "$TASK_ROOT/.swiftpm-cache/security" \
    -Xswiftc -vfsoverlay -Xswiftc "$TASK_ROOT/.build/toolchain-overlay.json" "$@"

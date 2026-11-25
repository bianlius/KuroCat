#!/usr/bin/env bash
# Render and exercise the Pikachu skin without launching the app or changing user settings.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT
python3 - "$ROOT" "$CHECK_DIR" <<'PY'
from pathlib import Path
import sys
root, out = map(Path, sys.argv[1:])
(out/'CatPhysics.swift').write_text((root/'Sources/CatPhysics.swift').read_text().replace('private(set) ', ''))
(out/'CatRenderer.swift').write_text((root/'Sources/CatRenderer.swift').read_text().replace('CatSettings.shared', 'RenderSettings.shared'))
PY
swiftc -module-cache-path "$CHECK_DIR/cache" \
    "$ROOT/Sources/KeyMap.swift" "$ROOT/Sources/InputEngine.swift" \
    "$ROOT/Sources/CoatPatterns.swift" "$ROOT/Sources/DoraemonRenderer.swift" \
    "$ROOT/Sources/PikachuRenderer.swift" "$CHECK_DIR/CatPhysics.swift" \
    "$CHECK_DIR/CatRenderer.swift" "$ROOT/tests/pikachu/main.swift" -o "$CHECK_DIR/check" \
    -framework AppKit -framework CoreGraphics -framework QuartzCore -framework IOKit -framework ApplicationServices
"$CHECK_DIR/check" "${1:-$CHECK_DIR}"

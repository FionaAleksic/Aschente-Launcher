#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-0.3.0}"
OWNER="${2:-FionaAleksic}"
REPO="${3:-Aschente-Launcher}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
PACKAGE="$DIST/package"
WIN_VERSION="${VERSION#v}"
WIN_VERSION="${WIN_VERSION%%[-+]*}.0"

GO_WINRES="$(go env GOPATH)/bin/go-winres"
if [[ ! -x "$GO_WINRES" ]]; then
  go install github.com/tc-hib/go-winres@v0.3.3
fi

rm -rf "$DIST"
mkdir -p "$PACKAGE"
rm -f "$ROOT"/launcher/rsrc_windows_*.syso "$ROOT"/installer/rsrc_windows_*.syso
trap 'rm -f "$ROOT"/launcher/rsrc_windows_*.syso "$ROOT"/installer/rsrc_windows_*.syso' EXIT

(
  cd "$ROOT/launcher"
  "$GO_WINRES" make --file-version "$WIN_VERSION" --product-version "$WIN_VERSION"
)
(
  cd "$ROOT/installer"
  "$GO_WINRES" make --file-version "$WIN_VERSION" --product-version "$WIN_VERSION"
)

cd "$ROOT"
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath \
  -ldflags "-s -w -H windowsgui -X main.version=${VERSION#v}" \
  -o "$PACKAGE/Aschente Launcher.exe" ./launcher

GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath \
  -ldflags "-s -w -H windowsgui -X main.version=${VERSION#v}" \
  -o "$DIST/Installer.exe" ./installer

cp LICENSE.txt "$PACKAGE/LICENSE.txt"
mkdir -p "$PACKAGE/Assets"
cp assets/Aschente_Icon.png "$PACKAGE/Assets/Aschente_Icon.png"
cp assets/Aschente_Icon.ico "$PACKAGE/Assets/Aschente_Icon.ico"
cat > "$PACKAGE/README.txt" <<TXT
Aschente Launcher ${VERSION#v}

Repository: https://github.com/$OWNER/$REPO
TXT
cat > "$PACKAGE/version.json" <<JSON
{
  "name": "Aschente Launcher",
  "version": "${VERSION#v}",
  "architecture": "win-x64",
  "repository": "$OWNER/$REPO"
}
JSON

python - "$PACKAGE" "$DIST/Aschente-Launcher-win-x64.zip" <<'PY'
import os, sys, zipfile
src, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, 'w', compression=zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk(src):
        for name in sorted(files):
            full = os.path.join(root, name)
            z.write(full, os.path.relpath(full, src))
PY

(
  cd "$DIST"
  sha256sum Installer.exe Aschente-Launcher-win-x64.zip > SHA256SUMS.txt
)

echo "Build fertig: $DIST"

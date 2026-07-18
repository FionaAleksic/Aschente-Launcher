#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-0.2.0}"
OWNER="${2:-YOUR_GITHUB_USERNAME}"
REPO="${3:-Aschente-Launcher}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
PACKAGE="$DIST/package"

rm -rf "$DIST"
mkdir -p "$PACKAGE"

cd "$ROOT"
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath \
  -ldflags "-s -w -H windowsgui -X main.version=$VERSION" \
  -o "$PACKAGE/Aschente Launcher.exe" ./launcher

GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath \
  -ldflags "-s -w -H windowsgui -X main.version=$VERSION -X main.defaultOwner=$OWNER -X main.defaultRepo=$REPO" \
  -o "$DIST/Installer.exe" ./installer

cp LICENSE.txt "$PACKAGE/LICENSE.txt"
cat > "$PACKAGE/README.txt" <<TXT
Aschente Launcher $VERSION

Repository: https://github.com/$OWNER/$REPO
TXT
cat > "$PACKAGE/version.json" <<JSON
{
  "name": "Aschente Launcher",
  "version": "$VERSION",
  "architecture": "win-x64",
  "repository": "$OWNER/$REPO"
}
JSON

python - "$PACKAGE" "$DIST/Aschente-Launcher-win-x64.zip" <<'PY'
import os, sys, zipfile
src, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, 'w', compression=zipfile.ZIP_DEFLATED) as z:
    for name in sorted(os.listdir(src)):
        z.write(os.path.join(src, name), name)
PY

(
  cd "$DIST"
  sha256sum Installer.exe Aschente-Launcher-win-x64.zip > SHA256SUMS.txt
)

echo "Build fertig: $DIST"

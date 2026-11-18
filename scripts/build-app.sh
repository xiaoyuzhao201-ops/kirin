#!/bin/bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
swift build --configuration release --product CodexContextLauncher
binary_dir=$(swift build --configuration release --show-bin-path)
mkdir -p "$root/dist"
staging=$(mktemp -d "$root/dist/.staging.XXXXXXXX")
trap 'rm -rf -- "$staging"' EXIT
app_name='Codex 上下文启动器.app'
app="$staging/$app_name"
mkdir -p "$app/Contents/MacOS"
install -m 755 "$binary_dir/CodexContextLauncher" "$app/Contents/MacOS/CodexContextLauncher"
install -m 644 "$root/scripts/Info.plist" "$app/Contents/Info.plist"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
destination="$root/dist/$app_name"
if [[ -e "$destination" ]]; then
    # Only replace the bundle assembled in this project's own distribution folder.
    rm -rf -- "$destination"
fi
mv "$app" "$destination"
printf '%s\n' "$destination"

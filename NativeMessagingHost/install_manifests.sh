#!/bin/bash
# install_manifests.sh — Installs Native Messaging manifests for Chrome and Firefox.
# Run once after installing Macin.app to /Applications, or with --extension-id to patch the ID.
#
# Usage:
#   ./install_manifests.sh                              — install manifests with placeholder ID
#   ./install_manifests.sh --extension-id <EXT_ID>     — install and patch Chrome with real ID
#
# How to find your Chrome Extension ID:
#   1. Open Chrome → chrome://extensions
#   2. Enable "Developer mode" (toggle, top-right)
#   3. Find "Macin Download Manager" in the list
#   4. Copy the ID string (32 lowercase letters), e.g. abcdefghijklmnopabcdefghijklmnop
#   5. Re-run: ./install_manifests.sh --extension-id abcdefghijklmnopabcdefghijklmnop

set -euo pipefail

CHROME_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
FIREFOX_DIR="$HOME/Library/Application Support/Mozilla/NativeMessagingHosts"
MANIFEST_NAME="com.krishpotanwar.macin.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTENSION_ID=""

# Parse --extension-id argument
while [[ $# -gt 0 ]]; do
    case "$1" in
        --extension-id)
            EXTENSION_ID="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

install_manifest() {
  local dest_dir="$1"
  local src="$2"
  mkdir -p "$dest_dir"
  cp "$src" "$dest_dir/$MANIFEST_NAME"
  echo "✓ Installed to $dest_dir/$MANIFEST_NAME"
}

echo "Installing Macin Native Messaging manifests..."

if [ -d "/Applications/Google Chrome.app" ]; then
  install_manifest "$CHROME_DIR" "$SCRIPT_DIR/Manifests/com.krishpotanwar.macin.chrome.json"

  if [ -n "$EXTENSION_ID" ]; then
    MANIFEST_PATH="$CHROME_DIR/$MANIFEST_NAME"
    # Replace the placeholder with the real extension ID using sed (in-place, macOS compatible)
    sed -i '' "s/REPLACE_WITH_EXTENSION_ID/$EXTENSION_ID/g" "$MANIFEST_PATH"
    echo "✓ Patched Chrome manifest with extension ID: $EXTENSION_ID"
  else
    echo ""
    echo "⚠️  ACTION REQUIRED: patch the Chrome manifest with your real extension ID:"
    echo "   1. Open Chrome → chrome://extensions"
    echo "   2. Enable Developer mode, find 'Macin Download Manager', copy its ID"
    echo "   3. Run: $0 --extension-id <YOUR_EXTENSION_ID>"
    echo "   OR manually edit: $CHROME_DIR/$MANIFEST_NAME"
  fi
else
  echo "  Chrome not found — skipping Chrome manifest"
fi

if [ -d "/Applications/Firefox.app" ]; then
  install_manifest "$FIREFOX_DIR" "$SCRIPT_DIR/Manifests/com.krishpotanwar.macin.firefox.json"
else
  echo "  Firefox not found — skipping Firefox manifest"
fi

echo ""
echo "Done. Restart your browser for changes to take effect."

# Macin — Download Manager for Mac

An IDM-style download manager for macOS with a Chrome extension.
Parallel chunk downloads, smart file routing, and a confirmation popup for every download.

---

## Download

**[⬇ Download Macin v1.0.0](https://github.com/Krishpotanwar/Macin/releases/latest/download/Macin.app.zip)**

Requires macOS 14 (Sonoma) or later. No Xcode needed.

---

## Installation

### 1 — Install the Mac app

1. Download **Macin.app.zip** from the link above
2. Unzip it (double-click the zip)
3. Drag **MacinDownloadManager.app** to your `/Applications` folder
4. Open it — if macOS blocks it, go to **System Settings → Privacy & Security** and click **Open Anyway**

---

### 2 — Load the Chrome extension

The extension intercepts downloads and shows a confirmation popup (like IDM).

**Step 1 — Get the extension files**

Clone or download this repo:
```bash
git clone https://github.com/Krishpotanwar/Macin.git
```
The extension is in the `ChromeExtension/` folder.

**Step 2 — Load it in Chrome**

1. Open Chrome and go to `chrome://extensions`
2. Enable **Developer mode** (toggle in the top-right corner)

   ![Developer mode toggle](https://i.imgur.com/placeholder-devmode.png)

3. Click **Load unpacked**
4. Select the `ChromeExtension/` folder from this repo
5. The Macin extension will appear in the list — **copy its Extension ID** (a 32-character string like `abcdefghijklmnopabcdefghijklmnop`)

---

### 3 — Connect the extension to the app (Native Messaging)

This one-time setup lets Chrome talk directly to the Macin app.

**Step 1 — Build the Native Messaging Host**

The NMH is a small Swift binary. Build it:
```bash
cd NativeMessagingHost
swiftc main.swift -o MacinNativeMessagingHost -O
```

Or build via Xcode after generating the project:
```bash
brew install xcodegen
xcodegen generate
open MacinDownloadManager.xcodeproj
# Build the MacinNativeMessagingHost target
```

Copy the built binary to `/Applications`:
```bash
cp MacinNativeMessagingHost /Applications/MacinNativeMessagingHost
```

**Step 2 — Install the manifests**

```bash
cd NativeMessagingHost
chmod +x install_manifests.sh
./install_manifests.sh --extension-id YOUR_EXTENSION_ID_HERE
```

Replace `YOUR_EXTENSION_ID_HERE` with the ID you copied in Step 2 above.

Example:
```bash
./install_manifests.sh --extension-id abcdefghijklmnopabcdefghijklmnop
```

**Step 3 — Restart Chrome**

Close and reopen Chrome. The extension is now connected.

---

## How it works

1. **Click any download link** in Chrome
2. Chrome intercepts it — a **Macin confirmation popup** appears:
   - Shows the filename and download URL
   - Lets you choose the save location (Downloads, Documents, Movies, etc.)
   - Or type a custom path
3. Click **Download** — the file downloads in Macin with parallel segments
4. When complete, click the **folder icon** on the card to reveal the file in Finder

**Right-click** any link and choose **"Download with Macin"** to use the context menu.

---

## Features

| Feature | Details |
|---------|---------|
| **Parallel chunks** | 4 simultaneous segments per file (IDM-style progress bars) |
| **Smart routing** | `.pdf` → Documents, `.mp4` → Movies, `.mp3` → Music, `.zip` → Downloads |
| **Custom save path** | Pick from presets or type any folder in the confirm popup |
| **Pause / Resume** | Per-file and bulk pause/resume all |
| **Reveal in Finder** | One click on completed downloads |
| **Google Drive** | Works with Google Drive download links |
| **Status bar** | App lives in the menu bar, always running in background |

---

## Building from source

Requirements: **Xcode 16+**, **Rust** (for the download engine), **XcodeGen**

```bash
# Install tools
brew install xcodegen
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Build Rust engine
cd MacinRustEngine
cargo build --release

# Generate and open Xcode project
cd ..
xcodegen generate
open MacinDownloadManager.xcodeproj
```

Press **⌘R** to run.

---

## Troubleshooting

**"Macin app not running" in the extension popup**
- Make sure MacinDownloadManager.app is open
- The app must be running before downloads can be intercepted

**Chrome extension not intercepting downloads**
- Check that the NMH binary exists at `/Applications/MacinNativeMessagingHost`
- Re-run `install_manifests.sh` with your correct Extension ID
- Restart Chrome after installing manifests

**macOS won't open the app ("unidentified developer")**
- Go to **System Settings → Privacy & Security** → scroll down → click **Open Anyway**
- Or run: `xattr -dr com.apple.quarantine /Applications/MacinDownloadManager.app`

**Extension ID changed after reinstalling**
- Re-run `install_manifests.sh --extension-id NEW_ID` and restart Chrome

---

## Project structure

```
MacinApp/               Swift app (SwiftUI, macOS)
MacinRustEngine/        Rust parallel download engine (staticlib)
ChromeExtension/        Chrome MV3 extension
NativeMessagingHost/    Swift CLI — bridges Chrome ↔ app (port 54322)
project.yml             XcodeGen project definition
MacinApp.entitlements   App sandbox + network entitlements
```

---

## License

MIT

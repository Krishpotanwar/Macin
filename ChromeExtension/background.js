// background.js — Macin Chrome Extension service worker
// Intercepts downloads, shows IDM-style confirm popup, then hands off to Macin.

const NMH_ID = "com.krishpotanwar.macin";

// Intercept Chrome download events (includes Google Drive, direct links, etc.)
chrome.downloads.onCreated.addListener((downloadItem) => {
  const url = downloadItem.url;
  if (!url.startsWith("http://") && !url.startsWith("https://")) return;

  // Cancel Chrome's download immediately
  chrome.downloads.cancel(downloadItem.id, () => {
    chrome.downloads.erase({ id: downloadItem.id });
  });

  // Use browser-provided filename (populated from Content-Disposition) when available.
  // Falls back to guessing from the URL path (handles Google Drive, etc.)
  const filename = cleanFilename(downloadItem.filename) || guessFilename(url);
  openConfirmPopup(url, filename);
});

// Right-click context menu: "Download with Macin"
chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: "macin-download",
    title: "Download with Macin",
    contexts: ["link"]
  });
});

chrome.contextMenus.onClicked.addListener((info) => {
  if (info.menuItemId === "macin-download" && info.linkUrl) {
    openConfirmPopup(info.linkUrl, guessFilename(info.linkUrl));
  }
});

// Messages from popup.js and confirm.js
chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message.action === "add_url" && message.url) {
    // Manual URL typed in popup — send directly, no confirm needed
    sendToMacin(message.url, "", "");
    sendResponse({ status: "ok" });
  } else if (message.action === "confirm_download" && message.url) {
    // User confirmed in the confirm popup
    sendToMacin(message.url, message.destination || "", message.filename || "");
    sendResponse({ status: "ok" });
  } else if (message.action === "open_folder") {
    openFolderInMacin(sendResponse);
    return true; // keep channel open for async response
  }
});

// ── Core functions ────────────────────────────────────────────────────────────

function sendToMacin(url, destination, filename) {
  chrome.runtime.sendNativeMessage(
    NMH_ID,
    { action: "add_download", url, destination, filename },
    (response) => {
      if (chrome.runtime.lastError) {
        console.error("[Macin] Native messaging error:", chrome.runtime.lastError.message);
        return;
      }
      console.log("[Macin] Response:", response);
    }
  );
}

function openConfirmPopup(url, filename) {
  const confirmUrl = chrome.runtime.getURL(
    `confirm.html?url=${encodeURIComponent(url)}&filename=${encodeURIComponent(filename)}`
  );
  chrome.windows.create({ url: confirmUrl, type: "popup", width: 420, height: 280, focused: true });
}

function openFolderInMacin(sendResponse) {
  chrome.runtime.sendNativeMessage(
    NMH_ID,
    { action: "open_folder" },
    (response) => {
      if (chrome.runtime.lastError) {
        sendResponse({ status: "error", message: chrome.runtime.lastError.message });
        return;
      }
      sendResponse(response || { status: "ok" });
    }
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function guessFilename(url) {
  try {
    const path = new URL(url).pathname;
    const parts = path.split("/").filter(Boolean);
    const last = parts[parts.length - 1] || "";
    return last ? decodeURIComponent(last) : "download";
  } catch { return "download"; }
}

// Chrome provides the full local path in downloadItem.filename; extract just the name.
function cleanFilename(fullPath) {
  if (!fullPath) return "";
  const parts = fullPath.replace(/\\/g, "/").split("/");
  return parts[parts.length - 1] || "";
}

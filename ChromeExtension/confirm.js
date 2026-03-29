// confirm.js — IDM-style download confirmation popup

const params = new URLSearchParams(window.location.search);
const downloadUrl = params.get("url") || "";
const suggestedFilename = params.get("filename") || guessFilename(downloadUrl);

// Populate filename + URL
document.getElementById("filename").textContent = suggestedFilename;
document.getElementById("url").textContent = truncateUrl(downloadUrl, 65);

// Pre-select the smart save path
const smartPath = smartSavePath(suggestedFilename);
const select = document.getElementById("pathSelect");
const customInput = document.getElementById("pathCustom");

// Set the dropdown to the smart path (or Downloads as fallback)
for (const opt of select.options) {
  if (opt.value === smartPath) { opt.selected = true; break; }
}

select.addEventListener("change", () => {
  if (select.value === "custom") {
    customInput.style.display = "block";
    customInput.focus();
  } else {
    customInput.style.display = "none";
  }
});

document.getElementById("downloadBtn").addEventListener("click", () => {
  const destination = select.value === "custom"
    ? (customInput.value.trim() || "~/Downloads")
    : select.value;

  chrome.runtime.sendMessage(
    { action: "confirm_download", url: downloadUrl, filename: suggestedFilename, destination },
    () => window.close()
  );
});

document.getElementById("cancelBtn").addEventListener("click", () => window.close());

// ── Helpers ──────────────────────────────────────────────────────────────────

function guessFilename(url) {
  try {
    const path = new URL(url).pathname;
    const parts = path.split("/").filter(Boolean);
    const last = parts[parts.length - 1] || "";
    return last ? decodeURIComponent(last) : "download";
  } catch { return "download"; }
}

function truncateUrl(url, max) {
  return url.length <= max ? url : url.slice(0, max) + "…";
}

function smartSavePath(name) {
  const ext = name.split(".").pop().toLowerCase();
  const videos = ["mp4", "mov", "mkv", "avi", "wmv", "flv", "webm", "m4v"];
  const audio  = ["mp3", "m4a", "flac", "aac", "wav", "ogg", "opus"];
  const images = ["jpg", "jpeg", "png", "gif", "webp", "svg", "heic", "bmp"];
  const docs   = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "csv"];
  if (videos.includes(ext)) return "~/Movies";
  if (audio.includes(ext))  return "~/Music";
  if (images.includes(ext)) return "~/Pictures";
  if (docs.includes(ext))   return "~/Documents";
  return "~/Downloads";
}

document.getElementById("addBtn").addEventListener("click", () => {
  const url = document.getElementById("urlInput").value.trim();
  const status = document.getElementById("status");

  if (!url.startsWith("http://") && !url.startsWith("https://")) {
    status.style.color = "#ff453a";
    status.textContent = "Please enter a valid http/https URL.";
    return;
  }

  chrome.runtime.sendMessage({ action: "add_url", url: url }, () => {
    status.style.color = "#30d158";
    status.textContent = "Sent to Macin!";
    document.getElementById("urlInput").value = "";
  });
});

document.getElementById("folderBtn").addEventListener("click", () => {
  const status = document.getElementById("status");
  chrome.runtime.sendMessage({ action: "open_folder" }, (response) => {
    if (chrome.runtime.lastError || !response || response.status !== "ok") {
      status.style.color = "#ff453a";
      status.textContent = "Macin app not running.";
    } else {
      status.style.color = "#30d158";
      status.textContent = "Opened in Finder!";
    }
  });
});

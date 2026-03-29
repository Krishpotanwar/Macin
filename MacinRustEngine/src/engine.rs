// engine.rs — DownloadEngine: owns all active tasks, drives the Tokio runtime

use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{broadcast, Mutex};
use uuid::Uuid;

use crate::progress::ProgressEvent;
use crate::resume::ResumeState;
use crate::segment::download_file;

/// Status of a single download task.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum TaskStatus {
    Waiting,
    Downloading,
    Paused,
    Completed,
    Failed,
}

/// Snapshot of a download task (serialised to JSON for FFI + WebSocket).
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TaskSnapshot {
    pub id: String,
    pub url: String,
    pub filename: String,
    pub total_bytes: u64,
    pub downloaded_bytes: u64,
    pub bytes_per_second: f64,
    pub status: TaskStatus,
    /// Resolved destination directory (smart-routed). Empty until download starts.
    #[serde(default)]
    pub destination: String,
}

/// Internal mutable state for one download.
pub(crate) struct TaskState {
    pub(crate) snapshot: TaskSnapshot,
    /// Signal to abort the download loop.
    cancel_tx: Option<tokio::sync::oneshot::Sender<()>>,
}

pub struct DownloadEngine {
    tasks: Arc<Mutex<HashMap<String, TaskState>>>,
    progress_tx: broadcast::Sender<ProgressEvent>,
    /// Maximum simultaneous active downloads.
    max_concurrent: usize,
}

impl DownloadEngine {
    pub fn new() -> Self {
        let (progress_tx, _) = broadcast::channel(256);
        Self {
            tasks: Arc::new(Mutex::new(HashMap::new())),
            progress_tx,
            max_concurrent: 3,
        }
    }

    /// Subscribe handle for the WebSocket server.
    pub fn progress_sender(&self) -> broadcast::Sender<ProgressEvent> {
        self.progress_tx.clone()
    }

    /// Enqueue a new download. Returns the task UUID.
    pub async fn add_download(&mut self, url: String, _dest_dir: String) -> String {
        let id = Uuid::new_v4().to_string();
        let filename = url
            .rsplit('/')
            .next()
            .unwrap_or("download")
            .to_owned();
        let filename = if filename.is_empty() { "download".to_owned() } else { filename };

        let snapshot = TaskSnapshot {
            id: id.clone(),
            url: url.clone(),
            filename: filename.clone(),
            total_bytes: 0,
            downloaded_bytes: 0,
            bytes_per_second: 0.0,
            status: TaskStatus::Waiting,
            destination: String::new(),
        };

        {
            let mut tasks = self.tasks.lock().await;
            tasks.insert(id.clone(), TaskState { snapshot: snapshot.clone(), cancel_tx: None });
        }

        self.maybe_start_next().await;
        id
    }

    /// Pause a downloading task. Returns false if not found or not downloading.
    pub fn pause(&mut self, id: &str) -> bool {
        // We need a synchronous entry point for FFI — use try_lock.
        if let Ok(mut tasks) = self.tasks.try_lock() {
            if let Some(state) = tasks.get_mut(id) {
                if state.snapshot.status == TaskStatus::Downloading {
                    // Signal the download loop to stop.
                    if let Some(tx) = state.cancel_tx.take() {
                        let _ = tx.send(());
                    }
                    state.snapshot.status = TaskStatus::Paused;
                    state.snapshot.bytes_per_second = 0.0;

                    // Persist resume state so we can continue from where we left off.
                    let snap = state.snapshot.clone();
                    let resume = ResumeState {
                        id: snap.id.clone(),
                        url: snap.url.clone(),
                        downloaded_bytes: snap.downloaded_bytes,
                        total_bytes: snap.total_bytes,
                    };
                    let _ = resume.save(&snap.filename);
                    return true;
                }
            }
        }
        false
    }

    /// Resume a paused task.
    pub fn resume(&mut self, id: &str) -> bool {
        if let Ok(mut tasks) = self.tasks.try_lock() {
            if let Some(state) = tasks.get_mut(id) {
                if state.snapshot.status == TaskStatus::Paused {
                    state.snapshot.status = TaskStatus::Waiting;
                    return true;
                }
            }
        }
        // Kick the scheduler on a background task.
        let tasks_ref = self.tasks.clone();
        let tx = self.progress_tx.clone();
        tokio::spawn(async move {
            let _ = tasks_ref; // keep alive
            let _ = tx;
        });
        false
    }

    /// Cancel a task (removes it from the engine).
    pub fn cancel(&mut self, id: &str) -> bool {
        if let Ok(mut tasks) = self.tasks.try_lock() {
            if let Some(mut state) = tasks.remove(id) {
                if let Some(tx) = state.cancel_tx.take() {
                    let _ = tx.send(());
                }
                return true;
            }
        }
        false
    }

    /// JSON snapshot of all tasks.
    pub fn status_json(&self) -> String {
        if let Ok(tasks) = self.tasks.try_lock() {
            let snapshots: Vec<&TaskSnapshot> = tasks.values().map(|s| &s.snapshot).collect();
            serde_json::to_string(&snapshots).unwrap_or_else(|_| "[]".to_owned())
        } else {
            "[]".to_owned()
        }
    }

    /// Start up to `max_concurrent` waiting tasks.
    async fn maybe_start_next(&mut self) {
        let active_count = {
            let tasks = self.tasks.lock().await;
            tasks.values().filter(|s| s.snapshot.status == TaskStatus::Downloading).count()
        };
        let slots = self.max_concurrent.saturating_sub(active_count);
        if slots == 0 {
            return;
        }

        let waiting_ids: Vec<String> = {
            let tasks = self.tasks.lock().await;
            tasks
                .values()
                .filter(|s| s.snapshot.status == TaskStatus::Waiting)
                .take(slots)
                .map(|s| s.snapshot.id.clone())
                .collect()
        };

        for id in waiting_ids {
            self.start_task(&id).await;
        }
    }

    async fn start_task(&mut self, id: &str) {
        let (cancel_tx, cancel_rx) = tokio::sync::oneshot::channel::<()>();
        let snapshot = {
            let mut tasks = self.tasks.lock().await;
            let state = match tasks.get_mut(id) {
                Some(s) => s,
                None => return,
            };
            state.snapshot.status = TaskStatus::Downloading;
            state.cancel_tx = Some(cancel_tx);
            state.snapshot.clone()
        };

        let tasks_ref = self.tasks.clone();
        let progress_tx = self.progress_tx.clone();

        tokio::spawn(async move {
            let result = download_file(
                snapshot.id.clone(),
                snapshot.url.clone(),
                snapshot.filename.clone(),
                snapshot.downloaded_bytes,
                tasks_ref.clone(),
                progress_tx.clone(),
                cancel_rx,
            )
            .await;

            let final_status = match result {
                Ok(_) => TaskStatus::Completed,
                Err(_) => TaskStatus::Failed,
            };

            let mut tasks = tasks_ref.lock().await;
            if let Some(state) = tasks.get_mut(&snapshot.id) {
                if state.snapshot.status == TaskStatus::Downloading {
                    state.snapshot.status = final_status.clone();
                    state.snapshot.bytes_per_second = 0.0;
                    let _ = progress_tx.send(ProgressEvent {
                        id: snapshot.id.clone(),
                        downloaded_bytes: state.snapshot.downloaded_bytes,
                        total_bytes: state.snapshot.total_bytes,
                        bytes_per_second: 0.0,
                        status: final_status.to_string(),
                        segment_bytes: vec![],
                        eta_seconds: 0.0,
                        destination: state.snapshot.destination.clone(),
                    });
                }
            }
        });
    }
}

impl TaskStatus {
    fn to_string(&self) -> String {
        match self {
            TaskStatus::Waiting => "waiting",
            TaskStatus::Downloading => "downloading",
            TaskStatus::Paused => "paused",
            TaskStatus::Completed => "completed",
            TaskStatus::Failed => "failed",
        }
        .to_owned()
    }
}

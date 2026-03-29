// resume.rs — .macin_resume sidecar file for surviving pauses and app restarts

use std::path::PathBuf;
use serde::{Deserialize, Serialize};

/// Persisted resume state written alongside the partial download file.
#[derive(Debug, Serialize, Deserialize)]
pub struct ResumeState {
    pub id: String,
    pub url: String,
    pub downloaded_bytes: u64,
    pub total_bytes: u64,
}

#[allow(dead_code)]
impl ResumeState {
    /// Save resume state to `~/Downloads/<filename>.macin_resume`.
    pub fn save(&self, filename: &str) -> Result<(), Box<dyn std::error::Error>> {
        let path = resume_path(filename);
        let json = serde_json::to_string_pretty(self)?;
        std::fs::write(path, json)?;
        Ok(())
    }

    /// Load resume state from `~/Downloads/<filename>.macin_resume`.
    /// Returns `None` if the file doesn't exist.
    pub fn load(filename: &str) -> Option<Self> {
        let path = resume_path(filename);
        let data = std::fs::read_to_string(path).ok()?;
        serde_json::from_str(&data).ok()
    }

    /// Delete the resume sidecar after a completed or cancelled download.
    pub fn delete(filename: &str) {
        let path = resume_path(filename);
        let _ = std::fs::remove_file(path);
    }
}

fn resume_path(filename: &str) -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_owned());
    PathBuf::from(home)
        .join("Downloads")
        .join(format!("{}.macin_resume", filename))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_save_load() {
        let state = ResumeState {
            id: "test-id".to_owned(),
            url: "https://example.com/file.zip".to_owned(),
            downloaded_bytes: 1024,
            total_bytes: 4096,
        };
        // Use a temp filename unlikely to collide.
        let fname = "macin_test_round_trip.zip";
        state.save(fname).expect("save failed");
        let loaded = ResumeState::load(fname).expect("load returned None");
        assert_eq!(loaded.id, state.id);
        assert_eq!(loaded.downloaded_bytes, state.downloaded_bytes);
        assert_eq!(loaded.total_bytes, state.total_bytes);
        ResumeState::delete(fname);
        assert!(ResumeState::load(fname).is_none());
    }

    #[test]
    fn load_missing_returns_none() {
        assert!(ResumeState::load("definitely_does_not_exist.zip").is_none());
    }
}

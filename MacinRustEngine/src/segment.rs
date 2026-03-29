// segment.rs — HTTP Range request downloader with parallel segments

use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::fs::{File, OpenOptions};
use tokio::io::AsyncWriteExt;
use tokio::sync::{broadcast, Mutex};

use crate::engine::TaskStatus;
use crate::progress::ProgressEvent;

const SEGMENT_COUNT: u64 = 4;
const SPEED_WINDOW_SECS: f64 = 3.0;

/// Resolve the smart destination folder based on file extension.
/// Mirrors IDM's automatic categorisation:
///   Documents → ~/Documents, Video → ~/Movies, Audio → ~/Music, else → ~/Downloads
pub fn smart_destination(filename: &str) -> String {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_owned());
    let ext = filename
        .rsplit('.')
        .next()
        .unwrap_or("")
        .to_lowercase();

    let folder = match ext.as_str() {
        // Documents
        "pdf" | "doc" | "docx" | "xls" | "xlsx" | "ppt" | "pptx" | "txt" | "rtf" | "odt" => "Documents",
        // Video
        "mp4" | "mov" | "avi" | "mkv" | "m4v" | "wmv" | "flv" | "webm" | "mpg" | "mpeg" => "Movies",
        // Audio
        "mp3" | "aac" | "flac" | "wav" | "ogg" | "m4a" | "wma" | "aiff" => "Music",
        // Images
        "jpg" | "jpeg" | "png" | "gif" | "bmp" | "tiff" | "webp" | "heic" | "svg" => "Pictures",
        // Everything else (DMG, ZIP, EXE, etc.)
        _ => "Downloads",
    };
    format!("{}/{}", home, folder)
}

/// Download a single file, using parallel range segments if the server supports it.
/// Falls back to single-stream if `Accept-Ranges` is absent.
/// Uses smart_destination() to route the file to the correct macOS folder.
pub async fn download_file(
    id: String,
    url: String,
    filename: String,
    resume_offset: u64,
    tasks: Arc<Mutex<HashMap<String, crate::engine::TaskState>>>,
    progress_tx: broadcast::Sender<ProgressEvent>,
    mut cancel_rx: tokio::sync::oneshot::Receiver<()>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(30))
        .build()?;

    // HEAD request to determine file size and range support.
    let head = client.head(&url).send().await?;
    let total_bytes = head
        .headers()
        .get(reqwest::header::CONTENT_LENGTH)
        .and_then(|v| v.to_str().ok())
        .and_then(|s| s.parse::<u64>().ok())
        .unwrap_or(0);
    let accepts_ranges = head
        .headers()
        .get(reqwest::header::ACCEPT_RANGES)
        .map(|v| v != "none")
        .unwrap_or(false);

    // Smart routing: pick destination folder based on file type.
    let dest_dir = smart_destination(&filename);
    // Ensure the destination directory exists.
    let _ = std::fs::create_dir_all(&dest_dir);
    let dest_path = format!("{}/{}", dest_dir, filename);

    // Update total_bytes and destination in engine state.
    {
        let mut tasks_guard = tasks.lock().await;
        if let Some(state) = tasks_guard.get_mut(&id) {
            state.snapshot.total_bytes = total_bytes;
            state.snapshot.destination = dest_dir.clone();
        }
    }

    if accepts_ranges && total_bytes > 0 && SEGMENT_COUNT > 1 {
        download_parallel(
            id, url, dest_path, dest_dir, total_bytes, resume_offset,
            tasks, progress_tx, &mut cancel_rx,
        )
        .await
    } else {
        download_single(
            id, url, dest_path, dest_dir, resume_offset,
            tasks, progress_tx, &mut cancel_rx,
        )
        .await
    }
}

async fn download_parallel(
    id: String,
    url: String,
    dest_path: String,
    dest_dir: String,
    total_bytes: u64,
    resume_offset: u64,
    tasks: Arc<Mutex<HashMap<String, crate::engine::TaskState>>>,
    progress_tx: broadcast::Sender<ProgressEvent>,
    cancel_rx: &mut tokio::sync::oneshot::Receiver<()>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let segment_size = total_bytes / SEGMENT_COUNT;
    // Track per-segment bytes in shared atomic array.
    let seg_bytes: Arc<parking_lot::Mutex<[u64; 4]>> = Arc::new(parking_lot::Mutex::new([0u64; 4]));
    let mut handles = Vec::new();

    for i in 0..SEGMENT_COUNT {
        let start = i * segment_size + if i == 0 { resume_offset } else { 0 };
        let end = if i == SEGMENT_COUNT - 1 { total_bytes - 1 } else { (i + 1) * segment_size - 1 };
        if start > end { continue; }

        let seg_path = format!("{}.seg{}", dest_path, i);
        let url_clone = url.clone();
        let id_clone = id.clone();
        let tasks_clone = tasks.clone();
        let tx_clone = progress_tx.clone();
        let seg_bytes_clone = seg_bytes.clone();

        handles.push(tokio::spawn(async move {
            download_segment(id_clone, url_clone, seg_path, start, end, i as usize, tasks_clone, tx_clone, seg_bytes_clone).await
        }));
    }

    let mut downloaded_so_far = resume_offset;
    let start_time = Instant::now();

    loop {
        tokio::select! {
            _ = &mut *cancel_rx => {
                for h in handles {
                    h.abort();
                }
                return Ok(());
            }
            _ = tokio::time::sleep(Duration::from_millis(200)) => {
                let tasks_guard = tasks.lock().await;
                if let Some(state) = tasks_guard.get(&id) {
                    if state.snapshot.status != TaskStatus::Downloading {
                        break;
                    }
                    downloaded_so_far = state.snapshot.downloaded_bytes;
                }
                drop(tasks_guard);

                let elapsed = start_time.elapsed().as_secs_f64().max(0.001);
                let speed = if elapsed < SPEED_WINDOW_SECS {
                    downloaded_so_far as f64 / elapsed
                } else {
                    downloaded_so_far as f64 / SPEED_WINDOW_SECS
                };

                let eta = if speed > 0.0 && total_bytes > downloaded_so_far {
                    (total_bytes - downloaded_so_far) as f64 / speed
                } else {
                    0.0
                };

                let seg_snapshot = { *seg_bytes.lock() };

                let _ = progress_tx.send(ProgressEvent {
                    id: id.clone(),
                    downloaded_bytes: downloaded_so_far,
                    total_bytes,
                    bytes_per_second: speed,
                    status: "downloading".to_owned(),
                    segment_bytes: seg_snapshot.to_vec(),
                    eta_seconds: eta,
                    destination: dest_dir.clone(),
                });

                if downloaded_so_far >= total_bytes {
                    break;
                }
            }
        }
    }

    for h in handles {
        let _ = h.await;
    }
    assemble_segments(&dest_path, SEGMENT_COUNT).await?;
    Ok(())
}

async fn download_segment(
    id: String,
    url: String,
    seg_path: String,
    start: u64,
    end: u64,
    seg_index: usize,
    tasks: Arc<Mutex<HashMap<String, crate::engine::TaskState>>>,
    progress_tx: broadcast::Sender<ProgressEvent>,
    seg_bytes: Arc<parking_lot::Mutex<[u64; 4]>>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let client = reqwest::Client::new();
    let range_header = format!("bytes={}-{}", start, end);
    let resp = client
        .get(&url)
        .header(reqwest::header::RANGE, range_header)
        .send()
        .await?;

    let mut file = File::create(&seg_path).await?;
    let mut stream = resp.bytes_stream();
    use futures_util::StreamExt;

    while let Some(chunk) = stream.next().await {
        let chunk = chunk?;
        file.write_all(&chunk).await?;
        let len = chunk.len() as u64;

        let mut tasks_guard = tasks.lock().await;
        if let Some(state) = tasks_guard.get_mut(&id) {
            state.snapshot.downloaded_bytes += len;
        }
        drop(tasks_guard);

        // Update per-segment counter.
        if seg_index < 4 {
            let mut segs = seg_bytes.lock();
            segs[seg_index] += len;
        }
    }

    let _ = progress_tx;
    Ok(())
}

async fn download_single(
    id: String,
    url: String,
    dest_path: String,
    dest_dir: String,
    resume_offset: u64,
    tasks: Arc<Mutex<HashMap<String, crate::engine::TaskState>>>,
    progress_tx: broadcast::Sender<ProgressEvent>,
    cancel_rx: &mut tokio::sync::oneshot::Receiver<()>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let client = reqwest::Client::new();
    let mut req = client.get(&url);
    if resume_offset > 0 {
        req = req.header(reqwest::header::RANGE, format!("bytes={}-", resume_offset));
    }
    let resp = req.send().await?;
    let total = resp
        .headers()
        .get(reqwest::header::CONTENT_LENGTH)
        .and_then(|v| v.to_str().ok())
        .and_then(|s| s.parse::<u64>().ok())
        .unwrap_or(0)
        + resume_offset;

    let mut file = if resume_offset > 0 {
        OpenOptions::new().append(true).open(&dest_path).await?
    } else {
        File::create(&dest_path).await?
    };

    let mut downloaded = resume_offset;
    let mut speed_window: Vec<(Instant, u64)> = Vec::new();
    let mut stream = resp.bytes_stream();
    use futures_util::StreamExt;

    loop {
        tokio::select! {
            _ = &mut *cancel_rx => return Ok(()),
            chunk = stream.next() => {
                match chunk {
                    None => break,
                    Some(Ok(bytes)) => {
                        file.write_all(&bytes).await?;
                        downloaded += bytes.len() as u64;
                        let now = Instant::now();
                        speed_window.push((now, bytes.len() as u64));
                        // Keep only last SPEED_WINDOW_SECS of samples.
                        speed_window.retain(|(t, _)| now.duration_since(*t).as_secs_f64() <= SPEED_WINDOW_SECS);
                        let speed = speed_window.iter().map(|(_, b)| b).sum::<u64>() as f64 / SPEED_WINDOW_SECS;

                        let mut tasks_guard = tasks.lock().await;
                        if let Some(state) = tasks_guard.get_mut(&id) {
                            state.snapshot.downloaded_bytes = downloaded;
                            state.snapshot.bytes_per_second = speed;
                        }
                        drop(tasks_guard);

                        let eta = if speed > 0.0 && total > downloaded {
                            (total - downloaded) as f64 / speed
                        } else {
                            0.0
                        };
                        let _ = progress_tx.send(ProgressEvent {
                            id: id.clone(),
                            downloaded_bytes: downloaded,
                            total_bytes: total,
                            bytes_per_second: speed,
                            status: "downloading".to_owned(),
                            segment_bytes: vec![],
                            eta_seconds: eta,
                            destination: dest_dir.clone(),
                        });
                    }
                    Some(Err(e)) => return Err(Box::new(e)),
                }
            }
        }
    }

    Ok(())
}

async fn assemble_segments(dest_path: &str, count: u64) -> std::io::Result<()> {
    let mut out = File::create(dest_path).await?;
    for i in 0..count {
        let seg_path = format!("{}.seg{}", dest_path, i);
        if let Ok(mut seg) = File::open(&seg_path).await {
            tokio::io::copy(&mut seg, &mut out).await?;
            let _ = tokio::fs::remove_file(&seg_path).await;
        }
    }
    Ok(())
}



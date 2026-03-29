// progress.rs — WebSocket server broadcasting progress events at 1Hz to the Swift UI

use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use tokio::net::TcpListener;
use tokio::sync::broadcast;
use tokio_tungstenite::tungstenite::Message;

/// Progress update broadcast to all connected WebSocket clients.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProgressEvent {
    pub id: String,
    pub downloaded_bytes: u64,
    pub total_bytes: u64,
    pub bytes_per_second: f64,
    pub status: String,
    /// Per-segment downloaded bytes (up to 4 segments). Empty for single-stream downloads.
    #[serde(default)]
    pub segment_bytes: Vec<u64>,
    /// Estimated seconds remaining. 0 when unknown.
    #[serde(default)]
    pub eta_seconds: f64,
    /// Destination folder path where the file will be saved.
    #[serde(default)]
    pub destination: String,
}

/// Bind on 127.0.0.1:54321 (loopback only — never exposed to the network).
/// Each WebSocket client receives every `ProgressEvent` from the broadcast channel.
pub async fn start_websocket_server(tx: broadcast::Sender<ProgressEvent>) {
    let addr: SocketAddr = "127.0.0.1:54321".parse().expect("invalid address");
    let listener = match TcpListener::bind(addr).await {
        Ok(l) => l,
        Err(e) => {
            eprintln!("[macin] WebSocket bind failed: {e}");
            return;
        }
    };
    eprintln!("[macin] WebSocket server listening on {addr}");

    loop {
        let (stream, peer) = match listener.accept().await {
            Ok(pair) => pair,
            Err(e) => {
                eprintln!("[macin] accept error: {e}");
                continue;
            }
        };
        let rx = tx.subscribe();
        tokio::spawn(handle_connection(stream, peer, rx));
    }
}

async fn handle_connection(
    stream: tokio::net::TcpStream,
    peer: SocketAddr,
    mut rx: broadcast::Receiver<ProgressEvent>,
) {
    let ws = match tokio_tungstenite::accept_async(stream).await {
        Ok(ws) => ws,
        Err(e) => {
            eprintln!("[macin] WS handshake failed from {peer}: {e}");
            return;
        }
    };
    let (mut sink, mut source) = ws.split();

    loop {
        tokio::select! {
            event = rx.recv() => {
                match event {
                    Ok(ev) => {
                        let json = match serde_json::to_string(&ev) {
                            Ok(j) => j,
                            Err(_) => continue,
                        };
                        if sink.send(Message::Text(json.into())).await.is_err() {
                            break; // client disconnected
                        }
                    }
                    Err(broadcast::error::RecvError::Lagged(_)) => continue,
                    Err(broadcast::error::RecvError::Closed) => break,
                }
            }
            msg = source.next() => {
                // Client closed or sent a close frame.
                match msg {
                    None | Some(Ok(Message::Close(_))) => break,
                    _ => {} // ignore ping/text from client
                }
            }
        }
    }
}

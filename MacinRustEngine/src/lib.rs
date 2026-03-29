// lib.rs — extern "C" FFI entry points for Swift integration
// SAFETY notes accompany every unsafe block.

mod engine;
mod segment;
mod resume;
mod progress;

pub use engine::DownloadEngine;

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::OnceLock;
use tokio::runtime::Runtime;

// Global Tokio runtime shared by all FFI calls.
static RUNTIME: OnceLock<Runtime> = OnceLock::new();

fn runtime() -> &'static Runtime {
    RUNTIME.get_or_init(|| {
        Runtime::new().expect("Failed to create Tokio runtime")
    })
}

// Global engine instance, protected by a Mutex.
static ENGINE: OnceLock<std::sync::Mutex<DownloadEngine>> = OnceLock::new();

fn engine() -> &'static std::sync::Mutex<DownloadEngine> {
    ENGINE.get_or_init(|| {
        let eng = runtime().block_on(async { DownloadEngine::new() });
        std::sync::Mutex::new(eng)
    })
}

/// Initialise the engine and start the WebSocket progress server on 127.0.0.1:54321.
/// Must be called once before any other function.
/// Returns 1 on success, 0 on failure.
#[no_mangle]
pub extern "C" fn macin_init() -> i32 {
    let eng = engine().lock().unwrap();
    let sender = eng.progress_sender();
    drop(eng);
    runtime().spawn(async move {
        progress::start_websocket_server(sender).await;
    });
    1
}

/// Add a download.
/// `url`  — null-terminated UTF-8 C string
/// `dest` — null-terminated UTF-8 destination directory path
/// Returns a null-terminated UUID string (caller must free with `macin_free_string`).
/// Returns null on invalid input.
#[no_mangle]
pub extern "C" fn macin_add_download(url: *const c_char, dest: *const c_char) -> *mut c_char {
    // SAFETY: caller guarantees non-null, valid null-terminated C strings.
    let url_str = unsafe {
        if url.is_null() { return std::ptr::null_mut(); }
        match CStr::from_ptr(url).to_str() {
            Ok(s) => s.to_owned(),
            Err(_) => return std::ptr::null_mut(),
        }
    };
    let dest_str = unsafe {
        if dest.is_null() { return std::ptr::null_mut(); }
        match CStr::from_ptr(dest).to_str() {
            Ok(s) => s.to_owned(),
            Err(_) => return std::ptr::null_mut(),
        }
    };

    // Basic URL validation — only http/https accepted.
    if !url_str.starts_with("http://") && !url_str.starts_with("https://") {
        return std::ptr::null_mut();
    }

    let mut eng = engine().lock().unwrap();
    let id = runtime().block_on(async { eng.add_download(url_str, dest_str).await });
    match CString::new(id) {
        Ok(s) => s.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Pause a download by UUID string. Returns 1 on success, 0 if not found.
#[no_mangle]
pub extern "C" fn macin_pause(id: *const c_char) -> i32 {
    // SAFETY: caller guarantees non-null, valid null-terminated C string.
    let id_str = unsafe {
        if id.is_null() { return 0; }
        match CStr::from_ptr(id).to_str() {
            Ok(s) => s.to_owned(),
            Err(_) => return 0,
        }
    };
    let mut eng = engine().lock().unwrap();
    if eng.pause(&id_str) { 1 } else { 0 }
}

/// Resume a paused download. Returns 1 on success, 0 if not found.
#[no_mangle]
pub extern "C" fn macin_resume(id: *const c_char) -> i32 {
    // SAFETY: caller guarantees non-null, valid null-terminated C string.
    let id_str = unsafe {
        if id.is_null() { return 0; }
        match CStr::from_ptr(id).to_str() {
            Ok(s) => s.to_owned(),
            Err(_) => return 0,
        }
    };
    let mut eng = engine().lock().unwrap();
    if eng.resume(&id_str) { 1 } else { 0 }
}

/// Cancel and remove a download. Returns 1 on success, 0 if not found.
#[no_mangle]
pub extern "C" fn macin_cancel(id: *const c_char) -> i32 {
    // SAFETY: caller guarantees non-null, valid null-terminated C string.
    let id_str = unsafe {
        if id.is_null() { return 0; }
        match CStr::from_ptr(id).to_str() {
            Ok(s) => s.to_owned(),
            Err(_) => return 0,
        }
    };
    let mut eng = engine().lock().unwrap();
    if eng.cancel(&id_str) { 1 } else { 0 }
}

/// Returns a JSON snapshot of all download statuses as a null-terminated C string.
/// Caller must free with `macin_free_string`.
#[no_mangle]
pub extern "C" fn macin_get_status() -> *mut c_char {
    let eng = engine().lock().unwrap();
    let json = eng.status_json();
    match CString::new(json) {
        Ok(s) => s.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Free a string previously returned by this library.
///
/// # Safety
/// `ptr` must be a pointer returned by this library and must not have been freed before.
#[no_mangle]
pub unsafe extern "C" fn macin_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        // SAFETY: ptr was created via CString::into_raw() in this library.
        drop(CString::from_raw(ptr));
    }
}

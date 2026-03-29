// MacinEngine.h — C header for the Macin Rust download engine.
// Auto-maintained: keep in sync with extern "C" functions in lib.rs.

#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Initialise the engine and start the WebSocket server on 127.0.0.1:54321.
/// Call once at app launch. Returns 1 on success, 0 on failure.
int32_t macin_init(void);

/// Add a download. Returns a heap-allocated null-terminated UUID string.
/// Caller must free with macin_free_string(). Returns NULL on invalid input.
char* macin_add_download(const char* url, const char* dest_dir);

/// Pause a downloading task. Returns 1 on success, 0 if not found.
int32_t macin_pause(const char* id);

/// Resume a paused task. Returns 1 on success, 0 if not found.
int32_t macin_resume(const char* id);

/// Cancel and remove a task. Returns 1 on success, 0 if not found.
int32_t macin_cancel(const char* id);

/// Returns a JSON array of all task snapshots as a heap-allocated C string.
/// Caller must free with macin_free_string().
char* macin_get_status(void);

/// Free a string returned by this library.
void macin_free_string(char* ptr);

#ifdef __cplusplus
}
#endif

#pragma once

#include <stdbool.h>

// C entry points exported by the SwiftUI shell (app/swiftui/*.swift).
// All of them must be called on the main thread.
//
// Data crosses the bridge as UTF-8 JSON:
// - computers: [{uuid, name, online, paired, canWake, runningAppId,
//                apps: [{id, name, boxArt}]}]
// - prefs: {resolutionMode, width, height, fps, bitrateKbps, windowMode,
//           vsync, framePacing, hdr, muteHost, disableAwdl}
// - status: {text, busy, error}
// - pairing: {uuid, stage: "waiting" | "paired" | "failed", pin, error}
// - add host result: {success, portBlocking}
// - actions sent back by the shell: {action: "launch", uuid, appId, displayX, displayY}
//   | {action: "cancel"} | {action: "wake", uuid} | {action: "quitApp", uuid}
//   | {action: "setPrefs", prefs} | {action: "pair", uuid} | {action: "addHost", address}
//   | {action: "deleteHost", uuid} | {action: "streamAction", value: Session::StreamAction}
// - stream overlay: begin {computer, app, targetMbps}, stats {fps, width, height,
//   bitrateMbps, rttMs, decodeMs, dropPercent}
//   | {action: "quit"}

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*MVActionCallback)(const char* json);
// Stream state flags polled by the overlay
enum { MV_STREAM_CAPTURED = 1, MV_STREAM_STATS = 2, MV_STREAM_FULLSCREEN = 4 };
typedef int (*MVStreamStateCallback)(void);

void mv_ui_show(MVActionCallback action);
void mv_ui_update_computers(const char* json);
void mv_ui_update_prefs(const char* json);
void mv_ui_set_status(const char* json);
void mv_ui_set_visible(bool visible);
void mv_ui_update_pairing(const char* json);
void mv_ui_add_host_result(const char* json);

// Stream overlays, shown above the SDL stream window (an NSWindow*). Unlike the rest
// of the API, they run while Qt's event loop is suspended, and mv_overlay_stats() is
// called from the decoder thread.
void mv_overlay_begin(void* streamWindow, const char* json, MVStreamStateCallback state);
void mv_overlay_stats(const char* json);
void mv_overlay_end(void);

#ifdef __cplusplus
}
#endif

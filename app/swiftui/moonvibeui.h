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
//   | {action: "deleteHost", uuid}
//   | {action: "quit"}

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*MVActionCallback)(const char* json);

void mv_ui_show(MVActionCallback action);
void mv_ui_update_computers(const char* json);
void mv_ui_update_prefs(const char* json);
void mv_ui_set_status(const char* json);
void mv_ui_set_visible(bool visible);
void mv_ui_update_pairing(const char* json);
void mv_ui_add_host_result(const char* json);

#ifdef __cplusplus
}
#endif

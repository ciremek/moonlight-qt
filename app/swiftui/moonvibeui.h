#pragma once

#include <stdbool.h>

// C entry points exported by the SwiftUI shell (MoonvibeUI.swift).
// All of them must be called on the main thread.

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*MVLaunchCallback)(const char* computerUuid, int appId);
typedef void (*MVQuitCallback)(void);

void mv_ui_show(MVLaunchCallback launch, MVQuitCallback quit);
void mv_ui_update_computers(const char* json);
void mv_ui_set_status(const char* text, bool busy);
void mv_ui_set_visible(bool visible);

#ifdef __cplusplus
}
#endif

# dmgbuild settings for Moonvibe's DMG, used by scripts/package-moonvibe.sh.
#
# dmgbuild writes the window layout (.DS_Store) itself, instead of asking Finder
# through AppleScript, which on recent macOS reverts the icon view options it was
# given. The layout matches make-background.swift: a 660x400 window with Moonvibe
# at (170, 170) and the Applications link at (490, 170).
import os.path

app = defines["app"]

format = "UDZO"
compression_level = 9

files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines["volume_icon"]
background = defines["background"]

window_rect = ((200, 120), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

arrange_by = None
icon_size = 128
text_size = 13
icon_locations = {
    os.path.basename(app): (170, 170),
    "Applications": (490, 170),
}

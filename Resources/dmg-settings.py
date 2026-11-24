# dmgbuild settings for the Contxt installer. Layout matches scripts/make-dmg-background.swift.
import os

app_path = defines.get("app", "Contxt.app")  # noqa: F821 (dmgbuild injects `defines`)
app_name = os.path.basename(app_path)

format = "UDZO"
files = [app_path]
symlinks = {"Applications": "/Applications"}
icon = "Resources/AppIcon.icns"
background = "Resources/dmg-background.tiff"

window_rect = ((200, 140), (660, 440))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 112
text_size = 13
icon_locations = {
    app_name: (180, 265),
    "Applications": (480, 265),
}

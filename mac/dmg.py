# dmg.py lays out the release disk image for dmgbuild: Moorings on the left, an Applications link
# on the right, and a background with an arrow between them. Run through `make dmg`.

app = defines.get("app", ".build/Moorings.app")  # noqa: F821 (dmgbuild provides defines)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon_locations = {"Moorings.app": (170, 190), "Applications": (490, 190)}
background = "dmg-background.tiff"
window_rect = ((200, 140), (660, 400))
default_view = "icon-view"
icon_size = 128
text_size = 13
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True

@tool
extends RefCounted
## "Make project pixel-perfect": a few project settings for crisp pixel art, and their undo.
## The values from before are kept in this project's editor metadata (.godot/editor/), not in
## project.godot, so the undo works across editor restarts and never ends up in a commit.

const META_SECTION := "gridwright_library"
const META_KEY := "pixel_perfect_undo"

const BASE := [
	{"key": "rendering/textures/canvas_textures/default_texture_filter", "to": 0,
		"label": "Default texture filter set to Nearest", "why": "Sprites stay sharp instead of blurring when scaled."},
	{"key": "rendering/2d/snap/snap_2d_transforms_to_pixel", "to": true,
		"label": "Snap 2D transforms to pixel turned on", "why": "Sprites and cameras sit on whole pixels, so nothing shimmers."},
	{"key": "rendering/2d/snap/snap_2d_vertices_to_pixel", "to": true,
		"label": "Snap 2D vertices to pixel turned on", "why": "Polygon and tile edges line up with the pixel grid."},
]
const STRETCH := [
	{"key": "display/window/stretch/mode", "to": "viewport",
		"label": "Stretch mode set to viewport", "why": "The game draws at its base size, then the whole picture is scaled up."},
	{"key": "display/window/stretch/scale_mode", "to": "integer",
		"label": "Stretch scale set to integer", "why": "It scales by whole numbers (2x, 3x, 4x), so every pixel stays square."},
]


## The settings in `group` ("base" or "stretch") that would change, with their current values.
static func pending(group: String) -> Array:
	var out: Array = []
	for item in (BASE if group == "base" else STRETCH):
		var key: String = item["key"]
		if not ProjectSettings.has_setting(key):
			continue  # older Godot without this setting
		var now = ProjectSettings.get_setting(key)
		if now != item["to"]:
			var row: Dictionary = item.duplicate()
			row["from"] = now
			out.append(row)
	return out


static func base_size() -> Vector2i:
	return Vector2i(int(ProjectSettings.get_setting("display/window/size/viewport_width", 1152)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 648)))


static func _undo_data() -> Dictionary:
	var es := EditorInterface.get_editor_settings()
	var data = es.get_project_metadata(META_SECTION, META_KEY, {})
	return data if data is Dictionary else {}


static func can_undo() -> bool:
	return not _undo_data().is_empty()


## Applies the base settings, and the stretch settings too when include_stretch is true.
## Returns { changed: [labels] }. The first value seen for each setting is the one undo restores.
static func apply(include_stretch: bool) -> Dictionary:
	var rows := pending("base")
	if include_stretch:
		rows.append_array(pending("stretch"))
	var data := _undo_data()
	var changed: Array = []
	for row in rows:
		var key: String = row["key"]
		if not data.has(key):
			data[key] = {"from": row["from"], "to": row["to"]}
		else:
			data[key]["to"] = row["to"]
		ProjectSettings.set_setting(key, row["to"])
		changed.append(row["label"])
	if not changed.is_empty():
		ProjectSettings.save()
		EditorInterface.get_editor_settings().set_project_metadata(META_SECTION, META_KEY, data)
	return {"changed": changed}


## Puts back the values from before. A setting changed by hand since then is left as it is.
## Returns { restored: [keys], kept: [keys] }.
static func undo() -> Dictionary:
	var data := _undo_data()
	var restored: Array = []
	var kept: Array = []
	for key in data.keys():
		var entry: Dictionary = data[key]
		if ProjectSettings.has_setting(key) and ProjectSettings.get_setting(key) == entry["to"]:
			ProjectSettings.set_setting(key, entry["from"])
			restored.append(key)
		else:
			kept.append(key)
	ProjectSettings.save()
	EditorInterface.get_editor_settings().set_project_metadata(META_SECTION, META_KEY, {})
	return {"restored": restored, "kept": kept}

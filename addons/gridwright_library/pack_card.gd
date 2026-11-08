@tool
extends PanelContainer
## One pack in the dock: cover, name, grid size, engines, and its buttons.
## A pack this account has bought gets Install; one it hasn't gets Buy (its page on gridwright.store)
## and, when the pack has one, Install sample.

signal install_requested(slug: String, kind: String)
signal buy_requested(slug: String)
signal show_requested(slug: String)

const COVER_RATIO := 500.0 / 630.0  # the store covers are 630x500

var pack: Dictionary = {}
var slug := ""
var search_text := ""
var owned := false
var _manifest := {}
var _margin := 6.0

var _cover: TextureRect
var _name: Label
var _meta: Label
var _state: Label
var _show: Button
var _install: Button
var _sample: Button


func setup(p: Dictionary, editor_scale: float) -> void:
	pack = p
	slug = str(p["slug"])
	var s := editor_scale
	_margin = 6 * s
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1, 1, 1, 0.045)
	box.set_corner_radius_all(int(4 * s))
	box.set_content_margin_all(_margin)
	add_theme_stylebox_override("panel", box)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(3 * s))
	add_child(col)

	var frame := PanelContainer.new()
	var dark := StyleBoxFlat.new()
	dark.bg_color = Color(0, 0, 0, 0.25)
	dark.set_corner_radius_all(int(3 * s))
	frame.add_theme_stylebox_override("panel", dark)
	col.add_child(frame)
	_cover = TextureRect.new()
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_cover)

	_name = Label.new()
	_name.text = str(p["name"])
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.max_lines_visible = 2
	_name.custom_minimum_size.x = 60 * s
	col.add_child(_name)

	_meta = Label.new()
	_meta.text = meta_line(p)
	_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_meta.custom_minimum_size.x = 60 * s
	_meta.modulate = Color(1, 1, 1, 0.62)
	col.add_child(_meta)

	var state_row := HBoxContainer.new()
	col.add_child(state_row)
	_state = Label.new()
	_state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_state.modulate = Color(0.55, 0.9, 0.6)
	state_row.add_child(_state)
	_show = Button.new()
	_show.text = "Show"
	_show.flat = true
	_show.tooltip_text = "Show the pack's folder in the FileSystem dock."
	_show.pressed.connect(func(): show_requested.emit(slug))
	state_row.add_child(_show)

	# Stacked, so the two buttons fit the narrowest card.
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", int(2 * s))
	col.add_child(buttons)
	_install = Button.new()
	_install.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_install.pressed.connect(_on_main_pressed)
	buttons.add_child(_install)
	_sample = Button.new()
	_sample.text = "Install sample"
	_sample.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sample.tooltip_text = "Download this pack's free sample into res://gridwright/. Any Gridwright account can."
	_sample.pressed.connect(func(): install_requested.emit(slug, "sample"))
	buttons.add_child(_sample)

	tooltip_text = str(p["name"])
	var words := PackedStringArray([str(p["name"]), slug, str(p.get("category", "")), str(p.get("grid", "") if p.get("grid") != null else "")])
	for e in p.get("engines", []):
		words.append(str(e))
	search_text = " ".join(words).to_lower()
	_refresh()


static func meta_line(p: Dictionary) -> String:
	var bits: Array[String] = []
	var grid = p.get("grid")
	if grid is String and grid != "":
		bits.append(grid)
	var engines: Array = p.get("engines", [])
	if not engines.is_empty():
		bits.append(", ".join(engines.slice(0, 3)) + ("…" if engines.size() > 3 else ""))
	var mb := float(p.get("sizeMB", 0.0))
	if mb > 0.0:
		bits.append(("%.1f MB" % mb) if mb < 100.0 else ("%d MB" % int(round(mb))))
	return " · ".join(bits)


func _on_main_pressed() -> void:
	if owned:
		install_requested.emit(slug, "full")
	else:
		buy_requested.emit(slug)


## m is the install manifest ({} when not installed).
func set_installed(m: Dictionary) -> void:
	_manifest = m
	_refresh()


## true when this account has bought the pack (or every pack opens for it).
func set_owned(on: bool) -> void:
	owned = on
	_refresh()


func main_text() -> String:
	return _install.text


func sample_shown() -> bool:
	return _sample.visible


func _refresh() -> void:
	var m := _manifest
	var kind := str(m.get("kind", "full"))
	var full_installed := not m.is_empty() and kind == "full" and bool(m.get("complete", true))
	if owned:
		_install.text = "Reinstall" if full_installed else "Install"
		_install.tooltip_text = "Download the full pack into res://gridwright/."
	else:
		_install.text = "Buy"
		_install.tooltip_text = "Buy this pack once on gridwright.store (opens its page). Then it installs here."
	# A bought pack has no need for its sample.
	_sample.visible = bool(pack.get("hasSample", false)) and not owned
	if m.is_empty():
		_state.text = ""
		_state.get_parent().visible = false
		return
	_state.get_parent().visible = true
	if not bool(m.get("complete", true)):
		_state.text = "Unfinished: install again"
		_state.modulate = Color(1, 0.8, 0.4)
		return
	_state.modulate = Color(0.55, 0.9, 0.6)
	_state.text = "Installed" if kind == "full" else "Sample installed"


func set_busy(busy: bool) -> void:
	_install.disabled = busy
	_sample.disabled = busy


func set_cover(tex: Texture2D) -> void:
	_cover.texture = tex


func set_width(w: float) -> void:
	custom_minimum_size.x = w
	var inner := w - 2.0 * _margin
	_cover.custom_minimum_size = Vector2(0, round(inner * COVER_RATIO))
	_name.custom_minimum_size.x = inner
	_meta.custom_minimum_size.x = inner

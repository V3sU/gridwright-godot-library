@tool
extends VBoxContainer
## The Gridwright dock: browse every Gridwright pack and install it into res://gridwright/.
## A free Gridwright account installs any pack's sample; a full pack installs once it is bought on gridwright.store.

signal catalog_finished(result: Dictionary)
signal install_finished(result: Dictionary)

const Api := preload("api.gd")
const Installer := preload("installer.gd")
const PixelPerfect := preload("pixel_perfect.gd")
const PackCard := preload("pack_card.gd")

const VERSION := "1.1"
const SETTING_KEY := "gridwright_library/key"
const SETTING_BASE := "gridwright_library/advanced/server"
const DEFAULT_BASE := "https://gridwright.store"
## Web pages always open on gridwright.store, whatever server the API calls go to.
const SITE := "https://gridwright.store"
const URL_KEY := "https://gridwright.store/account?ref=godot"
const URL_BROWSE := "https://gridwright.store/library?ref=godot"
const URL_BUNDLE := "https://itch.io/s/207198"
const URL_CUSTOM := "https://gridwright.store/custom?ref=godot"
const URL_DISCORD := "https://discord.gg/CmXcSgBQ6V"
## The strip at the top of the dock: [id, text, address].
const PROMO := [
	["bundle", "Every Gridwright pack: $20 bundle on itch.io", URL_BUNDLE],
	["custom", "Need art made for your game? Custom packs", URL_CUSTOM],
]
const CACHE_DIR := "user://gridwright_library"
const MIN_CARD := 132.0
const COVER_WORKERS := 4

const CATEGORY_ORDER := ["tilesets", "characters", "kits", "ui", "icons", "vfx", "backgrounds", "audio", "fonts", "3d", "tools", "templates"]
const CATEGORY_LABELS := {
	"tilesets": "Tilesets & worlds", "characters": "Characters & creatures", "kits": "Genre kits",
	"ui": "Game UI", "icons": "Icons", "vfx": "Effects", "backgrounds": "Backgrounds", "audio": "Music & sound",
	"fonts": "Pixel fonts", "3d": "3D & PSX", "tools": "Tools", "templates": "Templates",
}

## The Gridwright "G" with its corner brackets, 16x16 (Y gold, W white, P purple).
const ICON_ROWS := [
	"YY............YY",
	"Y..............Y",
	"................",
	".....WWWWWW.....",
	"....WWPPPPWW....",
	"....WP....PP....",
	"....WP..........",
	"....WP..WWWW....",
	"....WP..PPWW....",
	"....WP....WW....",
	"....WW....WW....",
	".....WWWWWWP....",
	"......PPPPP.....",
	"................",
	"Y..............Y",
	"YY............YY",
]
const ICON_COLORS := {"Y": Color8(255, 220, 90), "W": Color8(255, 255, 255), "P": Color8(110, 72, 210)}

var api: Node
var catalog: Array = []
var installed := {}
var me := {}
var busy := false
var imported := true
var last_notice := ""
var last_notice_buttons: Array[String] = []
## The last web page the dock opened (or would have opened: see open_url).
var last_opened_url := ""

var _cards := {}
var _account_res := {}
var _recheck_on_focus := false
var _catalog_running := false
var _started := false
var _scale := 1.0
var _installer = null
var _cover_queue: Array = []
var _cover_active := 0
var _confirm_action := Callable()


func _ready() -> void:
	if _is_edited_scene():
		return
	add_to_group("gridwright_library_dock")
	_scale = EditorInterface.get_editor_scale()
	api = Api.new()
	api.name = "Api"
	add_child(api)
	%Logo.texture = make_icon(int(16 * _scale))
	%Logo.custom_minimum_size = Vector2(16, 16) * _scale
	%Refresh.icon = get_theme_icon("Reload", "EditorIcons")
	%Search.right_icon = get_theme_icon("Search", "EditorIcons")
	%NoticeClose.icon = get_theme_icon("Close", "EditorIcons")
	%NoticeClose.text = ""
	%GetKey.uri = URL_KEY
	%Browse.uri = URL_BROWSE
	%Discord.uri = URL_DISCORD
	%Refresh.pressed.connect(func(): refresh_catalog())
	%CheckKey.pressed.connect(_on_check_pressed)
	%KeyEdit.text_submitted.connect(func(_t): _on_check_pressed())
	%KeyEdit.focus_exited.connect(func(): set_key(%KeyEdit.text))
	%Search.text_changed.connect(func(_t): _apply_filter())
	%Category.item_selected.connect(func(_i): _apply_filter())
	%NoticeClose.pressed.connect(func(): %Notice.visible = false)
	%Cancel.pressed.connect(cancel)
	%PixelButton.pressed.connect(_on_pixel_pressed)
	%UndoPixel.pressed.connect(_on_undo_pixel_pressed)
	%PixelDialog.confirmed.connect(_on_pixel_confirmed)
	%StretchCheck.toggled.connect(func(_on): _fill_pixel_dialog())
	%ConfirmDialog.confirmed.connect(_on_confirmed)
	%Scroll.resized.connect(_relayout)
	%Notice.visible = false
	%ProgressRow.visible = false
	_fill_promo()
	_fill_categories()


## The bundle first, custom packs second (the packs themselves are the dock's list).
func _fill_promo() -> void:
	var accent := _color("accent_color")
	var lines: Array[String] = []
	for p in PROMO:
		lines.append("[color=#%s][url=%s]%s[/url][/color]" % [accent.to_html(false), p[0], p[1]])
	%Promo.text = "\n".join(lines)
	if not %Promo.meta_clicked.is_connected(_on_promo_meta):
		%Promo.meta_clicked.connect(_on_promo_meta)
	%Promo.tooltip_text = "Opens in your browser."
	var strip := StyleBoxFlat.new()
	strip.bg_color = Color(accent, 0.1)
	strip.set_corner_radius_all(int(3 * _scale))
	strip.set_content_margin_all(5 * _scale)
	%PromoBox.add_theme_stylebox_override("panel", strip)


func _on_promo_meta(meta: Variant) -> void:
	for p in PROMO:
		if p[0] == str(meta):
			open_url(p[2])


func promo_links() -> Array:
	var out: Array = []
	for p in PROMO:
		out.append([p[1], p[2]])
	return out


## Opens a web page in the browser. GRIDWRIGHT_NO_BROWSER=1 (the addon's tests) only records it.
func open_url(url: String) -> void:
	last_opened_url = url
	if url.begins_with(SITE + "/library/"):
		# Back from buying a pack: look at the account again, so the card turns into Install.
		_recheck_on_focus = true
	if OS.get_environment("GRIDWRIGHT_NO_BROWSER") != "1":
		OS.shell_open(url)


static func pack_url(slug: String) -> String:
	return SITE + "/library/" + slug + "?ref=godot"


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and _recheck_on_focus and _started and not busy and get_key() != "":
		_recheck_on_focus = false
		check_key()


func _is_edited_scene() -> bool:
	if not is_inside_tree():
		return true
	var root := get_tree().edited_scene_root
	return root != null and (root == self or root.is_ancestor_of(self))


## Called by the plugin once the dock is in place.
func start() -> void:
	if _started or _is_edited_scene():
		return
	_started = true
	%KeyEdit.text = get_key()
	installed = Installer.find_installed()
	_load_cached_catalog()
	_update_pixel_buttons()
	_show_account({})
	refresh_catalog()
	if get_key() != "":
		check_key()


func shutdown() -> void:
	cancel()
	_cover_queue.clear()


# ---------------------------------------------------------------- settings

func _es() -> EditorSettings:
	return EditorInterface.get_editor_settings()


## The key lives in the editor's own settings (not in the project), so it never ends up in a commit.
func get_key() -> String:
	var es := _es()
	return str(es.get_setting(SETTING_KEY)).strip_edges() if es.has_setting(SETTING_KEY) else ""


func set_key(key: String) -> void:
	key = key.strip_edges()
	var es := _es()
	if not es.has_setting(SETTING_KEY):
		if key == "":
			return
		es.set_setting(SETTING_KEY, "")
		es.set_initial_value(SETTING_KEY, "", false)
		es.add_property_info({"name": SETTING_KEY, "type": TYPE_STRING, "hint": PROPERTY_HINT_PASSWORD})
	if str(es.get_setting(SETTING_KEY)) != key:
		es.set_setting(SETTING_KEY, key)
		me = {}
		_account_res = {}
		_update_owned()
	if is_inside_tree() and %KeyEdit.text != key:
		%KeyEdit.text = key


## gridwright.store, unless the GRIDWRIGHT_BASE_URL environment variable or the editor setting
## gridwright_library/advanced/server points somewhere else (used for testing).
func get_base_url() -> String:
	var url := OS.get_environment("GRIDWRIGHT_BASE_URL").strip_edges()
	var es := _es()
	if url == "" and es.has_setting(SETTING_BASE):
		url = str(es.get_setting(SETTING_BASE)).strip_edges()
	return url.trim_suffix("/") if url != "" else DEFAULT_BASE


# ---------------------------------------------------------------- account

func _on_check_pressed() -> void:
	set_key(%KeyEdit.text)
	check_key()


func check_key() -> Dictionary:
	api.base_url = get_base_url()
	if get_key() == "":
		me = {}
		_account_res = {}
		_update_owned()
		_show_account({})
		var r := {"ok": false, "code": 0, "error": "no_key"}
		_show_error(r)
		return r
	%Account.text = "Checking your key…"
	%Account.modulate = Color(1, 1, 1, 0.7)
	var res: Dictionary = await api.get_me(get_key())
	me = {}
	if res["ok"]:
		me = res["data"]
	_account_res = res
	_show_account(res)
	_update_owned()
	return res


## Every pack installs for this account (the shop's owner).
func every_pack() -> bool:
	return bool(me.get("pro", false))


## The account behind the key has bought this pack (known once the key is checked).
func owns(slug: String) -> bool:
	if every_pack():
		return true
	var bought: Variant = me.get("purchases")
	return bought is Array and bought.has(slug)


## Packs in the list this account has bought (tools and other items it bought aren't counted).
func bought_count() -> int:
	var bought: Variant = me.get("purchases")
	if not (bought is Array):
		return 0
	var n := 0
	for id in bought:
		var s := str(id)
		if catalog.is_empty():
			if not s.begins_with("tool-"):
				n += 1
		elif not _pack(s).is_empty():
			n += 1
	return n


func _update_owned() -> void:
	for s in _cards:
		_cards[s].set_owned(owns(s))
	if is_inside_tree() and %Category.selected >= 0 and str(%Category.get_selected_metadata()) == "@bought":
		_apply_filter()


func _show_account(res: Dictionary) -> void:
	var label: Label = %Account
	var link: LinkButton = %GetKey
	link.text = "Get your key"
	link.uri = URL_KEY
	label.modulate = Color(1, 1, 1, 0.7)
	if res.is_empty():
		label.text = "No key yet. It's on your Gridwright account page." if get_key() == "" else "Key saved. Press Check to see your packs."
		return
	if not res["ok"]:
		match res["error"]:
			"key":
				label.text = "This key doesn't work. Copy it again from your account page."
				label.modulate = _color("error_color")
			"no_key":
				label.text = "No key yet. It's on your Gridwright account page."
			_:
				label.text = "Couldn't check the key: " + describe(res)["text"]
				label.modulate = _color("warning_color")
		return
	var email := str(me.get("email", ""))
	link.text = "Your account"
	label.modulate = _color("success_color")
	if every_pack():
		label.text = "Owner · every pack · " + email
		return
	var n := bought_count()
	label.text = "%s · %d pack%s bought" % [email, n, "" if n == 1 else "s"]
	if n == 0:
		label.text += ". Samples install now."
		label.modulate = Color(1, 1, 1, 0.8)


# ---------------------------------------------------------------- catalog

func refresh_catalog() -> Dictionary:
	if _catalog_running:
		return await catalog_finished
	_catalog_running = true
	api.base_url = get_base_url()
	%Count.text = "Loading the pack list…"
	var res: Dictionary = await api.get_catalog()
	if res["ok"] and res["data"].get("packs") is Array:
		catalog = clean_packs(res["data"]["packs"])
		_save_cached_catalog(res["data"])
		_build_cards()
	elif catalog.is_empty():
		%Count.text = ""
		_show_error(res)
	else:
		%Count.text = "Offline: showing the list saved earlier."
		_show_error(res)
	_catalog_running = false
	catalog_finished.emit(res)
	return res


## Keeps only well-formed entries, so a bad record can't break the dock or reach the file system.
static func clean_packs(raw: Array) -> Array:
	var out: Array = []
	for p in raw:
		if not (p is Dictionary):
			continue
		var slug := str(p.get("slug", ""))
		var pack_name := str(p.get("name", "")).strip_edges()
		if not Installer.is_safe_slug(slug) or pack_name == "":
			continue
		var engines: Array = []
		if p.get("engines") is Array:
			for e in p["engines"]:
				engines.append(str(e))
		var grid: Variant = null
		if p.get("grid") != null and str(p["grid"]) != "":
			grid = str(p["grid"])
		out.append({
			"slug": slug, "name": pack_name, "category": str(p.get("category", "")),
			"cover": str(p.get("cover", "")) if p.get("cover") is String else "",
			"grid": grid,
			"engines": engines, "sizeMB": float(p.get("sizeMB", 0.0)) if p.get("sizeMB") != null else 0.0,
			"hasSample": bool(p.get("hasSample", false)),
		})
	return out


func _cache_path() -> String:
	return CACHE_DIR + "/catalog.json"


func _save_cached_catalog(data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var f := FileAccess.open(_cache_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"saved": Time.get_datetime_string_from_system(), "base": get_base_url(), "data": data}))
		f.close()


func _load_cached_catalog() -> void:
	if not FileAccess.file_exists(_cache_path()):
		return
	var c = JSON.parse_string(FileAccess.get_file_as_string(_cache_path()))
	if c is Dictionary and c.get("base") == get_base_url() and c.get("data") is Dictionary and c["data"].get("packs") is Array:
		catalog = clean_packs(c["data"]["packs"])
		_build_cards()


func _pack(slug: String) -> Dictionary:
	for p in catalog:
		if p["slug"] == slug:
			return p
	return {}


func _fill_categories() -> void:
	var opt: OptionButton = %Category
	var keep := ""
	if opt.selected >= 0:
		keep = str(opt.get_selected_metadata())
	opt.clear()
	opt.add_item("All packs")
	opt.set_item_metadata(0, "")
	var present := {}
	for p in catalog:
		present[p["category"]] = true
	var cats: Array = []
	for c in CATEGORY_ORDER:
		if present.has(c):
			cats.append(c)
	for c in present.keys():
		if c != "" and not cats.has(c):
			cats.append(c)
	for c in cats:
		opt.add_item(CATEGORY_LABELS.get(c, str(c).capitalize()))
		opt.set_item_metadata(opt.item_count - 1, c)
	opt.add_item("Installed")
	opt.set_item_metadata(opt.item_count - 1, "@installed")
	opt.add_item("Bought")
	opt.set_item_metadata(opt.item_count - 1, "@bought")
	opt.select(0)
	for i in opt.item_count:
		if opt.get_item_metadata(i) == keep:
			opt.select(i)


func _build_cards() -> void:
	for c in %Grid.get_children():
		c.queue_free()
	_cards.clear()
	_cover_queue.clear()
	for p in catalog:
		var card := PackCard.new()
		card.setup(p, _scale)
		card.install_requested.connect(_on_install_requested)
		card.buy_requested.connect(_on_buy_requested)
		card.show_requested.connect(_on_show_requested)
		%Grid.add_child(card)
		_cards[p["slug"]] = card
		if installed.has(p["slug"]):
			card.set_installed(installed[p["slug"]])
		card.set_owned(owns(p["slug"]))
		card.set_busy(busy)
		if p["cover"] != "":
			_cover_queue.append([p["slug"], p["cover"]])
	_fill_categories()
	_apply_filter()
	if not _account_res.is_empty():
		_show_account(_account_res)  # the bought count follows the list
	_relayout()
	_pump_covers()


## Shows the cards that match the search words and the category.
func _apply_filter() -> void:
	var words: PackedStringArray = %Search.text.to_lower().split(" ", false)
	var cat := str(%Category.get_selected_metadata()) if %Category.selected >= 0 else ""
	var shown := 0
	for slug in _cards:
		var card = _cards[slug]
		var ok := true
		if cat == "@installed":
			ok = installed.has(slug)
		elif cat == "@bought":
			ok = owns(slug)
		elif cat != "":
			ok = card.pack["category"] == cat
		if ok:
			for w in words:
				if not card.search_text.contains(w):
					ok = false
					break
		card.visible = ok
		if ok:
			shown += 1
	if catalog.is_empty():
		%Count.text = ""
	elif shown == catalog.size():
		%Count.text = "%d packs" % shown
	else:
		%Count.text = "%d of %d packs" % [shown, catalog.size()]


func set_filter(text: String, category := "") -> int:
	%Search.text = text
	for i in %Category.item_count:
		if %Category.get_item_metadata(i) == category:
			%Category.select(i)
	_apply_filter()
	return visible_card_count()


func visible_card_count() -> int:
	var n := 0
	for slug in _cards:
		if _cards[slug].visible:
			n += 1
	return n


func card_count() -> int:
	return _cards.size()


func _relayout() -> void:
	var scroll: ScrollContainer = %Scroll
	var w := scroll.size.x - scroll.get_v_scroll_bar().get_combined_minimum_size().x - 4.0 * _scale
	if w < 60.0:
		return
	var gap := 6.0 * _scale
	var cols := maxi(1, int((w + gap) / (MIN_CARD * _scale + gap)))
	var grid: GridContainer = %Grid
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", int(gap))
	grid.add_theme_constant_override("v_separation", int(gap))
	var card_w := floorf((w - gap * (cols - 1)) / cols)
	for c in grid.get_children():
		if c.has_method("set_width"):
			c.set_width(card_w)


# ---------------------------------------------------------------- covers

func _pump_covers() -> void:
	while _cover_active < COVER_WORKERS and not _cover_queue.is_empty():
		var item: Array = _cover_queue.pop_front()
		_cover_active += 1
		_load_cover(item[0], item[1])


func _load_cover(slug: String, url: String) -> void:
	var path := CACHE_DIR + "/covers/" + url.md5_text() + ".img"
	var bytes := PackedByteArray()
	if FileAccess.file_exists(path):
		bytes = FileAccess.get_file_as_bytes(path)
	else:
		var res: Dictionary = await api.fetch(url)
		if not is_inside_tree():
			return
		if res["ok"]:
			bytes = res["body"]
			DirAccess.make_dir_recursive_absolute(CACHE_DIR + "/covers")
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f:
				f.store_buffer(bytes)
				f.close()
	var img := image_from_bytes(bytes)
	if img and _cards.has(slug):
		var target := int(MIN_CARD * 1.6 * _scale)
		if img.get_width() > target:
			img.resize(target, int(round(img.get_height() * float(target) / img.get_width())), Image.INTERPOLATE_LANCZOS)
		_cards[slug].set_cover(ImageTexture.create_from_image(img))
	_cover_active -= 1
	_pump_covers()


func covers_pending() -> int:
	return _cover_queue.size() + _cover_active


static func image_from_bytes(b: PackedByteArray) -> Image:
	if b.size() < 12:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if b[0] == 0x89 and b[1] == 0x50 and b[2] == 0x4E and b[3] == 0x47:
		err = img.load_png_from_buffer(b)
	elif b[0] == 0xFF and b[1] == 0xD8:
		err = img.load_jpg_from_buffer(b)
	elif b.slice(0, 4).get_string_from_ascii() == "RIFF" and b.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = img.load_webp_from_buffer(b)
	return img if err == OK else null


# ---------------------------------------------------------------- install

func _on_install_requested(slug: String, kind: String) -> void:
	if busy:
		return
	var p := _pack(slug)
	if installed.has(slug):
		var m: Dictionary = installed[slug]
		var what := "the full pack" if kind == "full" else "the sample"
		_ask("Install %s again?" % p.get("name", slug),
			"This puts %s into %s/ again. Files that came with the pack are replaced; anything else in that folder stays." % [what, m["folder"]],
			func(): install(slug, kind))
		return
	install(slug, kind)


## Buy opens the pack's page on gridwright.store. Back in the editor, the dock checks the account again.
func _on_buy_requested(slug: String) -> void:
	var p := _pack(slug)
	open_url(pack_url(slug))
	var buttons: Array = [["Check again", func(): check_key()]]
	if bool(p.get("hasSample", false)):
		buttons.append(["Install sample", func(): _on_install_requested(slug, "sample")])
	_notice("%s opened on gridwright.store. Once it's bought, it installs here with one click." % p.get("name", slug),
		"success_color", buttons)


## Downloads the pack through the account key and unpacks it into res://gridwright/<folder>/.
func install(slug: String, kind: String) -> Dictionary:
	if busy:
		return {"ok": false, "error": "busy"}
	var p := _pack(slug)
	if p.is_empty() or not Installer.is_safe_slug(slug) or not (kind in ["full", "sample"]):
		return _finish_install({"ok": false, "error": "not_found"})
	if get_key() == "":
		return _finish_install({"ok": false, "error": "no_key"})
	_set_busy(true)
	%Notice.visible = false
	var label := "%s%s" % [p["name"], " (sample)" if kind == "sample" else ""]
	_progress("Getting %s…" % label, -1.0)
	api.base_url = get_base_url()
	var res: Dictionary = await api.request_download(get_key(), slug, kind)
	if not res["ok"]:
		if res["error"] == "key":
			_show_account(res)
		res["slug"] = slug
		return _finish_install(res)
	var d: Dictionary = res["data"]
	var url := str(d.get("url", ""))
	var expected := int(d.get("bytes", 0))
	DirAccess.make_dir_recursive_absolute(CACHE_DIR + "/downloads")
	var zip_path := CACHE_DIR + "/downloads/%s-%s.zip" % [slug, kind]
	var on_bytes := func(got: int, total: int) -> void:
		var t := "Downloading %s: %s" % [label, _mb(got)]
		if total > 0:
			t += " of " + _mb(total)
		_progress(t, float(got) / total if total > 0 else -1.0)
	var dl: Dictionary = await api.download(url, zip_path, expected, on_bytes)
	if not dl["ok"] and dl["error"] == "expired":
		# The signed link ran out before the download began (say the editor was busy importing):
		# ask for a fresh one, once.
		res = await api.request_download(get_key(), slug, kind)
		if not res["ok"]:
			res["slug"] = slug
			return _finish_install(res)
		d = res["data"]
		expected = int(d.get("bytes", 0))
		dl = await api.download(str(d.get("url", "")), zip_path, expected, on_bytes)
	if not dl["ok"]:
		return _finish_install(dl)
	var dest := Installer.target_folder(slug, p["name"], installed)
	# The record goes in first, so an unpack that stops halfway is found and finished in the same folder.
	var record := {"slug": slug, "name": p["name"], "kind": kind, "file": str(d.get("fileName", "")),
		"complete": false, "addon": VERSION}
	DirAccess.make_dir_recursive_absolute(dest)
	Installer.write_manifest(dest, record)
	var inst = Installer.new()
	_installer = inst
	inst.progress = func(done: int, total: int) -> void:
		_progress("Unpacking %s: %d of %d files" % [label, done, total], float(done) / maxi(total, 1))
	var r: Dictionary = await inst.extract(zip_path, dest, get_tree())
	_installer = null
	DirAccess.remove_absolute(zip_path)
	if r["ok"]:
		record["complete"] = true
		record["files"] = r["files"]
		record["installed"] = Time.get_datetime_string_from_system()
		Installer.write_manifest(dest, record)
	installed = Installer.find_installed()
	for s in _cards:
		_cards[s].set_installed(installed.get(s, {}))
	_scan()
	if not r["ok"]:
		return _finish_install(r)
	if kind == "full" and not owns(slug) and not me.is_empty():
		# The server found a purchase newer than the last check: show it as bought.
		var bought: Variant = me.get("purchases")
		var list: Array = bought if bought is Array else []
		list.append(slug)
		me["purchases"] = list
		_update_owned()
		_show_account(_account_res)
	r["slug"] = slug
	r["kind"] = kind
	r["name"] = p["name"]
	return _finish_install(r)


func _finish_install(r: Dictionary) -> Dictionary:
	_set_busy(false)
	%ProgressRow.visible = false
	if r["ok"]:
		var dest: String = r["dest"]
		var text := "Installed %s%s: %d files in %s/." % [r["name"], " (sample)" if r["kind"] == "sample" else "", r["files"], dest]
		if r["readme"] != "":
			text += " Start with " + r["readme"] + "."
		if not r["roots"].is_empty():
			text += " Its Godot demo now points at this folder."
		var show_path := dest
		if r["readme"] != "":
			show_path = r["readme"]
		var buttons: Array = [["Show in FileSystem", func(): _reveal(show_path)]]
		if r["readme"] != "":
			buttons.append(["Open README", func(): OS.shell_open(ProjectSettings.globalize_path(r["readme"]))])
		if r["demo_scene"] != "":
			buttons.append(["Open demo scene", func(): _open_demo(r["demo_scene"])])
		_notice(text, "success_color", buttons)
	elif r.get("error") != "busy":
		_show_error(r)
	install_finished.emit(r)
	return r


func cancel() -> void:
	if api and api.is_downloading():
		api.cancel_download()
	if _installer != null:
		_installer.cancelled = true


func _set_busy(on: bool) -> void:
	busy = on
	for s in _cards:
		_cards[s].set_busy(on)
	%PixelButton.disabled = on


func _progress(text: String, ratio: float) -> void:
	%ProgressRow.visible = true
	%ProgressLabel.text = text
	%Progress.indeterminate = ratio < 0.0
	if ratio >= 0.0:
		%Progress.value = ratio * 100.0


static func _mb(b: int) -> String:
	return "%.1f MB" % (b / 1048576.0)


## Lets Godot find and import the new files. `imported` turns true once the FileSystem has
## caught up (the import runs before filesystem_changed is sent).
func _scan() -> void:
	imported = false
	var fs := EditorInterface.get_resource_filesystem()
	if not fs.filesystem_changed.is_connected(_on_fs_changed):
		fs.filesystem_changed.connect(_on_fs_changed, CONNECT_ONE_SHOT)
	fs.scan()


func _on_fs_changed() -> void:
	imported = true


## Waits until the new files are imported (at most two minutes of running time: the editor itself
## stands still while it imports).
func wait_imported() -> void:
	var fs := EditorInterface.get_resource_filesystem()
	var waited := 0.0
	while (not imported or fs.is_scanning()) and waited < 120.0:
		var t := Time.get_ticks_msec()
		await get_tree().process_frame
		waited += minf((Time.get_ticks_msec() - t) / 1000.0, 0.25)


func _on_show_requested(slug: String) -> void:
	if installed.has(slug):
		var m: Dictionary = installed[slug]
		_reveal(str(m["folder"]))


func _reveal(path: String) -> void:
	await wait_imported()
	EditorInterface.get_file_system_dock().navigate_to_path(path)


func _open_demo(path: String) -> void:
	await wait_imported()
	EditorInterface.open_scene_from_path(path)


# ---------------------------------------------------------------- messages

## Turns an error from the API or the installer into one short line and the buttons that help.
func describe(r: Dictionary) -> Dictionary:
	var host: String = api.host() if api else "gridwright.store"
	var e := str(r.get("error", "server"))
	match e:
		"no_key":
			return {"text": "Paste your Gridwright key first. It's on your account page.", "buttons": [["Get your key", URL_KEY]]}
		"key":
			return {"text": "This key doesn't work. Copy it again from your account page.", "buttons": [["Get your key", URL_KEY]]}
		"buy":
			var slug := str(r.get("slug", ""))
			var text := "Not bought yet. Buy this pack on gridwright.store, and it installs here."
			if bool(_pack(slug).get("hasSample", false)):
				text += " Its sample installs now."
			return {"text": text, "buttons": [["Open the pack page", pack_url(slug) if Installer.is_safe_slug(slug) else URL_BROWSE]]}
		"limit":
			return {"text": "You've reached today's download limit. Try again tomorrow.", "buttons": []}
		"not_found":
			return {"text": "This pack isn't available right now. Reload the list and try again.", "buttons": []}
		"net":
			return {"text": "Can't reach %s. Check your internet connection." % host, "buttons": []}
		"timeout":
			return {"text": "No answer from %s. Check your internet connection and try again." % host, "buttons": []}
		"tls":
			return {"text": "Couldn't make a secure connection to %s. Check your system clock, then try again." % host, "buttons": []}
		"insecure":
			return {"text": "The server address has to start with https://.", "buttons": []}
		"expired":
			return {"text": "The download link ran out. Press Install again.", "buttons": []}
		"stalled":
			return {"text": "The download stopped moving. Try again.", "buttons": []}
		"incomplete":
			return {"text": "The download was incomplete. Try again.", "buttons": []}
		"cancelled":
			return {"text": "Cancelled.", "buttons": []}
		"bad_zip", "empty_zip":
			return {"text": "The downloaded file isn't a working zip. Try again; if it keeps happening, tell us on Discord.", "buttons": [["Discord", URL_DISCORD]]}
		"write":
			return {"text": "Couldn't write a file: %s" % r.get("detail", ""), "buttons": []}
		"forbidden":
			return {"text": "gridwright.store refused this download.", "buttons": []}
	return {"text": "%s had a problem%s. Try again in a minute." % [host, (" (%d)" % r["code"]) if int(r.get("code", 0)) > 0 else ""], "buttons": []}


func _show_error(r: Dictionary) -> void:
	var d := describe(r)
	var buttons: Array = []
	for b in d["buttons"]:
		var url: String = b[1]
		buttons.append([b[0], func(): open_url(url)])
	_notice(d["text"], "warning_color" if r.get("error") in ["cancelled", "limit", "buy"] else "error_color", buttons)


func _notice(text: String, color: String, buttons: Array = []) -> void:
	last_notice = text
	last_notice_buttons.clear()
	%NoticeText.text = text
	%NoticeText.modulate = _color(color)
	for c in %NoticeButtons.get_children():
		c.queue_free()
	for b in buttons:
		var btn := Button.new()
		btn.text = b[0]
		btn.pressed.connect(b[1])
		%NoticeButtons.add_child(btn)
		last_notice_buttons.append(b[0])
	%NoticeButtons.visible = not buttons.is_empty()
	%Notice.visible = true


func _color(color_name: String) -> Color:
	if has_theme_color(color_name, "Editor"):
		return get_theme_color(color_name, "Editor")
	return {"error_color": Color(1, 0.47, 0.42), "success_color": Color(0.45, 0.9, 0.55), "warning_color": Color(1, 0.8, 0.4),
		"accent_color": Color(0.44, 0.73, 0.98)}.get(color_name, Color.WHITE)


func _on_confirmed() -> void:
	if _confirm_action.is_valid():
		_confirm_action.call()


func _ask(title: String, text: String, action: Callable) -> void:
	_confirm_action = action
	%ConfirmDialog.title = title
	%ConfirmDialog.dialog_text = text
	%ConfirmDialog.popup_centered(Vector2i(int(420 * _scale), 0))


# ---------------------------------------------------------------- pixel-perfect

func _update_pixel_buttons() -> void:
	%UndoPixel.disabled = not PixelPerfect.can_undo()


func _on_pixel_pressed() -> void:
	if PixelPerfect.pending("base").is_empty() and PixelPerfect.pending("stretch").is_empty():
		_notice("This project already uses pixel-perfect settings.", "success_color")
		return
	%StretchCheck.button_pressed = false
	%StretchCheck.disabled = PixelPerfect.pending("stretch").is_empty()
	_fill_pixel_dialog()
	%PixelDialog.popup_centered(Vector2i(int(460 * _scale), 0))


func _fill_pixel_dialog() -> void:
	var rows := PixelPerfect.pending("base")
	var lines: Array[String] = []
	if rows.is_empty():
		lines.append("Filtering and snapping are already set.")
	else:
		lines.append("These project settings change:")
		for r in rows:
			lines.append("• %s. %s" % [r["label"], r["why"]])
	%PixelText.text = "\n".join(lines)
	var st := PixelPerfect.pending("stretch")
	var base := PixelPerfect.base_size()
	var more: Array[String] = []
	for r in st:
		more.append("• %s. %s" % [r["label"], r["why"]])
	if st.is_empty():
		more.append("Stretch is already set to viewport with integer scaling.")
	else:
		more.append("Your base size is %dx%d. For pixel art, set it to your game's own size, such as 320x180 or 640x360 (Project Settings > Display > Window)." % [base.x, base.y])
	%StretchText.text = "\n".join(more)
	%StretchText.modulate = Color(1, 1, 1, 1.0 if %StretchCheck.button_pressed else 0.55)
	%PixelDialog.get_ok_button().disabled = rows.is_empty() and not %StretchCheck.button_pressed


func _on_pixel_confirmed() -> void:
	apply_pixel_perfect(%StretchCheck.button_pressed)


func apply_pixel_perfect(include_stretch: bool) -> Dictionary:
	var r := PixelPerfect.apply(include_stretch)
	_update_pixel_buttons()
	if r["changed"].is_empty():
		_notice("Nothing to change: this project already uses these settings.", "success_color")
	else:
		_notice("Pixel-perfect: %s. Undo puts the old values back." % ", ".join(r["changed"]), "success_color")
	return r


func _on_undo_pixel_pressed() -> void:
	undo_pixel_perfect()


func undo_pixel_perfect() -> Dictionary:
	var r := PixelPerfect.undo()
	_update_pixel_buttons()
	var text := "Put back %d setting%s from before." % [r["restored"].size(), "" if r["restored"].size() == 1 else "s"]
	if not r["kept"].is_empty():
		text += " Left %d you changed yourself since then." % r["kept"].size()
	_notice(text, "success_color")
	return r


# ---------------------------------------------------------------- icon

static func make_icon(px: int) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 16:
		var row: String = ICON_ROWS[y]
		for x in 16:
			var c := row[x]
			if ICON_COLORS.has(c):
				img.set_pixel(x, y, ICON_COLORS[c])
	var side := maxi(16, px - px % 16)
	if side != 16:
		img.resize(side, side, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)

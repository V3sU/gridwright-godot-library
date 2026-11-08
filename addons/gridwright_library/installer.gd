@tool
extends RefCounted
## Unpacks a Gridwright pack zip into res://gridwright/<folder>/.
##
## - The zip's single top folder ("Gridwright Pixel UI Kit/") is dropped; the folders inside it are kept.
## - .import and .uid files, .godot/ caches and OS junk are skipped.
## - Entries that would land outside the pack folder (../, absolute paths, drive letters) are refused.
## - A pack's own Godot demo project (a folder with project.godot) is made usable inside your project:
##   its project.godot is saved as project.godot.txt, and the res:// paths in its .tscn, .tres, .gd and
##   shader files are pointed at the new folder.

const ROOT := "res://gridwright"
const MANIFEST := ".gridwright-install"
const SKIP_EXTENSIONS := ["import", "uid"]
const SKIP_FILES := [".ds_store", "thumbs.db", "desktop.ini"]
const SKIP_DIRS := [".godot", ".import", "__macosx", ".git", ".svn"]
const REWRITE_EXTENSIONS := ["tres", "tscn", "gd", "gdshader", "gdshaderinc"]
const FRAME_BUDGET_MS := 12

## Called as progress.call(done, total) while files are written.
var progress := Callable()
var cancelled := false


## A short, readable folder name from the pack name ("Isometric Shops & Cafe Interiors" ->
## "isometric-shops-and-cafe-interiors"). The site slugs are long SEO slugs, too long for a project tree.
static func folder_name(pack_name: String, slug: String) -> String:
	var s := pack_name.strip_edges().to_lower().replace("&", " and ")
	if s.begins_with("gridwright "):
		s = s.substr(11)
	var out := ""
	var dash := false
	for i in s.length():
		var c := s.unicode_at(i)
		var ok := (c >= 97 and c <= 122) or (c >= 48 and c <= 57)
		if ok:
			out += char(c)
			dash = false
		elif not dash and out != "":
			out += "-"
			dash = true
	out = out.trim_suffix("-")
	if out.length() > 48:
		out = out.substr(0, 48).trim_suffix("-")
	if out == "":
		out = slug.substr(0, 48)
	return out


static func is_safe_slug(slug: String) -> bool:
	if slug.length() < 1 or slug.length() > 120:
		return false
	for i in slug.length():
		var c := slug.unicode_at(i)
		var ok := (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 45 or c == 95
		if not ok:
			return false
	return true


## Works out what to write, without touching the disk. Returns:
## { entries: [{zip, rel, out, root}], skipped: [names], unsafe: [names], roots: [rel dirs] }
## where `root` is the demo-project folder whose res:// paths the file needs rewritten, or null.
static func plan(files: PackedStringArray) -> Dictionary:
	var names: Array[String] = []
	for f in files:
		if not f.ends_with("/"):
			names.append(f)
	# Drop one shared top folder.
	var prefix := ""
	if not names.is_empty():
		var first := names[0].replace("\\", "/")
		var slash := first.find("/")
		if slash > 0:
			var top := first.substr(0, slash + 1)
			var shared := true
			for n in names:
				if not n.replace("\\", "/").begins_with(top):
					shared = false
					break
			if shared:
				prefix = top
	var entries: Array = []
	var skipped: Array = []
	var unsafe: Array = []
	var roots: Array = []
	for n in names:
		var rel := n.replace("\\", "/").substr(prefix.length())
		if not _safe_rel(rel):
			unsafe.append(n)
			continue
		var segs := rel.split("/")
		var skip := false
		for i in segs.size() - 1:
			if SKIP_DIRS.has(segs[i].to_lower()):
				skip = true
				break
		var file := rel.get_file()
		if skip or SKIP_FILES.has(file.to_lower()) or SKIP_EXTENSIONS.has(rel.get_extension().to_lower()):
			skipped.append(n)
			continue
		var out := rel
		if file == "project.godot":
			roots.append(rel.get_base_dir())
			out = rel + ".txt"
		entries.append({"zip": n, "rel": rel, "out": out, "root": null})
	# Files inside a demo project get their res:// paths pointed at the new place.
	for e in entries:
		var rel: String = e["rel"]
		var ext := rel.get_extension().to_lower()
		if not (REWRITE_EXTENSIONS.has(ext) or rel.get_file() == "project.godot"):
			continue
		var best = null
		for r in roots:
			var root: String = r
			if root == "" or rel.begins_with(root + "/"):
				if best == null or root.length() > str(best).length():
					best = root
		e["root"] = best
	return {"entries": entries, "skipped": skipped, "unsafe": unsafe, "roots": roots}


static func _safe_rel(rel: String) -> bool:
	if rel == "" or rel.begins_with("/") or rel.contains(":"):
		return false
	for seg in rel.split("/"):
		if seg == "" or seg == "." or seg == "..":
			return false
	return true


## Points every res:// path in a demo-project file at `new_root` ("res://gridwright/<folder>/Godot/").
## Paths that already start there are left alone, so running it twice changes nothing.
static func rewrite_paths(text: String, new_root: String) -> String:
	var parts := text.split("res://")
	if parts.size() == 1:
		return text
	var already := new_root.trim_prefix("res://")
	var out := parts[0]
	for i in range(1, parts.size()):
		var rest: String = parts[i]
		out += ("res://" + rest) if rest.begins_with(already) else (new_root + rest)
	return out


## Unpacks `zip_path` into `dest` (a folder under res://gridwright/). Yields to the editor between
## batches so it stays responsive. Returns { ok, error?, dest, files, skipped, unsafe, readme, demo_scene }.
func extract(zip_path: String, dest: String, tree: SceneTree) -> Dictionary:
	if not dest.begins_with(ROOT + "/") or dest.contains(".."):
		return {"ok": false, "error": "bad_dest"}
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return {"ok": false, "error": "bad_zip"}
	var p := plan(reader.get_files())
	var entries: Array = p["entries"]
	if entries.is_empty():
		reader.close()
		return {"ok": false, "error": "empty_zip"}
	var made := {}
	var written := 0
	var readme := ""
	var readme_depth := 1 << 20
	var demo_scene := ""
	var t0 := Time.get_ticks_msec()
	for i in entries.size():
		if cancelled:
			reader.close()
			return {"ok": false, "error": "cancelled", "dest": dest, "files": written}
		var e: Dictionary = entries[i]
		var out_rel: String = e["out"]
		var path := (dest + "/" + out_rel).simplify_path()
		if not path.begins_with(dest + "/"):
			p["unsafe"].append(e["zip"])
			continue
		var dir := path.get_base_dir()
		if not made.has(dir):
			DirAccess.make_dir_recursive_absolute(dir)
			made[dir] = true
		var data := reader.read_file(e["zip"])
		if e["root"] != null:
			var root: String = e["root"]
			var new_root := dest + "/" + (root + "/" if root != "" else "")
			var text := rewrite_paths(data.get_string_from_utf8(), new_root)
			data = text.to_utf8_buffer()
			if out_rel.get_file() == "project.godot.txt":
				var scene := _main_scene(text)
				if scene != "" and demo_scene == "":
					demo_scene = scene
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			reader.close()
			return {"ok": false, "error": "write", "detail": path + ": " + error_string(FileAccess.get_open_error()), "dest": dest, "files": written}
		f.store_buffer(data)
		f.close()
		written += 1
		var low := out_rel.get_file().to_lower()
		if (low.begins_with("readme") or low.begins_with("read me") or low.begins_with("read_me")) and ["txt", "md", "pdf", "html"].has(low.get_extension()):
			var depth := out_rel.count("/")
			if depth < readme_depth or (depth == readme_depth and low.get_extension() == "txt"):
				readme = path
				readme_depth = depth
		if Time.get_ticks_msec() - t0 > FRAME_BUDGET_MS:
			if progress.is_valid():
				progress.call(i + 1, entries.size())
			await tree.process_frame
			t0 = Time.get_ticks_msec()
	reader.close()
	if progress.is_valid():
		progress.call(entries.size(), entries.size())
	if demo_scene != "" and not FileAccess.file_exists(demo_scene):
		demo_scene = ""
	return {"ok": true, "dest": dest, "files": written, "skipped": p["skipped"].size(),
		"unsafe": p["unsafe"], "readme": readme, "demo_scene": demo_scene, "roots": p["roots"]}


static func _main_scene(project_text: String) -> String:
	for line in project_text.split("\n"):
		var l := line.strip_edges()
		if l.begins_with("run/main_scene="):
			var v := l.substr(15).strip_edges().trim_prefix("\"").trim_suffix("\"")
			return v if v.begins_with("res://") else ""
	return ""


static func write_manifest(dest: String, info: Dictionary) -> void:
	var f := FileAccess.open(dest + "/" + MANIFEST, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(info, "\t"))
		f.close()


static func read_manifest(dir: String) -> Dictionary:
	var path := dir + "/" + MANIFEST
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


## Every pack installed by this addon: slug -> manifest (with "folder" set to its res:// path).
static func find_installed() -> Dictionary:
	var out := {}
	if not DirAccess.dir_exists_absolute(ROOT):
		return out
	for d in DirAccess.get_directories_at(ROOT):
		var dir := ROOT + "/" + d
		var m := read_manifest(dir)
		if m.has("slug"):
			m["folder"] = dir
			out[str(m["slug"])] = m
	return out


## Where a pack goes: its existing install, or a new folder that no other pack or file is using.
static func target_folder(slug: String, pack_name: String, installed: Dictionary) -> String:
	if installed.has(slug):
		return str(installed[slug]["folder"])
	var base := ROOT + "/" + folder_name(pack_name, slug)
	var dir := base
	var n := 2
	while DirAccess.dir_exists_absolute(dir):
		var m := read_manifest(dir)
		if m.get("slug", "") == slug:
			break
		dir = base + "-" + str(n)
		n += 1
	return dir

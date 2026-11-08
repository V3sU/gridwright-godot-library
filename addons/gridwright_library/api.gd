@tool
extends Node
## Talks to gridwright.store: the pack catalog, the account behind a key, and download links.
## Every call returns a Dictionary: { ok: bool, code: int, data, error: String }.
## error is one of: no_key, key, buy, forbidden, not_found, limit, net, timeout, tls, server,
## bad_response, cancelled, stalled, incomplete, expired, insecure.
## "buy" is the server's 403 for a full pack this account hasn't bought (it answers {"error": "pro", "reason": "buy"}).
##
## Timeouts count only time the editor is actually running. Godot blocks the editor while it imports
## new files (minutes for a big pack), and HTTPRequest's own timer would then fire the moment the editor
## comes back, before the request had a chance. So HTTPRequest.timeout stays 0 and each frame adds at
## most a quarter second here.

const VERSION := "1.1"
const USER_AGENT := "GridwrightLibrary/" + VERSION + " (Godot)"
const JSON_TIMEOUT := 30.0
const COVER_TIMEOUT := 20.0
const STALL_TIMEOUT := 60.0
const MAX_STEP := 0.25

var base_url := "https://gridwright.store"
var _download := {}


func host() -> String:
	return base_url.trim_prefix("https://").trim_prefix("http://").get_slice("/", 0)


## The key only ever travels over HTTPS (plain HTTP is allowed for a local test server).
func is_secure() -> bool:
	if base_url.begins_with("https://"):
		return true
	var h := host().get_slice(":", 0)
	return base_url.begins_with("http://") and (h == "127.0.0.1" or h == "localhost")


func get_catalog() -> Dictionary:
	return await _json(HTTPClient.METHOD_GET, "/api/public/plugin/catalog", "", null)


func get_me(key: String) -> Dictionary:
	if key.strip_edges() == "":
		return {"ok": false, "code": 0, "error": "no_key"}
	return await _json(HTTPClient.METHOD_GET, "/api/public/plugin/me", key, null)


func request_download(key: String, slug: String, kind: String) -> Dictionary:
	if key.strip_edges() == "":
		return {"ok": false, "code": 0, "error": "no_key"}
	return await _json(HTTPClient.METHOD_POST, "/api/public/plugin/download", key, {"slug": slug, "kind": kind})


func _new_request() -> HTTPRequest:
	var http := HTTPRequest.new()
	http.timeout = 0.0
	http.use_threads = false
	add_child(http)
	return http


## Waits for st["done"], counting running time only. Returns false on timeout (the request is cancelled).
func _wait(http: HTTPRequest, st: Dictionary, limit: float) -> bool:
	var waited := 0.0
	while not st["done"]:
		var t := Time.get_ticks_msec()
		await get_tree().process_frame
		waited += minf((Time.get_ticks_msec() - t) / 1000.0, MAX_STEP)
		if waited > limit and not st["done"]:
			http.cancel_request()
			return false
	return true


func _json(method: int, path: String, key: String, body) -> Dictionary:
	if not is_secure():
		return {"ok": false, "code": 0, "error": "insecure"}
	var http := _new_request()
	var headers := PackedStringArray(["Accept: application/json", "User-Agent: " + USER_AGENT])
	if key != "":
		headers.append("Authorization: Bearer " + key.strip_edges())
	var data := ""
	if body != null:
		headers.append("Content-Type: application/json")
		data = JSON.stringify(body)
	var st := {"done": false}
	http.request_completed.connect(_on_done.bind(st), CONNECT_ONE_SHOT)
	var err := http.request(base_url + path, headers, method, data)
	if err != OK:
		http.queue_free()
		return {"ok": false, "code": 0, "error": "net", "detail": error_string(err)}
	var finished: bool = await _wait(http, st, JSON_TIMEOUT)
	http.queue_free()
	if not finished:
		return {"ok": false, "code": 0, "error": "timeout"}
	return parse_response(st["result"], st["code"], st["body"])


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, st: Dictionary) -> void:
	st["result"] = result
	st["code"] = code
	st["body"] = body
	st["done"] = true


static func parse_response(result: int, code: int, body: PackedByteArray) -> Dictionary:
	if result != HTTPRequest.RESULT_SUCCESS:
		var failure := "net"
		if result == HTTPRequest.RESULT_TIMEOUT:
			failure = "timeout"
		elif result == HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			failure = "tls"
		return {"ok": false, "code": 0, "error": failure, "detail": "result %d" % result}
	var data: Variant = JSON.parse_string(body.get_string_from_utf8()) if body.size() > 0 else null
	if code >= 200 and code < 300:
		if data is Dictionary:
			return {"ok": true, "code": code, "data": data}
		return {"ok": false, "code": code, "error": "bad_response"}
	var e := "server"
	var server_error: String = str(data.get("error", "")) if data is Dictionary else ""
	match code:
		401:
			e = "key"
		403:
			e = "buy" if server_error in ["pro", "buy", ""] else "forbidden"
		404:
			e = "not_found"
		429:
			e = "limit"
	return {"ok": false, "code": code, "error": e, "data": data}


## Downloads `url` to `to_path`. on_progress.call(bytes_done, bytes_total_or_-1) runs every frame.
## The account key is never sent here: download links are signed and go to file storage.
func download(url: String, to_path: String, expected_bytes: int, on_progress: Callable) -> Dictionary:
	if not (url.begins_with("https://") or url.begins_with("http://127.0.0.1") or url.begins_with("http://localhost")):
		return {"ok": false, "code": 0, "error": "insecure"}
	var http := _new_request()
	http.download_chunk_size = 1048576
	http.download_file = to_path
	var st := {"done": false, "cancel": false}
	_download = st
	http.request_completed.connect(_on_done.bind(st), CONNECT_ONE_SHOT)
	var err := http.request(url, PackedStringArray(["User-Agent: " + USER_AGENT]))
	if err != OK:
		http.queue_free()
		_download = {}
		return {"ok": false, "code": 0, "error": "net", "detail": error_string(err)}
	var last := -1
	var still := 0.0
	while not st["done"]:
		if st["cancel"] or still > STALL_TIMEOUT:
			http.cancel_request()
			http.queue_free()
			_download = {}
			DirAccess.remove_absolute(to_path)
			return {"ok": false, "code": 0, "error": "cancelled" if st["cancel"] else "stalled"}
		var got := http.get_downloaded_bytes()
		var total := http.get_body_size()
		if total <= 0 and expected_bytes > 0:
			total = expected_bytes
		if on_progress.is_valid():
			on_progress.call(got, total)
		var t := Time.get_ticks_msec()
		await get_tree().process_frame
		if got != last:
			last = got
			still = 0.0
		else:
			still += minf((Time.get_ticks_msec() - t) / 1000.0, MAX_STEP)
	http.queue_free()
	_download = {}
	var code: int = st["code"]
	if st["result"] != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		DirAccess.remove_absolute(to_path)
		var r := parse_response(st["result"], code, PackedByteArray())
		if r["ok"]:
			r = {"ok": false, "code": code, "error": "server"}
		if code == 403 or code == 404:
			r["error"] = "expired"
		return r
	var size := 0
	var f := FileAccess.open(to_path, FileAccess.READ)
	if f:
		size = f.get_length()
		f.close()
	if size == 0 or (expected_bytes > 0 and size != expected_bytes):
		DirAccess.remove_absolute(to_path)
		return {"ok": false, "code": code, "error": "incomplete", "detail": "%d of %d bytes" % [size, expected_bytes]}
	return {"ok": true, "code": code, "bytes": size}


func cancel_download() -> void:
	if not _download.is_empty():
		_download["cancel"] = true


func is_downloading() -> bool:
	return not _download.is_empty()


## A small public file (a cover picture). No key is sent.
func fetch(url: String, max_bytes := 4 * 1024 * 1024) -> Dictionary:
	if not (url.begins_with("https://") or url.begins_with("http://")):
		return {"ok": false, "code": 0, "error": "bad_url"}
	var http := _new_request()
	http.body_size_limit = max_bytes
	var st := {"done": false}
	http.request_completed.connect(_on_done.bind(st), CONNECT_ONE_SHOT)
	if http.request(url, PackedStringArray(["User-Agent: " + USER_AGENT])) != OK:
		http.queue_free()
		return {"ok": false, "code": 0, "error": "net"}
	var finished: bool = await _wait(http, st, COVER_TIMEOUT)
	http.queue_free()
	if not finished or st["result"] != HTTPRequest.RESULT_SUCCESS or st["code"] != 200:
		return {"ok": false, "code": st.get("code", 0), "error": "net"}
	return {"ok": true, "code": 200, "body": st["body"]}

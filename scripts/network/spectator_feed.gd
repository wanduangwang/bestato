extends Node

signal frame_received(info: PackedInt32Array, time_left: float,
		roster: PackedFloat32Array, horde: PackedFloat32Array, world: PackedFloat32Array)
signal status_changed(message: String)
signal closed(message: String)

const FRAME_LIMIT := 64 * 1024
const PUBLISH_INTERVAL_MS := 110
const CONNECT_TIMEOUT_MS := 15000

var _source: JavaScriptObject
var _callbacks: Array[JavaScriptObject] = []
var _connect_deadline := 0
var _upload: HTTPRequest
var _uploading := false
var _next_publish := 0


func _ready() -> void:
	_upload = HTTPRequest.new()
	_upload.timeout = 2.0
	_upload.body_size_limit = 2048
	add_child(_upload)
	_upload.request_completed.connect(_on_upload_finished)


func watch(origin: String, code: String, key: String) -> bool:
	var url := "%s/spectate?code=%s&key=%s" % [origin, code.uri_encode(), key.uri_encode()]
	_source = JavaScriptBridge.create_object("EventSource", url)
	if _source == null:
		return false
	_callbacks.assign([
		JavaScriptBridge.create_callback(_on_frame),
		JavaScriptBridge.create_callback(_on_error),
		JavaScriptBridge.create_callback(_on_closed),
	])
	_source.onmessage = _callbacks[0]
	_source.onerror = _callbacks[1]
	_source.addEventListener("room_closed", _callbacks[2])
	_connect_deadline = Time.get_ticks_msec() + CONNECT_TIMEOUT_MS
	status_changed.emit("Connecting to the spectator feed...")
	return true


func stop() -> void:
	if _source != null:
		_source.close()
		_source = null
	_callbacks.clear()
	_connect_deadline = 0
	_upload.cancel_request()
	_uploading = false
	_next_publish = 0


func publish(url: String, code: String, token: String, frame: Array) -> void:
	var now := Time.get_ticks_msec()
	if _uploading or now < _next_publish:
		return
	_next_publish = now + PUBLISH_INTERVAL_MS
	var encoded := Marshalls.raw_to_base64(var_to_bytes(frame))
	if encoded.length() > FRAME_LIMIT:
		return
	var body := JSON.stringify({"action": "publish", "code": code, "token": token, "frame": encoded})
	_uploading = _upload.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body) == OK


func _on_upload_finished(_result: int, _response: int, _headers: PackedStringArray,
		_body: PackedByteArray) -> void:
	_uploading = false


func _process(_delta: float) -> void:
	if _connect_deadline > 0 and Time.get_ticks_msec() >= _connect_deadline:
		_connect_deadline = 0
		closed.emit("The spectator feed timed out.")


func _on_error(_args: Array) -> void:
	if _connect_deadline == 0:
		_connect_deadline = Time.get_ticks_msec() + CONNECT_TIMEOUT_MS
	status_changed.emit("Reconnecting to the spectator feed...")


func _on_closed(args: Array) -> void:
	_connect_deadline = 0
	var message := "The host closed the room." if args.is_empty() else str(args[0].data)
	closed.emit(message)


func _on_frame(args: Array) -> void:
	if args.is_empty():
		return
	var encoded := str(args[0].data)
	if encoded.is_empty() or encoded.length() > FRAME_LIMIT:
		return
	var frame: Variant = bytes_to_var(Marshalls.base64_to_raw(encoded))
	if frame is Array and frame.size() == 5 and frame[0] is PackedInt32Array and frame[1] is float \
			and frame[2] is PackedFloat32Array and frame[3] is PackedFloat32Array and frame[4] is PackedFloat32Array:
		frame_received.emit(frame[0], frame[1], frame[2], frame[3], frame[4])
		if _connect_deadline > 0:
			_connect_deadline = 0
			status_changed.emit("Live spectator feed")

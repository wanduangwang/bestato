extends Node

signal backgrounded
signal touch_changed
signal invite_received(code: String)

const DESIGN_SIZE := Vector2(1120, 720)
const WECHAT_DIR := "/bestato-wechat"
const WECHAT_EVENTS := WECHAT_DIR + "/events.json"

var wechat := false
var relay_enabled := false
var relay_url := ""
var touch_enabled := false
var pending_invite := ""

var _wechat_config: Dictionary = {}
var _keyboard_target: WeakRef
var _event_poll := 0.0


func _ready() -> void:
	touch_enabled = DisplayServer.is_touchscreen_available()
	set_process(false)
	if not OS.has_feature("web"):
		return
	if OS.has_feature("wechat_minigame"):
		wechat = true
		relay_enabled = true
		touch_enabled = true
		_wechat_config = _read_wechat_file(WECHAT_DIR + "/config.json")
		relay_url = str(_wechat_config.get("relay_url", ""))
		pending_invite = str(_wechat_config.get("invite", ""))
		set_process(true)
		return
	var browser := JavaScriptBridge.get_interface("window")
	if browser == null:
		return
	if str(browser.location.hostname) in ["localhost", "127.0.0.1"] \
			and "relay=1" in str(browser.location.search).trim_prefix("?").split("&"):
		relay_enabled = true
		var origin := str(browser.location.origin)
		relay_url = origin.replace("http", "ws") + "/wechat-room"


func _input(event: InputEvent) -> void:
	if not touch_enabled and event is InputEventScreenTouch:
		touch_enabled = true
		touch_changed.emit()


func safe_rect() -> Rect2:
	if not wechat:
		return Rect2(Vector2.ZERO, DESIGN_SIZE)
	var area: Variant = _wechat_config.get("safe_area", [])
	if not area is Array or area.size() != 6:
		return Rect2(Vector2.ZERO, DESIGN_SIZE)
	var screen := Vector2(area[0], area[1])
	var ratio := minf(screen.x / DESIGN_SIZE.x, screen.y / DESIGN_SIZE.y)
	if ratio <= 0.0:
		return Rect2(Vector2.ZERO, DESIGN_SIZE)
	var origin := (screen - DESIGN_SIZE * ratio) * 0.5
	var left_top := (Vector2(area[2], area[3]) - origin) / ratio
	var right_bottom := (Vector2(area[4], area[5]) - origin) / ratio
	var safe := Rect2(left_top, right_bottom - left_top).intersection(Rect2(Vector2.ZERO, DESIGN_SIZE))
	return safe if safe.size.x >= DESIGN_SIZE.x * 0.7 and safe.size.y >= DESIGN_SIZE.y * 0.7 \
		else Rect2(Vector2.ZERO, DESIGN_SIZE)


func read_preferences() -> String:
	return str(_wechat_config.get("preferences", "{}"))


func write_preferences(data: String) -> void:
	_wechat_command("preferences", data)


func open_room_keyboard(field: LineEdit) -> void:
	_keyboard_target = weakref(field)
	_wechat_command("keyboard", field.text)


func share_room(code: String) -> void:
	_wechat_command("share", code)


func copy_room(code: String) -> void:
	if wechat:
		_wechat_command("copy", code)
	else:
		DisplayServer.clipboard_set(code)


func _read_wechat_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	return value if value is Dictionary else {}


func _wechat_command(action: String, value: String) -> void:
	var file := FileAccess.open(WECHAT_DIR + "/command.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"action": action, "value": value}))
		file.close()


func _process(delta: float) -> void:
	_event_poll -= delta
	if _event_poll > 0.0:
		return
	_event_poll = 0.05
	if not FileAccess.file_exists(WECHAT_EVENTS):
		return
	var events := _read_wechat_file(WECHAT_EVENTS)
	DirAccess.remove_absolute(WECHAT_EVENTS)
	if events.get("hidden", false):
		backgrounded.emit()
	if events.has("invite"):
		pending_invite = str(events["invite"])
		invite_received.emit(pending_invite)
	if events.has("keyboard"):
		_update_keyboard(events["keyboard"])


func _update_keyboard(args: Array) -> void:
	var field: LineEdit = _keyboard_target.get_ref() if _keyboard_target else null
	if is_instance_valid(field):
		field.text = str(args[0])
		if args[1]:
			field.release_focus()
			_keyboard_target = null

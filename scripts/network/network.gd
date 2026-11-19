extends Node

const SpectatorFeed = preload("res://scripts/network/spectator_feed.gd")
const RelayClient = preload("res://scripts/network/relay_client.gd")

signal hosted
signal session_ended
signal combat_seats_locked
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal input_received(peer_id: int, direction: Vector2)
signal choice_received(peer_id: int, action: int, slot: int, revision: int)
signal profile_received(profile: Dictionary)
signal snapshot_received(info: PackedInt32Array, time_left: float,
		roster: PackedFloat32Array, horde: PackedFloat32Array, world: PackedFloat32Array)

enum State { IDLE, REQUESTING, HOST, CONNECTING, CLIENT, SPECTATOR }

const HOST_ID := 1
const ROOM_CAPACITY := 4
const SIGNAL_INTERVAL := 0.20
const RTC_TIMEOUT_MS := 18000
const RTC_CHANNEL_OPEN := 1
const ROOM_PROTOCOL := 3

var state: int = State.IDLE
var room_code := ""
var status := ""
var viewer_count := 0
var players_locked := false
var seat_change_pending: bool:
	get:
		return not _seat_change.is_empty() or not _seat_inflight.is_empty()

var _token := ""
var _url := ""
var _origin := ""
var _ice_servers: Array = []
# The compatible Mini Game engine omits the WebRTC classes.
var _rtc
var _http: HTTPRequest
var _feed: SpectatorFeed
var _action := ""
var _seat_change := ""
var _seat_inflight := ""
var _seat_roster: Array = []
var _sync_in := 0.0
var _connections: Dictionary = {}
var _deadlines: Dictionary = {}
var _remote_sdp: Dictionary = {}
var _early_ice: Dictionary = {}
var _outbox: Array[Dictionary] = []
var _drops: Array[int] = []
var _relay: RelayClient
var _relay_id := HOST_ID


func _ready() -> void:
	if Platform.relay_enabled:
		_relay = RelayClient.new()
		add_child(_relay)
		_relay.received.connect(_on_relay_message)
		_relay.disconnected.connect(_on_relay_disconnected)
		Platform.backgrounded.connect(_on_backgrounded)
	_http = HTTPRequest.new()
	_http.timeout = 6.0
	_http.body_size_limit = 1024 * 1024
	add_child(_http)
	_http.request_completed.connect(_on_reply)
	_feed = SpectatorFeed.new()
	add_child(_feed)
	_feed.frame_received.connect(_receive_spectator_frame)
	_feed.closed.connect(_spectator_closed, CONNECT_DEFERRED)
	_feed.status_changed.connect(_spectator_status)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.server_disconnected.connect(_on_host_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	# Clients have one connection, directly to peer 1.
	(multiplayer as SceneMultiplayer).server_relay = false


func create_room() -> void:
	_open_room("create", "")


func join_room(code: String) -> void:
	_find_room("join", code)


func watch_room(code: String) -> void:
	_find_room("watch", code)


func _find_room(action: String, code: String) -> void:
	code = code.strip_edges().to_upper()
	if code.length() != 6:
		status = "Enter a six-character room code."
		return
	_open_room(action, code)


func leave_room() -> void:
	_close("")


func local_id() -> int:
	return _relay_id if _relay != null else multiplayer.get_unique_id()


func lock_player_seats(roster: Array) -> void:
	if state == State.HOST and not players_locked and not seat_change_pending:
		if _relay != null:
			_change_relay_seats(true, roster)
			return
		_seat_change = "lock"
		_seat_roster = roster.duplicate()
		_sync_in = 0.0


func open_player_seats() -> void:
	if state == State.HOST and players_locked:
		if _relay != null:
			_change_relay_seats(false, [])
			return
		_seat_change = "open"
		_seat_roster.clear()
		_sync_in = 0.0


func reject_player(peer_id: int) -> void:
	if state != State.HOST:
		return
	if _relay != null:
		_relay.send({"type": "drop", "id": peer_id})
	elif _connections.has(peer_id):
		_forget_peer(peer_id)
		_drops.append(peer_id)


func _open_room(action: String, code: String) -> void:
	if state != State.IDLE:
		return
	if not OS.has_feature("web"):
		status = "Open the Web export to play online."
		return
	state = State.REQUESTING
	status = "Creating room..." if action == "create" else "Looking up room..."
	if _relay != null:
		if Platform.relay_url.is_empty():
			_close("Online play is unavailable in this build.")
		elif not _relay.start(Platform.relay_url, action, code):
			_close("Could not reach the signaling server.")
		return
	if not ClassDB.class_exists("WebRTCMultiplayerPeer"):
		_close("Could not start WebRTC.")
		return
	var browser := JavaScriptBridge.get_interface("window")
	_origin = str(browser.location.origin)
	_url = _origin + "/signal"
	_request(action, {"code": code, "version": ROOM_PROTOCOL})


func _change_relay_seats(lock: bool, active: Array) -> void:
	if _relay.send({"type": "seats", "lock": lock, "active": active}):
		_seat_inflight = "lock" if lock else "open"
	else:
		_close("The room connection closed.", true)


func _on_relay_disconnected() -> void:
	if state != State.IDLE:
		var message := "Could not reach the signaling server." if state == State.REQUESTING \
			else "The room connection closed."
		_close(message, true)


func _on_backgrounded() -> void:
	if state != State.IDLE:
		_close("The room connection closed.", true)


func _on_relay_message(message: Dictionary) -> void:
	match message.get("type"):
		"admitted":
			if state != State.REQUESTING:
				return
			room_code = str(message["code"])
			_relay_id = int(message["id"])
			match _relay_id:
				HOST_ID:
					state = State.HOST
					status = "Share the room code with your squad."
					hosted.emit()
				0:
					state = State.SPECTATOR
					status = "Connecting to the spectator feed..."
				_:
					state = State.CLIENT
					status = "Connected. Waiting for the host to start."
		"error":
			_close(str(message.get("error", "The room request failed.")), true)
		"peer_joined":
			if state == State.HOST:
				peer_joined.emit(int(message["id"]))
		"peer_left":
			if state == State.HOST:
				peer_left.emit(int(message["id"]))
		"viewers":
			viewer_count = int(message["count"])
		"seats":
			var locking := _seat_inflight == "lock"
			_seat_inflight = ""
			players_locked = message["locked"]
			if locking and players_locked and state == State.HOST:
				combat_seats_locked.emit()
		"input":
			var direction := Vector2(message["x"], message["y"])
			if state == State.HOST and direction.is_finite():
				input_received.emit(int(message["id"]), direction.limit_length())
		"choice":
			if state == State.HOST:
				choice_received.emit(int(message["id"]), int(message["action"]),
					int(message["slot"]), int(message["revision"]))
		"profile":
			if state == State.CLIENT:
				var profile: Variant = _decode_relay_data(message)
				if profile is Dictionary:
					profile_received.emit(profile)
		"snapshot":
			if state in [State.CLIENT, State.SPECTATOR]:
				_on_relay_frame(_decode_relay_data(message))


func _decode_relay_data(message: Dictionary) -> Variant:
	var encoded: Variant = message.get("data")
	return bytes_to_var(Marshalls.base64_to_raw(encoded)) if encoded is String else null


func _on_relay_frame(frame: Variant) -> void:
	if frame is Array and frame.size() == 5 and frame[0] is PackedInt32Array and frame[1] is float \
			and frame[2] is PackedFloat32Array and frame[3] is PackedFloat32Array and frame[4] is PackedFloat32Array:
		snapshot_received.emit(frame[0], frame[1], frame[2], frame[3], frame[4])
		if state == State.SPECTATOR:
			status = "Live spectator feed"


func _request(action: String, data: Dictionary) -> void:
	data["action"] = action
	_action = action
	var error := _http.request(_url, ["Content-Type: application/json"],
			HTTPClient.METHOD_POST, JSON.stringify(data))
	if error != OK:
		_close("Could not reach the signaling server.", true)


func _process(delta: float) -> void:
	if _rtc == null:
		return
	var now := Time.get_ticks_msec()
	for peer_id: int in _deadlines.keys():
		if now >= int(_deadlines[peer_id]):
			_fail_peer(peer_id)
			if _rtc == null:
				return
	_sync_in -= delta
	if _sync_in <= 0.0 and _action.is_empty():
		_sync_in = SIGNAL_INTERVAL
		var batch := _outbox.slice(0, 64)
		_outbox = _outbox.slice(batch.size())
		var drops := _drops.duplicate()
		_drops.clear()
		var payload := {"code": room_code, "token": _token, "messages": batch, "drop": drops}
		if not _seat_change.is_empty():
			_seat_inflight = _seat_change
			_seat_change = ""
			payload["seats"] = _seat_inflight
			payload["active"] = _seat_roster
		_request("sync", payload)


func _on_reply(result: int, response: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	var action := _action
	_action = ""
	if state == State.IDLE:
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or not data is Dictionary:
		_close("Could not reach the signaling server.", true)
		return
	if response != 200:
		_close(str(data.get("error", "The room request failed.")), true)
		return
	if action == "sync":
		var locking := _seat_inflight == "lock"
		_seat_inflight = ""
		players_locked = data.get("locked", false)
		viewer_count = int(data.get("viewers", 0))
		for event: Dictionary in data.get("events", []):
			_handle_event(event)
			if state == State.IDLE:
				break
		if locking and state == State.HOST and players_locked:
			combat_seats_locked.emit()
		return
	if action == "watch":
		room_code = str(data["code"])
		state = State.SPECTATOR
		if not _feed.watch(_origin, room_code, str(data["watchKey"])):
			_close("Could not open the spectator feed.", true)
		return
	_token = str(data["token"])
	room_code = str(data["code"])
	_ice_servers = data.get("iceServers", [])
	_rtc = ClassDB.instantiate("WebRTCMultiplayerPeer")
	var is_host := action == "create"
	var error: Error = _rtc.create_server() if is_host else _rtc.create_client(int(data["id"]))
	if error != OK:
		_close("Could not start WebRTC.", true)
		return
	multiplayer.multiplayer_peer = _rtc
	if is_host:
		state = State.HOST
		status = "Share the room code with your squad."
		hosted.emit()
	else:
		state = State.CONNECTING
		status = "Connecting directly to the host..."
		if not _add_connection(HOST_ID):
			_fail_peer(HOST_ID)


func _add_connection(peer_id: int) -> bool:
	var connection = ClassDB.instantiate("WebRTCPeerConnection")
	if connection.initialize({"iceServers": _ice_servers}) != OK:
		return false
	connection.session_description_created.connect(_on_local_sdp.bind(peer_id))
	connection.ice_candidate_created.connect(_on_local_ice.bind(peer_id))
	# Godot creates its negotiated data channels before SDP is generated.
	if _rtc.add_peer(connection, peer_id, 200) != OK:
		connection.close()
		return false
	_connections[peer_id] = connection
	_deadlines[peer_id] = Time.get_ticks_msec() + RTC_TIMEOUT_MS
	return true


func _handle_event(event: Dictionary) -> void:
	var peer_id := int(event.get("peer", 0))
	match str(event.get("type", "")):
		"peer_joined":
			if state == State.HOST and not _connections.has(peer_id):
				if not _add_connection(peer_id):
					_fail_peer(peer_id)
					return
				var connection = _connections[peer_id]
				if connection.create_offer() != OK:
					_fail_peer(peer_id)
		"peer_left":
			_forget_peer(peer_id)
		"offer", "answer":
			_receive_sdp(peer_id, event)
		"ice":
			_receive_ice(peer_id, event)


func _on_local_sdp(kind: String, sdp: String, peer_id: int) -> void:
	var connection = _connections.get(peer_id)
	if connection == null:
		return
	if connection.set_local_description(kind, sdp) != OK:
		_fail_peer(peer_id)
		return
	_outbox.append({"type": kind, "to": peer_id, "sdp": sdp})


func _on_local_ice(media: String, index: int, candidate: String, peer_id: int) -> void:
	if _connections.has(peer_id):
		_outbox.append({"type": "ice", "to": peer_id, "media": media,
				"index": index, "candidate": candidate})


func _receive_sdp(peer_id: int, event: Dictionary) -> void:
	var connection = _connections.get(peer_id)
	if connection == null or _remote_sdp.has(peer_id):
		return
	if connection.set_remote_description(str(event["type"]), str(event["sdp"])) != OK:
		_fail_peer(peer_id)
		return
	_remote_sdp[peer_id] = true
	for candidate: Dictionary in _early_ice.get(peer_id, []):
		_receive_ice(peer_id, candidate)
	_early_ice.erase(peer_id)


func _receive_ice(peer_id: int, event: Dictionary) -> void:
	var connection = _connections.get(peer_id)
	if connection == null:
		return
	# Candidates can arrive before the remote description is handed to the browser.
	if not _remote_sdp.has(peer_id):
		if not _early_ice.has(peer_id):
			_early_ice[peer_id] = []
		if _early_ice[peer_id].size() < 64:
			_early_ice[peer_id].append(event)
		return
	connection.add_ice_candidate(str(event["media"]), int(event["index"]), str(event["candidate"]))


func _on_connected() -> void:
	if state == State.CONNECTING:
		_deadlines.erase(HOST_ID)
		state = State.CLIENT
		status = "Connected. Waiting for the host to start."


func _on_peer_connected(peer_id: int) -> void:
	if state == State.HOST:
		_deadlines.erase(peer_id)
		status = "Squadmate connected."
		peer_joined.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if state != State.HOST:
		return
	peer_left.emit(peer_id)
	if _connections.has(peer_id):
		# The multiplayer peer may be iterating its connections during the signal.
		_drop_disconnected.call_deferred(peer_id)


func _drop_disconnected(peer_id: int) -> void:
	if state == State.HOST and _connections.has(peer_id):
		_forget_peer(peer_id)
		_drops.append(peer_id)
		status = "A squadmate disconnected."


func _on_host_disconnected() -> void:
	_lose_host.call_deferred()


func _lose_host() -> void:
	if state == State.CLIENT or state == State.CONNECTING:
		_close("The host disconnected.", true)


func _fail_peer(peer_id: int) -> void:
	if state == State.HOST:
		_forget_peer(peer_id)
		_drops.append(peer_id)
		status = "A peer could not connect. These networks may need TURN."
	else:
		_close("Direct connection failed. These networks may need TURN.", true)


func _forget_peer(peer_id: int) -> void:
	var connection = _connections.get(peer_id)
	_connections.erase(peer_id)
	_deadlines.erase(peer_id)
	_remote_sdp.erase(peer_id)
	_early_ice.erase(peer_id)
	if _rtc != null and _rtc.has_peer(peer_id):
		_rtc.remove_peer(peer_id)
	if connection != null:
		connection.close()


func _close(message: String, unexpected := false) -> void:
	if not _token.is_empty():
		_notify_leave()
	state = State.IDLE
	if _relay != null:
		_relay.stop()
		_relay_id = HOST_ID
	_feed.stop()
	_http.cancel_request()
	_action = ""
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if _rtc != null:
		_rtc.close()
		_rtc = null
	for connection in _connections.values():
		connection.close()
	_connections.clear()
	_deadlines.clear()
	_remote_sdp.clear()
	_early_ice.clear()
	_outbox.clear()
	_drops.clear()
	_seat_change = ""
	_seat_inflight = ""
	_seat_roster.clear()
	players_locked = false
	viewer_count = 0
	_token = ""
	room_code = ""
	status = message
	_sync_in = 0.0
	if unexpected:
		session_ended.emit()


func _notify_leave() -> void:
	var leave_request := HTTPRequest.new()
	leave_request.timeout = 3.0
	add_child(leave_request)
	leave_request.request_completed.connect(
		func(_result: int, _response: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
			leave_request.queue_free()
	)
	var body := JSON.stringify({"action": "leave", "code": room_code, "token": _token})
	if leave_request.request(_url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body) != OK:
		leave_request.queue_free()


func send_input(direction: Vector2) -> void:
	if state != State.CLIENT:
		return
	if _relay != null:
		_relay.send({"type": "input", "x": direction.x, "y": direction.y}, true)
	elif _data_channels_open(HOST_ID):
		_receive_input.rpc_id(HOST_ID, direction)


func send_snapshot(info: PackedInt32Array, time_left: float, roster: PackedFloat32Array,
		horde: PackedFloat32Array, world: PackedFloat32Array) -> void:
	if state == State.HOST:
		if _relay != null:
			var frame := Marshalls.raw_to_base64(var_to_bytes([info, time_left, roster, horde, world]))
			_relay.send({"type": "snapshot", "data": frame}, true)
			return
		for peer_id: int in multiplayer.get_peers():
			if _data_channels_open(peer_id):
				_apply_snapshot.rpc_id(peer_id, info, time_left, roster, horde, world)
		if viewer_count > 0:
			_feed.publish(_url, room_code, _token, [info, time_left, roster, horde, world])


func _receive_spectator_frame(info: PackedInt32Array, time_left: float, roster: PackedFloat32Array,
		horde: PackedFloat32Array, world: PackedFloat32Array) -> void:
	if state == State.SPECTATOR:
		snapshot_received.emit(info, time_left, roster, horde, world)


func _spectator_status(message: String) -> void:
	if state == State.SPECTATOR:
		status = message


func _spectator_closed(message: String) -> void:
	if state == State.SPECTATOR:
		_close(message, true)


func send_choice(action: int, slot: int, revision: int) -> void:
	if state != State.CLIENT:
		return
	if _relay != null:
		_relay.send({"type": "choice", "action": action, "slot": slot, "revision": revision})
	elif _data_channels_open(HOST_ID):
		_receive_choice.rpc_id(HOST_ID, action, slot, revision)


func send_profile(peer_id: int, profile: Dictionary) -> bool:
	if state != State.HOST:
		return false
	if _relay != null:
		var encoded := Marshalls.raw_to_base64(var_to_bytes(profile))
		return _relay.send({"type": "profile", "id": peer_id, "data": encoded})
	return _data_channels_open(peer_id) and rpc_id(peer_id, &"_apply_profile", profile) == OK


func _data_channels_open(peer_id: int) -> bool:
	if not _rtc.has_peer(peer_id):
		return false
	var peer: Dictionary = _rtc.get_peer(peer_id)
	# A browser can close a channel before Godot emits peer_disconnected.
	for channel in peer["channels"]:
		if channel.get_ready_state() != RTC_CHANNEL_OPEN:
			return false
	return peer["connected"]


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _receive_input(direction: Vector2) -> void:
	if state == State.HOST and direction.is_finite():
		input_received.emit(multiplayer.get_remote_sender_id(), direction.limit_length())


@rpc("any_peer", "call_remote", "reliable")
func _receive_choice(action: int, slot: int, revision: int) -> void:
	if state == State.HOST:
		choice_received.emit(multiplayer.get_remote_sender_id(), action, slot, revision)


@rpc("authority", "call_remote", "reliable")
func _apply_profile(profile: Dictionary) -> void:
	if state == State.CLIENT or state == State.CONNECTING:
		profile_received.emit(profile)


@rpc("authority", "call_remote", "unreliable_ordered")
func _apply_snapshot(info: PackedInt32Array, time_left: float, roster: PackedFloat32Array,
		horde: PackedFloat32Array, world: PackedFloat32Array) -> void:
	if state == State.CLIENT:
		snapshot_received.emit(info, time_left, roster, horde, world)

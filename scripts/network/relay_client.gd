extends Node

signal received(message: Dictionary)
signal disconnected

const VERSION := 1
const PACKET_LIMIT := 65 * 1024
const CONNECT_MS := 8500
const TRANSIENT_BACKLOG := 32 * 1024

var _socket: WebSocketPeer
var _admission: Dictionary
var _deadline := 0


func start(url: String, action: String, code: String) -> bool:
	stop()
	_socket = WebSocketPeer.new()
	_socket.inbound_buffer_size = PACKET_LIMIT * 4
	_socket.outbound_buffer_size = PACKET_LIMIT * 4
	_admission = {"type": action, "code": code, "version": VERSION}
	_deadline = Time.get_ticks_msec() + CONNECT_MS
	if _socket.connect_to_url(url) != OK:
		stop()
		return false
	return true


func stop() -> void:
	if _socket != null:
		_socket.close()
		_socket = null
	_admission = {}
	_deadline = 0


func send(message: Dictionary, transient := false) -> bool:
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	if transient and _socket.get_current_outbound_buffered_amount() >= TRANSIENT_BACKLOG:
		return false
	return _socket.send_text(JSON.stringify(message)) == OK


func _process(_delta: float) -> void:
	if _socket == null:
		return
	_socket.poll()
	var state := _socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _admission.is_empty() and send(_admission):
			_admission = {}
		var latest_snapshot: Dictionary = {}
		for packet in range(mini(64, _socket.get_available_packet_count())):
			var bytes := _socket.get_packet()
			if not _socket.was_string_packet() or bytes.size() > PACKET_LIMIT:
				continue
			var message: Variant = JSON.parse_string(bytes.get_string_from_utf8())
			if not message is Dictionary:
				continue
			# Full frames replace earlier queued frames. Seat and shop messages keep their order.
			if message.get("type") == "snapshot":
				latest_snapshot = message
			else:
				if message.get("type") == "admitted":
					_deadline = 0
				received.emit(message)
				if _socket == null:
					return
		if not latest_snapshot.is_empty():
			received.emit(latest_snapshot)
			if _socket == null:
				return
	if state == WebSocketPeer.STATE_CLOSED or (_deadline > 0 and Time.get_ticks_msec() >= _deadline):
		stop()
		disconnected.emit()

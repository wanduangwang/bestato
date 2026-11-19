extends Node2D

signal direction_changed(direction: Vector2)

const RADIUS := 64.0
const DEAD_ZONE := 0.15

var _finger := -1
var _knob := Vector2.ZERO


func _ready() -> void:
	hide()
	set_process_input(false)


func set_active(active: bool) -> void:
	if active == visible:
		return
	visible = active
	set_process_input(active)
	if not active:
		cancel()


func cancel() -> void:
	if _finger >= 0:
		_finger = -1
		_set_knob(Vector2.ZERO)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		cancel()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var local := make_input_local(event) as InputEventScreenTouch
		if event.index == _finger and (event.canceled or not event.pressed):
			cancel()
		elif _finger < 0 and event.pressed and not event.canceled and local.position.length() <= RADIUS:
			_finger = event.index
			_set_knob(local.position)
		else:
			return
	elif event is InputEventScreenDrag and event.index == _finger:
		var local := make_input_local(event) as InputEventScreenDrag
		_set_knob(local.position)
	else:
		return
	get_viewport().set_input_as_handled()


func _set_knob(offset: Vector2) -> void:
	_knob = offset.limit_length(RADIUS)
	var direction := _knob / RADIUS
	var strength := maxf(0.0, (direction.length() - DEAD_ZONE) / (1.0 - DEAD_ZONE))
	direction_changed.emit(direction.normalized() * strength)
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, Color("#30242e99"), true, -1.0, true)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 64, Color("#f6ead690"), 3.0, true)
	draw_circle(_knob, 26.0, Color("#f6ead6b8"), true, -1.0, true)

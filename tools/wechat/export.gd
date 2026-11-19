extends SceneTree


func _initialize() -> void:
	_export.call_deferred()


func _export() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		push_error("Expected template zip, AppID, and output directory.")
		quit(1)
		return
	var script := load("res://addons/godot_mini_game/exporter.gd") as GDScript
	var exporter = script.new()
	exporter.log_callback = func(message: String) -> void: print(message)
	exporter.pack_timeout_seconds = 120.0
	var result: Error = exporter.import_template_zip(args[0])
	if result == OK:
		result = await exporter.export_mini_game("wechat", args[1], "landscape", "Web", args[2])
	quit(0 if result == OK else 1)

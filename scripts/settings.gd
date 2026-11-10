extends Node

signal language_changed
signal sound_changed(muted: bool)

const FILE_PATH := "user://settings.cfg"
const BROWSER_KEY := "bestato.settings.v1"

@onready var cjk_font: Font = load("res://assets/fonts/BestatoUI-Regular.otf")

var language := "en"
var sound_muted := false


func _ready() -> void:
	var values := _load_preferences()
	if values.get("language") in ["en", "zh_CN"]:
		language = values["language"]
	if values.get("sound_muted") is bool:
		sound_muted = values["sound_muted"]
	TranslationServer.set_locale(language)


func toggle_language() -> void:
	language = "zh_CN" if language == "en" else "en"
	TranslationServer.set_locale(language)
	_save_preferences()
	language_changed.emit()


func toggle_sound() -> void:
	sound_muted = not sound_muted
	_save_preferences()
	sound_changed.emit(sound_muted)


func ui_font() -> Font:
	return cjk_font if language == "zh_CN" else ThemeDB.fallback_font


func _load_preferences() -> Dictionary:
	if OS.has_feature("web"):
		# Each tab keeps its own settings through reloads. The browser copy seeds new tabs.
		var raw: Variant = JavaScriptBridge.eval("""
			(() => {
				const key = %s;
				let value;
				try { value = sessionStorage.getItem(key); } catch {}
				if (value != null) return value;
				try { value = localStorage.getItem(key); } catch {}
				try { sessionStorage.setItem(key, value ?? '{}'); } catch {}
				return value ?? '{}';
			})()
		""" % JSON.stringify(BROWSER_KEY))
		var values: Variant = JSON.parse_string(raw) if raw is String else null
		return values if values is Dictionary else {}
	var config := ConfigFile.new()
	if config.load(FILE_PATH) != OK:
		return {}
	return {
		"language": config.get_value("preferences", "language", "en"),
		"sound_muted": config.get_value("preferences", "sound_muted", false),
	}


func _save_preferences() -> void:
	if OS.has_feature("web"):
		var data := JSON.stringify({"language": language, "sound_muted": sound_muted})
		JavaScriptBridge.eval("""
			(() => {
				const key = %s, data = %s;
				try { sessionStorage.setItem(key, data); } catch {}
				try { localStorage.setItem(key, data); } catch {}
			})()
		""" % [JSON.stringify(BROWSER_KEY), JSON.stringify(data)])
		return
	var config := ConfigFile.new()
	config.set_value("preferences", "language", language)
	config.set_value("preferences", "sound_muted", sound_muted)
	config.save(FILE_PATH)

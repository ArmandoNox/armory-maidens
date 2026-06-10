extends Node
## Autoload "Game": holds the DataDB and the current Run across scene changes,
## plus save-file and settings IO (Run itself stays pure logic).
##
## Save model: checkpoint() persists whenever the run is NOT mid-battle. The
## last checkpoint is always the pre-fight map state, so a page refresh rolls
## back to before the fight — never skips one.

const SAVE_PATH := "user://run_save.json"
const SETTINGS_PATH := "user://settings.json"
## Bump on any breaking change to Run.to_dict's shape; old saves are discarded
## with a notice instead of crashing Continue mid-playtest.
const SAVE_VERSION := 1

var db: DataDB
var run: Run
var settings := {}
var stale_save_notice := false


func _ready() -> void:
	db = DataDB.load_default()
	settings = _read_json(SETTINGS_PATH)


func new_run() -> void:
	run = Run.create(db, ["kaede", "riko", "tsubaki", "mizuki"], randi())
	checkpoint()


## Persist the run if it is in a serializable state. Call after every
## map-level transition (node entered, battle resolved, draft, event).
func checkpoint() -> void:
	if run == null or run.state == "battle":
		return
	if run.state == "over":
		clear_save()
		return
	var d := run.to_dict()
	d["save_version"] = SAVE_VERSION
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func load_run() -> bool:
	var d := _read_json(SAVE_PATH)
	if d.is_empty():
		return false
	if int(d.get("save_version", 0)) != SAVE_VERSION:
		clear_save()
		stale_save_notice = true
		return false
	run = Run.from_dict(db, d)
	return true


func clear_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


## ---- Settings (tiny flag store: help_seen, future volume) -------------------

func setting(key: String, default_val = null):
	return settings.get(key, default_val)


func set_setting(key: String, value) -> void:
	settings[key] = value
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(settings))


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

class_name DataDB
extends RefCounted
## Loads all balance JSON into dictionaries. Single source of truth for rules data.

var element_order: Array = []
var element_colors: Dictionary = {}
var element_chart: Dictionary = {}
var phys_types: Array = []
var archetypes: Dictionary = {}
var girls: Dictionary = {}
var moves: Dictionary = {}
var enemies: Dictionary = {}
var encounters: Dictionary = {}


static func load_default() -> DataDB:
	var db := DataDB.new()
	var elems: Dictionary = _load_json("res://data/elements.json")
	db.element_order = elems.get("order", [])
	db.element_colors = elems.get("colors", {})
	db.element_chart = elems.get("chart", {})
	var phys: Dictionary = _load_json("res://data/physical.json")
	db.phys_types = phys.get("types", [])
	db.archetypes = phys.get("archetypes", {})
	db.girls = _load_json("res://data/girls.json")
	db.moves = _load_json("res://data/moves.json")
	db.enemies = _load_json("res://data/enemies.json")
	db.encounters = _load_json("res://data/encounters.json")
	return db


static func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("DataDB: cannot open %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("DataDB: bad JSON in %s" % path)
		return {}
	return parsed

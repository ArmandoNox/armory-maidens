extends Node
## Autoload "Game": holds the DataDB and the current Run across scene changes.

var db: DataDB
var run: Run


func _ready() -> void:
	db = DataDB.load_default()
	new_run()


func new_run() -> void:
	run = Run.create(db, ["kaede", "riko", "tsubaki", "mizuki"], randi())

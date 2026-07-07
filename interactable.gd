extends Node3D

@export var item_id: String = "ak47"
@export var display_name: String = "AK-47"

func get_interaction_text() -> String:
	return "E " + display_name

func get_item_id() -> String:
	return item_id

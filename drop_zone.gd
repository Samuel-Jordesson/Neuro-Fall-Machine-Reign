extends Control

var inventory_ui = null

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_STRING
	
func _drop_data(at_position: Vector2, data: Variant) -> void:
	if inventory_ui:
		inventory_ui.item_dropped.emit(data)

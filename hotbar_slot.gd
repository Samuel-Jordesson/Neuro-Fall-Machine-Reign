extends ColorRect

var slot_index: int = 0
var inventory_ui = null
var item_id: String = ""

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_STRING
	
func _drop_data(at_position: Vector2, data: Variant) -> void:
	item_id = data
	var lbl = get_node_or_null("Label")
	if lbl:
		lbl.text = "[%s]\n%s" % [str(slot_index + 1), data]
	if inventory_ui:
		inventory_ui.hotbar_updated.emit(slot_index, data)

extends Panel

var slot_index: int = 0
var inventory_ui = null
var item_id: String = ""

func _get_drag_data(_at_position: Vector2) -> Variant:
	if item_id == "": return null
	
	var preview = ColorRect.new()
	preview.custom_minimum_size = Vector2(56, 56)
	preview.color = Color(0,0,0,0)
	
	if item_id == "ak47":
		var icon = TextureRect.new()
		icon.texture = preload("res://ak47/ak47im.png")
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		preview.add_child(icon)
	else:
		var lbl = Label.new()
		lbl.text = item_id
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		preview.add_child(lbl)
		
	set_drag_preview(preview)
	
	var dragged_item = item_id
	item_id = ""
	
	for child in get_children():
		if child.name == "ItemIcon":
			child.queue_free()
			
	if inventory_ui:
		inventory_ui.hotbar_updated.emit(slot_index, "")
		
	return {"source": "hotbar", "slot": slot_index, "item": dragged_item}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has("item")
	
func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if inventory_ui:
		inventory_ui.hotbar_updated.emit(slot_index, data)

func update_visuals():
	for child in get_children():
		if child.name == "ItemIcon":
			child.queue_free()
			
	if item_id == "ak47":
		var icon = TextureRect.new()
		icon.name = "ItemIcon"
		icon.texture = preload("res://ak47/ak47im.png")
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 5
		icon.offset_top = 5
		icon.offset_right = -5
		icon.offset_bottom = -5
		add_child(icon)
	elif item_id != "":
		var lbl = Label.new()
		lbl.name = "ItemIcon"
		lbl.text = item_id
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(lbl)

extends CanvasLayer

signal item_dropped(item_id: String)
signal item_equipped(item_id: String)
signal hotbar_updated(slot_index: int, drag_data: Dictionary)
signal inventory_slot_swapped(drag_data: Dictionary, to_slot: int)

@onready var grid_container = $Panel/GridContainer
@onready var drop_zone = $DropZone
@onready var panel = $Panel
@onready var hotbar_slots = [$Hotbar/Slot1, $Hotbar/Slot2, $Hotbar/Slot3, $Hotbar/Slot4]

var inventory_slots_ui = []

func _ready():
	panel.hide()
	drop_zone.hide()
	
	drop_zone.inventory_ui = self
	
	for i in range(4):
		hotbar_slots[i].slot_index = i
		hotbar_slots[i].inventory_ui = self
		
		var num_lbl = Label.new()
		num_lbl.name = "NumLabel"
		num_lbl.text = str(i + 1)
		num_lbl.set("theme_override_font_sizes/font_size", 14)
		num_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		num_lbl.position = Vector2(0, -22)
		num_lbl.size = Vector2(56, 20)
		hotbar_slots[i].add_child(num_lbl)
		
	if has_node("Hotbar/BackpackContainer/Circle/Icon"):
		$Hotbar/BackpackContainer/Circle/Icon.texture = preload("res://inventario.svg")
		
	if has_node("Panel/HeaderIcon"):
		$Panel/HeaderIcon.texture = preload("res://inventario.svg")
		
	var style_slot = StyleBoxFlat.new()
	style_slot.bg_color = Color(0.851, 0.851, 0.851, 0.48)
	style_slot.border_width_left = 1
	style_slot.border_width_top = 1
	style_slot.border_width_right = 1
	style_slot.border_width_bottom = 1
	style_slot.border_color = Color(1, 1, 1, 1)
	style_slot.corner_radius_top_left = 6
	style_slot.corner_radius_top_right = 6
	style_slot.corner_radius_bottom_right = 6
	style_slot.corner_radius_bottom_left = 6
		
	for i in range(12):
		var slot_bg = Panel.new()
		slot_bg.custom_minimum_size = Vector2(56, 56)
		slot_bg.add_theme_stylebox_override("panel", style_slot)
		
		var slot_content = InventorySlot.new()
		slot_content.slot_index = i
		slot_content.inventory_ui = self
		slot_content.set_anchors_preset(Control.PRESET_FULL_RECT)
		slot_content.color = Color(0, 0, 0, 0)
		slot_bg.add_child(slot_content)
		
		grid_container.add_child(slot_bg)
		inventory_slots_ui.append(slot_content)

func toggle():
	panel.visible = !panel.visible
	drop_zone.visible = panel.visible
	
	if panel.visible:
		$Hotbar/BackpackContainer.hide()
		$Hotbar/Spacer.hide()
	else:
		$Hotbar/BackpackContainer.show()
		$Hotbar/Spacer.show()

func update_inventory(inventory: Array):
	for i in range(12):
		for child in inventory_slots_ui[i].get_children():
			child.queue_free()
			
		if i < inventory.size():
			inventory_slots_ui[i].item_id = inventory[i]
			if inventory[i] == "ak47":
				var icon = TextureRect.new()
				icon.texture = preload("res://ak47/ak47im.png")
				icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				icon.set_anchors_preset(Control.PRESET_FULL_RECT)
				icon.offset_left = 5
				icon.offset_top = 5
				icon.offset_right = -5
				icon.offset_bottom = -5
				inventory_slots_ui[i].add_child(icon)
			else:
				var label = Label.new()
				label.text = inventory[i]
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				label.set_anchors_preset(Control.PRESET_FULL_RECT)
				inventory_slots_ui[i].add_child(label)
		else:
			inventory_slots_ui[i].item_id = ""


class InventorySlot extends ColorRect:
	var item_id: String = ""
	var slot_index: int = 0
	var inventory_ui = null
	
	func _init():
		color = Color(0.2, 0.2, 0.2, 1.0)
		
	func _get_drag_data(at_position: Vector2) -> Variant:
		if item_id == "": return null
		
		var preview = ColorRect.new()
		preview.custom_minimum_size = Vector2(100, 40)
		preview.color = Color(0.4, 0.4, 0.4, 0.8)
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
		return {"source": "inventory", "index": slot_index, "item": item_id}
		
	func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
		return typeof(data) == TYPE_DICTIONARY and data.has("item")
		
	func _drop_data(at_position: Vector2, data: Variant) -> void:
		if inventory_ui:
			inventory_ui.emit_signal("inventory_slot_swapped", data, slot_index)

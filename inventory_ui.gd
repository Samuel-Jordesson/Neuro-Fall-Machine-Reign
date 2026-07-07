extends CanvasLayer

signal item_dropped(item_id: String)
signal item_equipped(item_id: String)
signal hotbar_updated(slot_index: int, item_id: String)

@onready var item_list = $Panel/VBoxContainer/ItemList
@onready var drop_zone = $DropZone
@onready var panel = $Panel
@onready var hotbar_slots = [$Hotbar/Slot1, $Hotbar/Slot2, $Hotbar/Slot3]

func _ready():
	panel.hide()
	drop_zone.hide()
	
	drop_zone.inventory_ui = self
	
	for i in range(3):
		hotbar_slots[i].slot_index = i
		hotbar_slots[i].inventory_ui = self
		
		var lbl = Label.new()
		lbl.name = "Label"
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.text = str(i + 1)
		hotbar_slots[i].add_child(lbl)

func toggle():
	panel.visible = !panel.visible
	drop_zone.visible = panel.visible

func update_inventory(inventory: Array):
	for child in item_list.get_children():
		child.queue_free()
		
	for item in inventory:
		var slot = InventorySlot.new()
		slot.item_id = item
		slot.inventory_ui = self
		slot.custom_minimum_size = Vector2(0, 50)
		
		var label = Label.new()
		label.text = item
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		slot.add_child(label)
		
		item_list.add_child(slot)


class InventorySlot extends ColorRect:
	var item_id: String = ""
	var inventory_ui = null
	
	func _init():
		color = Color(0.2, 0.2, 0.2, 1.0)
		
	func _get_drag_data(at_position: Vector2) -> Variant:
		var preview = ColorRect.new()
		preview.custom_minimum_size = Vector2(100, 40)
		preview.color = Color(0.4, 0.4, 0.4, 0.8)
		var lbl = Label.new()
		lbl.text = item_id
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		preview.add_child(lbl)
		
		set_drag_preview(preview)
		return item_id

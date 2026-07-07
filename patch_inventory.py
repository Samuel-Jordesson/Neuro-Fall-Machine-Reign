import re

with open("inventory_ui.gd", "r") as f:
    content = f.read()

# 1. Add signals
content = content.replace(
    "signal hotbar_updated(slot_index: int, item_id: String)\nsignal item_returned_to_inventory(item_id: String)",
    "signal hotbar_updated(slot_index: int, drag_data: Dictionary)\nsignal inventory_slot_swapped(drag_data: Dictionary, to_slot: int)"
)

# 2. Add slot_index to slot_content creation
content = content.replace(
    "var slot_content = InventorySlot.new()",
    "var slot_content = InventorySlot.new()\n\t\tslot_content.slot_index = i"
)

# 3. Modify InventorySlot class
slot_class = """class InventorySlot extends ColorRect:
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
"""
content = re.sub(r'class InventorySlot extends ColorRect:.*', slot_class, content, flags=re.DOTALL)

with open("inventory_ui.gd", "w") as f:
    f.write(content)

with open("hotbar_slot.gd", "r") as f:
    content_hotbar = f.read()

# Modify hotbar_slot.gd
content_hotbar = re.sub(r'return dragged_item', 'return {"source": "hotbar", "slot": slot_index, "item": dragged_item}', content_hotbar)
content_hotbar = re.sub(r'func _can_drop_data.*', """func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
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
""", content_hotbar, flags=re.DOTALL)

with open("hotbar_slot.gd", "w") as f:
    f.write(content_hotbar)

with open("player.gd", "r") as f:
    player_content = f.read()

player_content = player_content.replace(
    'var inventory = []',
    'var inventory = ["", "", "", "", "", "", "", "", "", "", "", ""]'
)
player_content = player_content.replace(
    '$InventoryUI.item_returned_to_inventory.connect(_on_item_returned)',
    '$InventoryUI.inventory_slot_swapped.connect(_on_inventory_slot_swapped)'
)

pickup_replacement = """func _pickup_item(item):
	var item_id = item.get_item_id()
	for i in range(inventory.size()):
		if inventory[i] == "":
			inventory[i] = item_id
			if has_node("InventoryUI"):
				$InventoryUI.update_inventory(inventory)
			item.queue_free()
			return"""
player_content = re.sub(r'func _pickup_item.*?item\.queue_free\(\)', pickup_replacement, player_content, flags=re.DOTALL)

hotbar_logic = """func _on_hotbar_updated(slot_index, drag_data):
	var source = drag_data["source"]
	var item = drag_data["item"]
	
	if source == "inventory":
		var inv_idx = drag_data["index"]
		var temp = hotbar_items[slot_index]
		hotbar_items[slot_index] = item
		inventory[inv_idx] = temp
	elif source == "hotbar":
		var from_hotbar = drag_data["slot"]
		var temp = hotbar_items[slot_index]
		hotbar_items[slot_index] = item
		hotbar_items[from_hotbar] = temp
		
	update_all_ui()

func _on_inventory_slot_swapped(drag_data, to_slot):
	var source = drag_data["source"]
	var item = drag_data["item"]
	
	if source == "inventory":
		var from_slot = drag_data["index"]
		var temp = inventory[to_slot]
		inventory[to_slot] = item
		inventory[from_slot] = temp
	elif source == "hotbar":
		var from_hotbar = drag_data["slot"]
		var temp = inventory[to_slot]
		inventory[to_slot] = item
		hotbar_items[from_hotbar] = temp
		
	update_all_ui()

func update_all_ui():
	if has_node("InventoryUI"):
		$InventoryUI.update_inventory(inventory)
		for i in range(hotbar_items.size()):
			var hs = $InventoryUI.hotbar_slots[i]
			hs.item_id = hotbar_items[i]
			hs.update_visuals()"""

player_content = re.sub(r'func _on_hotbar_updated.*?update_inventory\(inventory\)', hotbar_logic, player_content, flags=re.DOTALL)

with open("player.gd", "w") as f:
    f.write(player_content)
print("patched")

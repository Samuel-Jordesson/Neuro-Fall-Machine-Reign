import re

with open("inventory_ui.tscn", "r") as f:
    content = f.read()

# Remove the old Hotbar node and its children
content = re.sub(r'\[node name="Hotbar".*?(?=\[node|\Z)', '', content, flags=re.DOTALL)

# Add StyleBoxes at the top
sub_resources = """
[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_slot"]
bg_color = Color(0.851, 0.851, 0.851, 0.48)
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 1
border_color = Color(1, 1, 1, 1)
corner_radius_top_left = 6
corner_radius_top_right = 6
corner_radius_bottom_right = 6
corner_radius_bottom_left = 6

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_circle"]
bg_color = Color(1, 1, 1, 1)
corner_radius_top_left = 24
corner_radius_top_right = 24
corner_radius_bottom_right = 24
corner_radius_bottom_left = 24

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_badge"]
bg_color = Color(1, 1, 1, 1)
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 1
border_color = Color(0.78, 0.78, 0.78, 1)
corner_radius_top_left = 10
corner_radius_top_right = 10
corner_radius_bottom_right = 10
corner_radius_bottom_left = 10
"""

# Insert subresources before the first node
parts = content.split('\n[node name="InventoryUI"')
new_content = parts[0] + "\n" + sub_resources + '\n[node name="InventoryUI"' + parts[1]

# Define new Hotbar UI
new_ui = """
[node name="Hotbar" type="HBoxContainer" parent="."]
anchors_preset = 3
anchor_left = 1.0
anchor_top = 1.0
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = -360.0
offset_top = -80.0
offset_right = -40.0
offset_bottom = -24.0
grow_horizontal = 0
grow_vertical = 0
theme_override_constants/separation = 7
alignment = 2

[node name="Slot1" type="Panel" parent="Hotbar"]
custom_minimum_size = Vector2(56, 56)
layout_mode = 2
theme_override_styles/panel = SubResource("StyleBoxFlat_slot")
script = ExtResource("3_slot")

[node name="Slot2" type="Panel" parent="Hotbar"]
custom_minimum_size = Vector2(56, 56)
layout_mode = 2
theme_override_styles/panel = SubResource("StyleBoxFlat_slot")
script = ExtResource("3_slot")

[node name="Slot3" type="Panel" parent="Hotbar"]
custom_minimum_size = Vector2(56, 56)
layout_mode = 2
theme_override_styles/panel = SubResource("StyleBoxFlat_slot")
script = ExtResource("3_slot")

[node name="Slot4" type="Panel" parent="Hotbar"]
custom_minimum_size = Vector2(56, 56)
layout_mode = 2
theme_override_styles/panel = SubResource("StyleBoxFlat_slot")
script = ExtResource("3_slot")

[node name="Spacer" type="Control" parent="Hotbar"]
custom_minimum_size = Vector2(20, 0)
layout_mode = 2

[node name="BackpackContainer" type="Control" parent="Hotbar"]
custom_minimum_size = Vector2(56, 56)
layout_mode = 2

[node name="Circle" type="Panel" parent="Hotbar/BackpackContainer"]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -23.5
offset_top = -23.5
offset_right = 23.5
offset_bottom = 23.5
grow_horizontal = 2
grow_vertical = 2
theme_override_styles/panel = SubResource("StyleBoxFlat_circle")

[node name="Icon" type="TextureRect" parent="Hotbar/BackpackContainer/Circle"]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -12.0
offset_top = -12.0
offset_right = 12.0
offset_bottom = 12.0
grow_horizontal = 2
grow_vertical = 2
expand_mode = 1
stretch_mode = 5

[node name="Badge" type="Panel" parent="Hotbar/BackpackContainer"]
layout_mode = 1
anchors_preset = 1
anchor_left = 1.0
anchor_right = 1.0
offset_left = -14.0
offset_top = 2.0
offset_right = 4.0
offset_bottom = 20.0
grow_horizontal = 0
theme_override_styles/panel = SubResource("StyleBoxFlat_badge")

[node name="Label" type="Label" parent="Hotbar/BackpackContainer/Badge"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
theme_override_colors/font_color = Color(0.635, 0.635, 0.635, 1)
theme_override_font_sizes/font_size = 12
text = "I"
horizontal_alignment = 1
vertical_alignment = 1

"""

new_content += "\n" + new_ui

with open("inventory_ui.tscn", "w") as f:
    f.write(new_content)
print("Updated inventory_ui.tscn")

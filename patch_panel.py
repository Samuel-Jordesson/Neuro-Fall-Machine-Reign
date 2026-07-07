import re

with open("inventory_ui.tscn", "r") as f:
    content = f.read()

new_panel = """[node name="Panel" type="Control" parent="."]
layout_mode = 3
anchors_preset = 11
anchor_left = 1.0
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = -613.0
grow_horizontal = 0
grow_vertical = 2

[node name="Background" type="ColorRect" parent="Panel"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
color = Color(0.376, 0.376, 0.376, 1)

[node name="Border" type="ColorRect" parent="Panel"]
layout_mode = 1
anchors_preset = 9
anchor_bottom = 1.0
offset_right = 1.0
grow_vertical = 2

[node name="HeaderIcon" type="TextureRect" parent="Panel"]
layout_mode = 0
offset_left = 75.0
offset_top = 49.0
offset_right = 99.0
offset_bottom = 73.0
expand_mode = 1
stretch_mode = 5

[node name="HeaderLabel" type="Label" parent="Panel"]
layout_mode = 0
offset_left = 108.0
offset_top = 54.0
offset_right = 176.0
offset_bottom = 77.0
theme_override_font_sizes/font_size = 12
text = "Inventario"

[node name="GridContainer" type="GridContainer" parent="Panel"]
layout_mode = 0
offset_left = 75.0
offset_top = 93.0
offset_right = 538.0
offset_bottom = 431.0
theme_override_constants/h_separation = 13
theme_override_constants/v_separation = 13
columns = 4

"""

content = re.sub(r'\[node name="Panel".*?(?=\n\[node name="Hotbar")', new_panel, content, flags=re.DOTALL)

with open("inventory_ui.tscn", "w") as f:
    f.write(content)
print("done")

import re

with open("main.tscn", "r") as f:
    content = f.read()

# Add a GrapplePoint Node
grapple_node = """
[node name="GrapplePoint" type="StaticBody3D" parent="." groups=["grapple_point"]]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 10, -10)
collision_layer = 1
collision_mask = 1

[node name="CollisionShape3D" type="CollisionShape3D" parent="GrapplePoint"]
shape = SubResource("BoxShape3D_grapple")

[node name="MeshInstance3D" type="MeshInstance3D" parent="GrapplePoint"]
mesh = SubResource("BoxMesh_grapple")
"""

sub_res = """
[sub_resource type="BoxShape3D" id="BoxShape3D_grapple"]
size = Vector3(2, 2, 2)

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_grapple"]
albedo_color = Color(1, 0.5, 0, 1)

[sub_resource type="BoxMesh" id="BoxMesh_grapple"]
material = SubResource("StandardMaterial3D_grapple")
size = Vector3(2, 2, 2)
"""

idx = content.find("[node name=\"Main\"")
if idx != -1:
    content = content[:idx] + sub_res + "\n" + content[idx:]
else:
    print("WARNING: Could not find [node name=\"Main\"")

content += grapple_node

with open("main.tscn", "w") as f:
    f.write(content)

print("done")

@tool
extends Path3D

@export var road_scene: PackedScene
@export var mesh_length_override: float = 0.0:
	set(val):
		mesh_length_override = max(0.0, val)
		if is_inside_tree(): _update_road()

@export_enum("X", "Y", "Z") var forward_axis: int = 2:
	set(val):
		forward_axis = val
		if is_inside_tree(): _update_road()

@export var rebuild: bool = false:
	set(val):
		if is_inside_tree(): _update_road()

func _ready():
	if not curve_changed.is_connected(_update_road):
		curve_changed.connect(_update_road)
	call_deferred("_update_road")

func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D: return node
	for child in node.get_children():
		var res = _find_mesh_instance(child)
		if res: return res
	return null

func _update_road():
	if not road_scene or curve == null: return
	
	var container = get_node_or_null("RoadMesh")
	if container:
		container.name = "RoadMesh_Old"
		container.queue_free()
		
	container = MeshInstance3D.new()
	container.name = "RoadMesh"
	add_child(container)
	
	var temp_scene = road_scene.instantiate()
	var mi = _find_mesh_instance(temp_scene)
	if not mi or not mi.mesh:
		temp_scene.queue_free()
		return
		
	var src_mesh = mi.mesh
	var aabb = src_mesh.get_aabb()
	
	var mesh_length = mesh_length_override
	if mesh_length <= 0.0:
		if forward_axis == 0: mesh_length = aabb.size.x
		elif forward_axis == 1: mesh_length = aabb.size.y
		else: mesh_length = aabb.size.z
		
	if mesh_length <= 0.1:
		temp_scene.queue_free()
		return
		
	var curve_len = curve.get_baked_length()
	var num_segments = max(1, int(curve_len / mesh_length))
	
	if num_segments > 500:
		print("Too many segments! Increase mesh length.")
		temp_scene.queue_free()
		return
	
	var out_mesh = ArrayMesh.new()
	
	for surf_idx in range(src_mesh.get_surface_count()):
		var mdt = MeshDataTool.new()
		mdt.create_from_surface(src_mesh, surf_idx)
		
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		
		var vert_count = mdt.get_vertex_count()
		
		for seg in range(num_segments):
			var seg_start_d = seg * mesh_length
			var idx_offset = seg * vert_count
			
			for v_idx in range(vert_count):
				var v = mdt.get_vertex(v_idx)
				var n = mdt.get_vertex_normal(v_idx)
				var uv = mdt.get_vertex_uv(v_idx)
				
				var percent = 0.0
				var offset = Vector3.ZERO
				var normal_offset = Vector3.ZERO
				
				if forward_axis == 0:
					percent = (v.x - aabb.position.x) / aabb.size.x
					offset = Vector3(0, v.y, v.z)
					normal_offset = Vector3(0, n.y, n.z)
				elif forward_axis == 1:
					percent = (v.y - aabb.position.y) / aabb.size.y
					offset = Vector3(v.x, 0, v.z)
					normal_offset = Vector3(n.x, 0, n.z)
				else:
					percent = (v.z - aabb.position.z) / aabb.size.z
					offset = Vector3(v.x, v.y, 0)
					normal_offset = Vector3(n.x, n.y, 0)
					
				var local_d = percent * mesh_length
				var d = seg_start_d + local_d
				d = clamp(d, 0.0, curve_len)
				
				var pos = curve.sample_baked(d)
				var forward = Vector3.FORWARD
				var next_pos = curve.sample_baked(min(d + 0.1, curve_len))
				if pos.distance_to(next_pos) > 0.001:
					forward = (pos - next_pos).normalized()
					
				var up = curve.sample_baked_up_vector(d).normalized()
				var right = Vector3.RIGHT
				if up.cross(forward).length() > 0.001:
					right = forward.cross(up).normalized()
					up = right.cross(forward).normalized()
				
				var basis = Basis()
				if forward_axis == 0:
					basis = Basis(forward, up, right)
				elif forward_axis == 1:
					basis = Basis(right, forward, up)
				else:
					basis = Basis(right, up, forward)
					
				var final_pos = pos + (basis * offset)
				var final_normal = (basis * normal_offset).normalized()
				
				st.set_uv(uv)
				st.set_normal(final_normal)
				st.add_vertex(final_pos)
				
			for f_idx in range(mdt.get_face_count()):
				st.add_index(mdt.get_face_vertex(f_idx, 0) + idx_offset)
				st.add_index(mdt.get_face_vertex(f_idx, 1) + idx_offset)
				st.add_index(mdt.get_face_vertex(f_idx, 2) + idx_offset)
				
		st.commit(out_mesh)
		
		var mat = src_mesh.surface_get_material(surf_idx)
		if mat == null and mi.get_surface_override_material(surf_idx):
			mat = mi.get_surface_override_material(surf_idx)
		out_mesh.surface_set_material(surf_idx, mat)
		
	container.mesh = out_mesh
	container.create_trimesh_collision()
	
	temp_scene.queue_free()

import re

with open("player.gd", "r") as f:
    content = f.read()

# 1. Add variables
var_block = """
var inventory = ["", "", "", "", "", "", "", "", "", "", "", ""]
var hotbar_items = ["", "", "", ""]
var active_slot = -1
var is_armed = false

var is_grappling = false
var grapple_point = Vector3.ZERO
var rope_length = 0.0
var grapple_equipped = false
var rope_mesh: MeshInstance3D = null
"""
content = re.sub(r'var inventory = .*?var is_armed = false', var_block, content, flags=re.DOTALL)

# 2. Add input 'grapple_equip' -> KEY_Q
input_block = """
		"hotbar_4": KEY_4,
		"grapple_equip": KEY_Q
	}
"""
content = content.replace('"hotbar_4": KEY_4\n\t}', input_block)

# 3. Modify _physics_process to handle pendulum
physics_start = content.find("func _physics_process(delta):")
physics_end = content.find("func _process(delta):")
physics_block = content[physics_start:physics_end]

new_physics = """func _physics_process(delta):
	if is_grappling:
		# Pendulum physics
		var player_pos = global_position + Vector3(0, 1, 0)
		var rope_vec = player_pos - grapple_point
		var current_dist = rope_vec.length()
		var rope_dir = rope_vec.normalized()
		
		# Reel in/out
		if Input.is_action_pressed("ui_up"):
			rope_length = max(2.0, rope_length - 10.0 * delta)
		if Input.is_action_pressed("ui_down"):
			rope_length += 10.0 * delta
			
		velocity.y -= gravity * delta
		
		# WASD swing force
		var input_dir = Input.get_vector("left", "right", "forward", "backward")
		if input_dir != Vector2.ZERO:
			var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
			velocity += direction * 20.0 * delta
		
		if current_dist > rope_length:
			var target_pos = grapple_point + rope_dir * rope_length
			var correction = target_pos - player_pos
			global_position += correction
			
			var v_dot = velocity.dot(rope_dir)
			if v_dot > 0:
				velocity -= rope_dir * v_dot
				
		move_and_slide()
		
		_update_rope_visual()
		
		if Input.is_action_just_pressed("grapple_equip"):
			is_grappling = false
			grapple_equipped = false
			if rope_mesh:
				rope_mesh.queue_free()
				rope_mesh = null
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	var input_dir = Input.get_vector("left", "right", "forward", "backward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var target_speed = 0.0
	if is_on_floor():
		if Input.is_action_just_pressed("ui_accept"):
			velocity.y = JUMP_VELOCITY
		
		if direction:
			target_speed = RUN_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
		
		velocity.x = lerp(velocity.x, direction.x * target_speed, 10.0 * delta)
		velocity.z = lerp(velocity.z, direction.z * target_speed, 10.0 * delta)
	else:
		if direction:
			velocity.x = lerp(velocity.x, direction.x * WALK_SPEED, 2.0 * delta)
			velocity.z = lerp(velocity.z, direction.z * WALK_SPEED, 2.0 * delta)
			
	move_and_slide()
	
	_update_animations(target_speed)
	_update_rotation(delta)
"""
content = content[:physics_start] + new_physics + "\n" + content[physics_end:]

# 4. Modify _process(delta) to handle equipping/shooting grapple
process_end = content.find("func _shoot():")

# Replace Input.is_action_just_pressed("shoot") inside _process
shoot_code = """
	if Input.is_action_just_pressed("grapple_equip"):
		grapple_equipped = !grapple_equipped
		if is_grappling:
			is_grappling = false
			grapple_equipped = false
			if rope_mesh:
				rope_mesh.queue_free()
				rope_mesh = null
				
	if Input.is_action_just_pressed("shoot"):
		if grapple_equipped and not is_grappling:
			_shoot_grapple()
		elif is_armed:
			_shoot()
"""
content = re.sub(r'if Input\.is_action_just_pressed\("shoot"\) and is_armed:\n\t\t_shoot\(\)', shoot_code, content)


# 5. Add grapple functions
grapple_functions = """
func _shoot_grapple():
	var space_state = get_world_3d().direct_space_state
	var camera = get_viewport().get_camera_3d()
	var mouse_pos = get_viewport().get_mouse_position()
	var origin = camera.project_ray_origin(mouse_pos)
	var end = origin + camera.project_ray_normal(mouse_pos) * 100.0
	
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	var result = space_state.intersect_ray(query)
	
	if result and result.collider and result.collider.is_in_group("grapple_point"):
		grapple_point = result.position
		var player_pos = global_position + Vector3(0, 1, 0)
		rope_length = player_pos.distance_to(grapple_point)
		is_grappling = true
		
		# Create rope mesh
		rope_mesh = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = 0.05
		cyl.bottom_radius = 0.05
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.2, 0.2)
		cyl.material = mat
		rope_mesh.mesh = cyl
		get_tree().root.add_child(rope_mesh)

func _update_rope_visual():
	if not rope_mesh: return
	var player_pos = global_position + Vector3(0, 1, 0)
	var mid_point = (player_pos + grapple_point) / 2.0
	var rope_vec = grapple_point - player_pos
	var dist = rope_vec.length()
	
	rope_mesh.global_position = mid_point
	rope_mesh.mesh.height = dist
	
	# Look at to align cylinder
	var up = Vector3.UP
	if abs(rope_vec.normalized().y) > 0.99:
		up = Vector3.RIGHT
	rope_mesh.look_at_from_position(mid_point, grapple_point, up)
	rope_mesh.rotation_degrees.x -= 90 # Cylinder is Y-up, we need Z-forward
"""

content = content + "\n" + grapple_functions

with open("player.gd", "w") as f:
    f.write(content)
print("done")

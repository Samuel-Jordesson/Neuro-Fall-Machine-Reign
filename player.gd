extends CharacterBody3D

const SPEED = 5.0
const ACCELERATION = 20.0
const ROTATION_SPEED = 10.0

@onready var visual = $Visual
var anim_player : AnimationPlayer

var inventory = []
var hotbar_items = ["", "", ""]
var active_slot = -1
var is_armed = false

@onready var pickup_radius = $PickupRadius
@onready var prompt_label = $PromptLabel
@onready var weapon_slot = $Visual/WeaponSlot
@onready var shoot_ray = $Visual/ShootRay

@export_group("Configuração da Arma (Na Mão)")
@export var pos_arma: Vector3 = Vector3(0, 0, 0)
@export var rot_arma: Vector3 = Vector3(0, 0, 0)

var interactable_target = null
var current_vehicle = null
var current_aim_target = Vector3.ZERO
var walk_particles: GPUParticles3D

func _ready():
	var inputs = {
		"move_up": KEY_W,
		"move_down": KEY_S,
		"move_left": KEY_A,
		"move_right": KEY_D,
		"interact": KEY_E,
		"inventory": KEY_I,
		"hotbar_1": KEY_1,
		"hotbar_2": KEY_2,
		"hotbar_3": KEY_3
	}
	for action in inputs:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var ev = InputEventKey.new()
		ev.physical_keycode = inputs[action]
		InputMap.action_add_event(action, ev)
		
	if not InputMap.has_action("shoot"):
		InputMap.add_action("shoot")
		var mouse_ev = InputEventMouseButton.new()
		mouse_ev.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("shoot", mouse_ev)
		
	if has_node("PromptLabel"):
		prompt_label.top_level = true
		
	setup_animations()
	
	if has_node("InventoryUI"):
		$InventoryUI.item_dropped.connect(_on_item_dropped)
		$InventoryUI.hotbar_updated.connect(_on_hotbar_updated)
		
	_setup_walk_particles()
		
	call_deferred("_setup_bone_attachment")

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for c in node.get_children():
		var skel = _find_skeleton(c)
		if skel: return skel
	return null

func _setup_walk_particles():
	walk_particles = GPUParticles3D.new()
	walk_particles.emitting = false
	walk_particles.amount = 15
	walk_particles.lifetime = 0.5
	walk_particles.one_shot = false
	
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.3
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 40.0
	mat.initial_velocity_min = 0.2
	mat.initial_velocity_max = 0.8
	mat.gravity = Vector3(0, 0.5, 0)
	mat.scale_min = 0.1
	mat.scale_max = 0.3
	
	var grad = Gradient.new()
	grad.add_point(0.0, Color(0.8, 0.8, 0.8, 0.6))
	grad.add_point(1.0, Color(0.8, 0.8, 0.8, 0.0))
	var grad_tex = GradientTexture1D.new()
	grad_tex.gradient = grad
	mat.color_ramp = grad_tex
	
	walk_particles.process_material = mat
	
	var sphere = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	var pmat = StandardMaterial3D.new()
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.vertex_color_use_as_albedo = true
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = pmat
	
	walk_particles.draw_pass_1 = sphere
	
	add_child(walk_particles)
	walk_particles.position = Vector3(0, 0.1, 0)

func _setup_bone_attachment():
	var skeleton = _find_skeleton(visual)
	if skeleton:
		var hand_bone_name = ""
		for i in range(skeleton.get_bone_count()):
			var b_name = skeleton.get_bone_name(i).to_lower()
			if "righthand" in b_name or "hand_r" in b_name or "hand.r" in b_name:
				hand_bone_name = skeleton.get_bone_name(i)
				break
				
		if hand_bone_name != "":
			var attachment = BoneAttachment3D.new()
			attachment.bone_name = hand_bone_name
			skeleton.add_child(attachment)
			
			weapon_slot.get_parent().remove_child(weapon_slot)
			attachment.add_child(weapon_slot)
			weapon_slot.transform = Transform3D()

func _find_ap(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer: return node
	for c in node.get_children():
		var ap = _find_ap(c)
		if ap: return ap
	return null

func setup_animations():
	anim_player = _find_ap(visual)
	if not anim_player:
		print("No AnimationPlayer found in visual!")
		return
		
	var idle_anim = get_first_animation(anim_player)
	if idle_anim:
		idle_anim = idle_anim.duplicate()
		idle_anim.loop_mode = Animation.LOOP_LINEAR
		add_animation_to_player(anim_player, "Idle", idle_anim)
		
	var running_scene = load("res://flavio/Running.fbx").instantiate()
	var running_ap = _find_ap(running_scene)
	if running_ap:
		var anim = get_first_animation(running_ap)
		if anim:
			anim = anim.duplicate()
			anim.loop_mode = Animation.LOOP_LINEAR
			add_animation_to_player(anim_player, "Run", anim)
	running_scene.queue_free()
	
	var armed_idle_scene = load("res://flavio/Rifle Aiming Idle.fbx").instantiate()
	var armed_idle_ap = _find_ap(armed_idle_scene)
	if armed_idle_ap:
		var anim = get_first_animation(armed_idle_ap)
		if anim:
			anim = anim.duplicate()
			anim.loop_mode = Animation.LOOP_LINEAR
			add_animation_to_player(anim_player, "ArmedIdle", anim)
	armed_idle_scene.queue_free()
	
	var armed_run_scene = load("res://flavio/Run Forward.fbx").instantiate()
	var armed_run_ap = _find_ap(armed_run_scene)
	if armed_run_ap:
		var anim = get_first_animation(armed_run_ap)
		if anim:
			anim = anim.duplicate()
			anim.loop_mode = Animation.LOOP_LINEAR
			add_animation_to_player(anim_player, "ArmedRun", anim)
	armed_run_scene.queue_free()
	
	if anim_player.has_animation("Idle"):
		anim_player.play("Idle")

func get_first_animation(ap: AnimationPlayer) -> Animation:
	for lib_name in ap.get_animation_library_list():
		var lib = ap.get_animation_library(lib_name)
		for anim_name in lib.get_animation_list():
			return lib.get_animation(anim_name)
	return null
	
func add_animation_to_player(ap: AnimationPlayer, anim_name: String, anim: Animation):
	for i in range(anim.get_track_count()):
		var path_str = str(anim.track_get_path(i)).to_lower()
		if anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			if "hips" in path_str or "root" in path_str or "pelvis" in path_str:
				var start_pos = anim.track_get_key_value(i, 0) if anim.track_get_key_count(i) > 0 else Vector3.ZERO
				for key_idx in range(anim.track_get_key_count(i)):
					var pos = anim.track_get_key_value(i, key_idx)
					anim.track_set_key_value(i, key_idx, Vector3(start_pos.x, pos.y, start_pos.z))

	var lib_name = ""
	var lib: AnimationLibrary
	if ap.has_animation_library(lib_name):
		lib = ap.get_animation_library(lib_name)
	else:
		lib = AnimationLibrary.new()
		ap.add_animation_library(lib_name, lib)
		
	if lib.has_animation(anim_name):
		lib.remove_animation(anim_name)
	lib.add_animation(anim_name, anim)


func _process(delta):
	interactable_target = null
	prompt_label.hide()
	
	if not has_node("PickupRadius"): return
	
	var areas = pickup_radius.get_overlapping_areas()
	for area in areas:
		var parent = area.get_parent()
		if parent.is_in_group("interactable"):
			interactable_target = parent
			prompt_label.text = parent.get_interaction_text()
			prompt_label.global_position = parent.global_position + Vector3(0, 1.5, 0)
			prompt_label.show()
			break
			
	if Input.is_action_just_pressed("interact") and interactable_target:
		if interactable_target.has_method("interact"):
			interactable_target.interact(self)
		elif interactable_target.has_method("get_item_id"):
			_pickup_item(interactable_target)
		
	if Input.is_action_just_pressed("inventory"):
		if has_node("InventoryUI"):
			$InventoryUI.toggle()
			
	if Input.is_action_just_pressed("hotbar_1"): _toggle_slot(0)
	if Input.is_action_just_pressed("hotbar_2"): _toggle_slot(1)
	if Input.is_action_just_pressed("hotbar_3"): _toggle_slot(2)
	
	if Input.is_action_just_pressed("shoot") and is_armed:
		_shoot()
		
	if is_armed and weapon_slot.get_child_count() > 0:
		var w = weapon_slot.get_child(0)
		w.position = pos_arma
		w.rotation_degrees = rot_arma

func _shoot():
	print("POW! Tiros disparados!")
	
	var start_pos = global_position + Vector3(0, 1.2, 0)
	if is_armed and weapon_slot.get_child_count() > 0:
		start_pos = weapon_slot.get_child(0).global_position
		
	var end_pos = current_aim_target
	if end_pos == Vector3.ZERO:
		end_pos = (global_position + Vector3(0, 1.2, 0)) + (visual.transform.basis * Vector3(0, 0, 50))
		if shoot_ray and shoot_ray.is_colliding():
			end_pos = shoot_ray.get_collision_point()
		
	var bullet_script = preload("res://bullet.gd")
	var bullet = bullet_script.new()
	
	# Adiciona o projétil à cena raiz
	get_tree().root.add_child(bullet)
	
	# Define a posição e direção
	bullet.global_position = start_pos
	bullet.direction = (end_pos - start_pos).normalized()
	
	# Opcional: Efeito sonoro, recuo, etc, podem entrar aqui

func _toggle_slot(idx):
	if active_slot == idx:
		active_slot = -1
		is_armed = false
		for child in weapon_slot.get_children():
			child.queue_free()
	else:
		var item = hotbar_items[idx]
		if item != "":
			active_slot = idx
			is_armed = true
			_equip_item(item)

func _on_hotbar_updated(slot_index, item_id):
	hotbar_items[slot_index] = item_id

func _pickup_item(item):
	var item_id = item.get_item_id()
	inventory.append(item_id)
	if has_node("InventoryUI"):
		$InventoryUI.update_inventory(inventory)
	item.queue_free()

func _equip_item(item_id):
	for child in weapon_slot.get_children():
		child.queue_free()
		
	if item_id == "ak47":
		var ak = load("res://ak47/Meshy_AI_AK_47_with_wooden_sto_0706200409_texture.fbx").instantiate()
		ak.position = pos_arma
		ak.rotation_degrees = rot_arma
		weapon_slot.add_child(ak)

func _on_item_dropped(item_id):
	inventory.erase(item_id)
	if has_node("InventoryUI"):
		$InventoryUI.update_inventory(inventory)
		
	if item_id == "ak47":
		var pickup = load("res://ak47_pickup.tscn").instantiate()
		get_parent().add_child(pickup)
		pickup.rotation.y = visual.rotation.y
		pickup.rotation_degrees.x = -90.4
		var forward = Vector3(0, 0, -1.5).rotated(Vector3.UP, visual.rotation.y)
		pickup.global_position = global_position + forward
		pickup.global_position.y = global_position.y
		
	# If we dropped our active weapon
	if active_slot != -1 and hotbar_items[active_slot] == item_id:
		# Check if we still have one in inventory to keep equipped
		if not inventory.has(item_id):
			hotbar_items[active_slot] = ""
			if has_node("InventoryUI"):
				var lbl = $InventoryUI.get_node("Hotbar/Slot" + str(active_slot + 1) + "/Label")
				if lbl: lbl.text = str(active_slot + 1)
			_toggle_slot(active_slot) # unequip

func _physics_process(delta):
	if not is_on_floor():
		velocity.y -= 9.8 * delta
		
	current_aim_target = Vector3.ZERO
	if is_armed:
		var camera = get_viewport().get_camera_3d()
		if camera:
			var mouse_pos = get_viewport().get_mouse_position()
			var ray_origin = camera.project_ray_origin(mouse_pos)
			var ray_dir = camera.project_ray_normal(mouse_pos)
			
			var space_state = get_world_3d().direct_space_state
			var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 1000)
			query.exclude = [self.get_rid()]
			
			var result = space_state.intersect_ray(query)
			if result:
				current_aim_target = result.position
			else:
				var plane = Plane(Vector3.UP, global_position.y)
				var intersection = plane.intersects_ray(ray_origin, ray_dir)
				if intersection != null:
					current_aim_target = intersection
					
			if current_aim_target != Vector3.ZERO:
				var look_dir = current_aim_target - global_position
				look_dir.y = 0
				if look_dir.length_squared() > 0.001:
					var target_rotation = atan2(look_dir.x, look_dir.z)
					visual.rotation.y = lerp_angle(visual.rotation.y, target_rotation, ROTATION_SPEED * 1.5 * delta)
					
	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction.length() > 0:
		velocity.x = move_toward(velocity.x, direction.x * SPEED, ACCELERATION * delta)
		velocity.z = move_toward(velocity.z, direction.z * SPEED, ACCELERATION * delta)
		
		if not is_armed:
			var target_rotation = atan2(direction.x, direction.z)
			visual.rotation.y = lerp_angle(visual.rotation.y, target_rotation, ROTATION_SPEED * delta)
		
		var run_anim = "ArmedRun" if is_armed else "Run"
		if anim_player and anim_player.has_animation(run_anim) and anim_player.current_animation != run_anim:
			anim_player.play(run_anim, 0.2)
	else:
		velocity.x = move_toward(velocity.x, 0, ACCELERATION * delta)
		velocity.z = move_toward(velocity.z, 0, ACCELERATION * delta)
		
		var idle_anim = "ArmedIdle" if is_armed else "Idle"
		if anim_player and anim_player.has_animation(idle_anim) and anim_player.current_animation != idle_anim:
			anim_player.play(idle_anim, 0.2)
			
	if walk_particles:
		var is_walking = velocity.length() > 0.5 and is_on_floor()
		walk_particles.emitting = is_walking
			
	move_and_slide()

func enter_vehicle(vehicle):
	current_vehicle = vehicle
	process_mode = Node.PROCESS_MODE_DISABLED
	hide()
	$CameraArm/Camera3D.current = false

func exit_vehicle(pos: Vector3):
	current_vehicle = null
	global_position = pos
	process_mode = Node.PROCESS_MODE_INHERIT
	show()
	$CameraArm/Camera3D.current = true

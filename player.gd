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
		
	call_deferred("_setup_bone_attachment")

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for c in node.get_children():
		var skel = _find_skeleton(c)
		if skel: return skel
	return null

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
		
	var end_pos = (global_position + Vector3(0, 1.2, 0)) + (visual.transform.basis * Vector3(0, 0, 50))
	
	if shoot_ray and shoot_ray.is_colliding():
		var hit_obj = shoot_ray.get_collider()
		print("Acertou: ", hit_obj.name)
		end_pos = shoot_ray.get_collision_point()
		
	var tracer = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.02
	cylinder.bottom_radius = 0.02
	cylinder.height = start_pos.distance_to(end_pos)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 0)
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 0)
	cylinder.material = mat
	tracer.mesh = cylinder
	
	get_tree().root.add_child(tracer)
	tracer.global_position = (start_pos + end_pos) / 2.0
	tracer.look_at_from_position(tracer.global_position, end_pos, Vector3.UP)
	tracer.rotate_object_local(Vector3.RIGHT, PI/2)
	
	get_tree().create_timer(0.05).timeout.connect(tracer.queue_free)

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
		
	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction.length() > 0:
		velocity.x = move_toward(velocity.x, direction.x * SPEED, ACCELERATION * delta)
		velocity.z = move_toward(velocity.z, direction.z * SPEED, ACCELERATION * delta)
		
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

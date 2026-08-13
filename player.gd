extends CharacterBody3D

const SPEED = 5.0
const ACCELERATION = 20.0
const ROTATION_SPEED = 10.0

@onready var visual = $Visual
var anim_player : AnimationPlayer

var inventory = ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]
var backpack_item = ""
var backpack_node: Node3D = null
var hotbar_items = ["", "", "", ""]
var active_slot = -1
var is_armed = false
var is_punching = false

var is_grappling = false
var grapple_point = Vector3.ZERO
var rope_length = 0.0
var grapple_equipped = false
var rope_mesh: MeshInstance3D = null

@onready var pickup_radius = $PickupRadius
@onready var prompt_label = $PromptLabel
@onready var weapon_slot = $Visual/WeaponSlot
@onready var shoot_ray = $Visual/ShootRay

var my_skeleton: Skeleton3D = null
var arm_bone_names: Array[StringName] = []
var was_on_floor: bool = true

@export_group("Configuração da Arma (Na Mão)")
@export var pos_arma: Vector3 = Vector3(0, 0, 0)
@export var rot_arma: Vector3 = Vector3(0, 0, 0)
@export var scale_arma: Vector3 = Vector3(1, 1, 1)

@export_group("Configuração da Mochila (Costas)")
@export var pos_mochila: Vector3 = Vector3(0, 0, -0.2):
	set(value):
		pos_mochila = value
		if backpack_node and backpack_node.get_child_count() > 0:
			backpack_node.get_child(0).position = value

@export var rot_mochila: Vector3 = Vector3(0, 180, 0):
	set(value):
		rot_mochila = value
		if backpack_node and backpack_node.get_child_count() > 0:
			backpack_node.get_child(0).rotation_degrees = value

@export var scale_mochila: Vector3 = Vector3(1, 1, 1):
	set(value):
		scale_mochila = value
		if backpack_node and backpack_node.get_child_count() > 0:
			backpack_node.get_child(0).scale = value

@export_group("Água")
## Velocidade nadando, bem menor que andando.
@export var swim_speed := 2.6
## Velocidade subindo/descendo na água (Espaço sobe).
@export var swim_vertical_speed := 3.0
## Quanto o empuxo puxa o corpo de volta pra linha d'água.
@export var buoyancy := 5.0
## Profundidade do pé em que o personagem deixa de andar e começa a nadar.
@export var swim_depth := 1.2
## Profundidade em que o empuxo estabiliza o corpo boiando. Menor = boia mais
## alto. É isto que decide onde a linha d'água corta o personagem, não o
## swim_depth acima.
@export var float_depth := 0.55
## Metros percorridos entre um anel de rastro e o próximo.
@export var ripple_spacing := 0.55
## Braçadas por segundo nadando pra frente.
@export var swim_stroke_speed := 1.1
## Ritmo mais lento de quando está só boiando parado.
@export var swim_tread_speed := 0.55
## Inclinação do corpo ao nadar, em graus (0 = boiando em pé, 90 = deitado).
@export var swim_pitch_degrees := 72.0
## Inverte o sentido da braçada, caso o rig fique nadando de costas.
@export var swim_stroke_inverted := false

var interactable_target = null
var current_vehicle = null
var current_aim_target = Vector3.ZERO
var walk_particles: GPUParticles3D
var splash_particles: GPUParticles3D

# --- estado da água ---
var water_body: Node3D = null
var water_depth := -999.0
var is_in_water := false
var is_swimming := false
var _ripple_travel := 0.0
var _last_ripple_pos := Vector3.ZERO
var _swim_time := 0.0
## 0 = fora d'água, 1 = pose de natação aplicada por inteiro.
var _swim_blend := 0.0
## 0 = boiando parado, 1 = nadando pra frente.
var _swim_move_blend := 0.0

# Ossos usados pela natação procedural. -1 = não encontrado no rig.
var _swim_bones := {}

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
		"hotbar_3": KEY_3,
		"hotbar_4": KEY_4,
		"grapple_equip": KEY_Q,
		"grapple_action": KEY_K
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
		$InventoryUI.inventory_slot_swapped.connect(_on_inventory_slot_swapped)
		
	_setup_walk_particles()
	_setup_splash_particles()

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

func _setup_splash_particles():
	# Respingos que saem na linha d'agua quando o personagem se mexe na agua.
	splash_particles = GPUParticles3D.new()
	splash_particles.emitting = false
	splash_particles.amount = 24
	splash_particles.lifetime = 0.7
	splash_particles.local_coords = false

	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.35
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 35.0
	mat.initial_velocity_min = 1.5
	mat.initial_velocity_max = 3.5
	mat.gravity = Vector3(0, -9.0, 0)
	mat.scale_min = 0.04
	mat.scale_max = 0.12
	mat.damping_min = 0.5
	mat.damping_max = 1.5

	var grad = Gradient.new()
	grad.add_point(0.0, Color(0.85, 0.95, 1.0, 0.9))
	grad.add_point(0.6, Color(0.7, 0.9, 1.0, 0.6))
	grad.add_point(1.0, Color(0.7, 0.9, 1.0, 0.0))
	var grad_tex = GradientTexture1D.new()
	grad_tex.gradient = grad
	mat.color_ramp = grad_tex

	splash_particles.process_material = mat

	var sphere = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 6
	sphere.rings = 3
	var pmat = StandardMaterial3D.new()
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.vertex_color_use_as_albedo = true
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = pmat

	splash_particles.draw_pass_1 = sphere
	splash_particles.top_level = true
	add_child(splash_particles)

func _setup_bone_attachment():
	my_skeleton = _find_skeleton(visual)
	if my_skeleton:
		for i in range(my_skeleton.get_bone_count()):
			var b_name = my_skeleton.get_bone_name(i).to_lower()
			if "arm" in b_name or "hand" in b_name or "shoulder" in b_name:
				arm_bone_names.append(my_skeleton.get_bone_name(i))
				
		var hand_bone_name = ""
		for i in range(my_skeleton.get_bone_count()):
			var b_name = my_skeleton.get_bone_name(i).to_lower()
			if "righthand" in b_name or "hand_r" in b_name or "hand.r" in b_name:
				hand_bone_name = my_skeleton.get_bone_name(i)
				break
				
		if hand_bone_name != "":
			var attachment = BoneAttachment3D.new()
			attachment.bone_name = hand_bone_name
			my_skeleton.add_child(attachment)
			
			weapon_slot.get_parent().remove_child(weapon_slot)
			attachment.add_child(weapon_slot)
			weapon_slot.transform = Transform3D()
			
		var spine_bone_name = ""
		for i in range(my_skeleton.get_bone_count()):
			var b_name = my_skeleton.get_bone_name(i).to_lower()
			if "spine" in b_name or "chest" in b_name or "back" in b_name:
				spine_bone_name = my_skeleton.get_bone_name(i)
				if "spine2" in b_name or "spine.002" in b_name or "spine1" in b_name:
					break
					
		if spine_bone_name != "":
			var bp_attachment = BoneAttachment3D.new()
			bp_attachment.bone_name = spine_bone_name
			my_skeleton.add_child(bp_attachment)
			
			backpack_node = Node3D.new()
			bp_attachment.add_child(backpack_node)

	_find_swim_bones()

# --- natação procedural -------------------------------------------------------

## Acha os ossos da braçada por nome aproximado, do mesmo jeito que o resto do
## arquivo faz, pra funcionar mesmo se o rig for reexportado com outro prefixo.
func _find_swim_bones():
	_swim_bones.clear()
	if not my_skeleton:
		return

	# "todas estas palavras" e "nenhuma destas", pra nao confundir
	# LeftArm com LeftForeArm nem LeftUpLeg com LeftLeg.
	var wanted := {
		"hips":       [["hips"], ["upleg"]],
		"spine":      [["spine1"], []],
		"l_arm":      [["left", "arm"], ["fore", "lower", "hand"]],
		"r_arm":      [["right", "arm"], ["fore", "lower", "hand"]],
		"l_forearm":  [["left", "forearm"], ["hand"]],
		"r_forearm":  [["right", "forearm"], ["hand"]],
		"l_upleg":    [["left", "upleg"], []],
		"r_upleg":    [["right", "upleg"], []],
		"l_leg":      [["left", "leg"], ["upleg"]],
		"r_leg":      [["right", "leg"], ["upleg"]],
	}

	for key in wanted:
		var must: Array = wanted[key][0]
		var must_not: Array = wanted[key][1]
		_swim_bones[key] = _find_bone(must, must_not)

func _find_bone(must: Array, must_not: Array) -> int:
	for i in range(my_skeleton.get_bone_count()):
		var n := my_skeleton.get_bone_name(i).to_lower()
		var ok := true
		for m in must:
			if not (m in n):
				ok = false
				break
		if ok:
			for m in must_not:
				if m in n:
					ok = false
					break
		if ok:
			return i
	return -1

## Aponta um osso para uma direção dada em espaço do corpo
## (X = esquerda, Y = cima, Z = frente do personagem).
##
## Girar em torno de um eixo fixo não serve aqui: o rig está em T-pose, então o
## braço já aponta pro lado e girar no eixo lateral só torceria o osso no lugar.
## Apontar resolve isso e ainda fica independente de como o rig foi orientado —
## a direção de repouso vem do próprio esqueleto.
func _point_bone(key: String, body_dir: Vector3, weight: float) -> void:
	var idx: int = _swim_bones.get(key, -1)
	if idx < 0 or weight <= 0.001:
		return

	var g_rest := my_skeleton.get_bone_global_rest(idx)
	# Todo osso deste rig aponta pelo próprio +Y local (verificado no esqueleto).
	var rest_dir: Vector3 = (g_rest.basis * Vector3.UP).normalized()
	var target := body_dir.normalized()
	if rest_dir.length_squared() < 0.5 or target.length_squared() < 0.5:
		return

	# Rotação mínima que leva a direção de repouso até a direção pedida.
	var q := Quaternion(rest_dir, target)
	q = Quaternion.IDENTITY.slerp(q, clampf(weight, 0.0, 1.0))

	var desired_global := Basis(q) * g_rest.basis
	var parent := my_skeleton.get_bone_parent(idx)
	var parent_basis := Basis()
	if parent >= 0:
		# Repouso do pai (e não a pose atual) pra não depender da ordem em que
		# os ossos são escritos neste frame.
		parent_basis = my_skeleton.get_bone_global_rest(parent).basis
	var local := parent_basis.inverse() * desired_global
	my_skeleton.set_bone_pose_rotation(idx, local.get_rotation_quaternion())

## Deita o corpo na água e toca a braçada. Roda em _process (e não em
## _physics_process) porque precisa acontecer depois do AnimationPlayer, senão a
## animação sobrescreve os ossos que a braçada acabou de posicionar.
func _update_swim_visual(delta: float) -> void:
	if not visual:
		return

	# Enquanto nada, o AnimationPlayer fica pausado pra não brigar com a pose.
	if anim_player:
		if is_swimming and anim_player.is_playing():
			anim_player.pause()
		elif not is_swimming and not anim_player.is_playing() and _swim_blend <= 0.001:
			var resume := "ArmedIdle" if (is_armed or grapple_equipped) else "Idle"
			if anim_player.has_animation(resume):
				anim_player.play(resume, 0.2)

	# Só deita o corpo quando está de fato se deslocando. Boiando parado ele
	# fica em pé na água, com a cabeça pra fora.
	var lay_down := _swim_blend * _swim_move_blend
	visual.rotation.x = lerp_angle(
		visual.rotation.x, deg_to_rad(swim_pitch_degrees) * lay_down, 5.0 * delta)

	# Deitado o pivô continua nos pés, então levanta o visual pra que o corpo
	# fique na linha d'água em vez de afundado. Amarrado no float_depth pra que
	# mexer na flutuação não descole o corpo da superfície ao nadar.
	visual.position.y = lerpf(visual.position.y, float_depth * 0.8 * lay_down, 5.0 * delta)

	_update_swim_pose(delta)

## Pose de natação inteira, montada por código a cada frame.
##
## São duas poses que se misturam pelo quanto o personagem está se deslocando:
##   _swim_move_blend = 0 -> boiando parado em pé, braços abertos, pés batendo
##   _swim_move_blend = 1 -> nado crawl, corpo deitado, braçada alternada
##
## Tudo é descrito em espaço do corpo: +X esquerda, +Y cima, +Z frente. Como o
## nó Visual é quem deita o corpo na água, aqui o personagem é sempre "em pé" e
## o +Y vira a direção de nado depois do pitch.
func _update_swim_pose(delta: float) -> void:
	if not my_skeleton or _swim_bones.is_empty():
		return

	# Blend suave pra entrada e saída da água não estalar.
	var target_blend := 1.0 if is_swimming else 0.0
	_swim_blend = move_toward(_swim_blend, target_blend, 4.0 * delta)
	if _swim_blend <= 0.001:
		return

	var speed := Vector2(velocity.x, velocity.z).length()
	var move_target := clampf(speed / maxf(swim_speed, 0.01), 0.0, 1.0)
	_swim_move_blend = move_toward(_swim_move_blend, move_target, 2.5 * delta)

	var b := _swim_blend
	var m := _swim_move_blend
	var flip := -1.0 if swim_stroke_inverted else 1.0

	# Boiando o ritmo é lento; nadando é a cadência da braçada.
	_swim_time += delta * lerpf(swim_tread_speed, swim_stroke_speed, m) * TAU

	var p := _swim_time * flip
	var stroke_l := sin(p)
	var stroke_r := sin(p + PI)
	var kick_l := sin(p * 2.0)
	var kick_r := sin(p * 2.0 + PI)
	var scull := sin(p)

	# --- braços -------------------------------------------------------------
	# Parado: abertos pros lados, um pouco abaixo da horizontal, varrendo a água
	# pra frente e pra trás (é isso que segura o corpo boiando).
	var tread_l := Vector3(1.0, -0.30, 0.45 * scull)
	var tread_r := Vector3(-1.0, -0.30, 0.45 * scull)
	# Nadando: moinho no plano vertical, um braço puxa enquanto o outro recupera.
	var crawl_l := Vector3(0.30, cos(p), -sin(p))
	var crawl_r := Vector3(-0.30, cos(p + PI), -sin(p + PI))

	_point_bone("l_arm", tread_l.lerp(crawl_l, m), b)
	_point_bone("r_arm", tread_r.lerp(crawl_r, m), b)

	# Cotovelo: parado fica dobrado pra frente; nadando dobra só na recuperação.
	var tread_fore_l := Vector3(0.55, -0.35, 0.75)
	var tread_fore_r := Vector3(-0.55, -0.35, 0.75)
	var crawl_fore_l := crawl_l.lerp(Vector3(0.30, 0.2, 0.9), maxf(0.0, -stroke_l) * 0.6)
	var crawl_fore_r := crawl_r.lerp(Vector3(-0.30, 0.2, 0.9), maxf(0.0, -stroke_r) * 0.6)

	_point_bone("l_forearm", tread_fore_l.lerp(crawl_fore_l, m), b)
	_point_bone("r_forearm", tread_fore_r.lerp(crawl_fore_r, m), b)

	# --- pernas -------------------------------------------------------------
	# Parado: pedalada de pernas, joelho dobrado, amplitude maior.
	var tread_leg_l := Vector3(0.25, -1.0, 0.55 * kick_l)
	var tread_leg_r := Vector3(-0.25, -1.0, 0.55 * kick_r)
	# Nadando: batida de crawl, pernas quase retas e amplitude curta.
	var crawl_leg_l := Vector3(0.12, -1.0, 0.30 * kick_l)
	var crawl_leg_r := Vector3(-0.12, -1.0, 0.30 * kick_r)

	_point_bone("l_upleg", tread_leg_l.lerp(crawl_leg_l, m), b)
	_point_bone("r_upleg", tread_leg_r.lerp(crawl_leg_r, m), b)

	# Canela segue a coxa com atraso, que é o que dá a chicotada da pernada.
	var shin_bend: float = lerpf(0.45, 0.18, m)
	_point_bone("l_leg", Vector3(0.1, -1.0, shin_bend + 0.3 * kick_l).normalized(), b)
	_point_bone("r_leg", Vector3(-0.1, -1.0, shin_bend + 0.3 * kick_r).normalized(), b)

	# --- tronco -------------------------------------------------------------
	# Rolagem leve acompanhando a braçada, que é o que tira a cara de boneco.
	var spine_dir := Vector3(0.08 * stroke_l * m, 1.0, 0.05 * sin(p * 0.5))
	_point_bone("spine", spine_dir, b * 0.6)

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
		
	if not anim_player.animation_finished.is_connected(_on_animation_finished):
		anim_player.animation_finished.connect(_on_animation_finished)
		
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
	
	var jump_scene_res = load("res://flavio/Jumping Up.fbx")
	if jump_scene_res:
		var jump_scene = jump_scene_res.instantiate()
		var jump_ap = _find_ap(jump_scene)
		if jump_ap:
			var anim = get_first_animation(jump_ap)
			if anim:
				anim = anim.duplicate()
				anim.loop_mode = Animation.LOOP_NONE
				add_animation_to_player(anim_player, "Jump", anim)
		jump_scene.queue_free()
		
	var punch_scene_res = load("res://flavio/soco.fbx")
	if punch_scene_res:
		var punch_scene = punch_scene_res.instantiate()
		var punch_ap = _find_ap(punch_scene)
		if punch_ap:
			var anim = get_first_animation(punch_ap)
			if anim:
				anim = anim.duplicate()
				anim.loop_mode = Animation.LOOP_NONE
				add_animation_to_player(anim_player, "Punch", anim)
		punch_scene.queue_free()
	
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
	_update_swim_visual(delta)

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
	if Input.is_action_just_pressed("hotbar_4"): _toggle_slot(3)
	
	if Input.is_action_just_pressed("grapple_equip"):
		grapple_equipped = !grapple_equipped
		if is_grappling:
			is_grappling = false
			grapple_equipped = false
			if rope_mesh:
				rope_mesh.queue_free()
				rope_mesh = null
				
	var target_grapple_point = null
	if not is_grappling:
		var closest_dist = 20.0
		var nodes = get_tree().get_nodes_in_group("grapple_point")
		for node in nodes:
			var dist = global_position.distance_to(node.global_position)
			if dist < closest_dist:
				closest_dist = dist
				target_grapple_point = node
				
		if target_grapple_point:
			prompt_label.text = "[ K ]"
			prompt_label.global_position = target_grapple_point.global_position
			prompt_label.show()
			
			if Input.is_action_just_pressed("grapple_action"):
				_shoot_grapple(target_grapple_point.global_position)
				
	if Input.is_action_just_pressed("shoot"):
		if is_armed:
			_shoot()
		else:
			_punch()
		
	if is_armed and weapon_slot.get_child_count() > 0:
		var w = weapon_slot.get_child(0)
		w.position = pos_arma
		w.rotation_degrees = rot_arma
		w.scale = scale_arma

func _shoot():
	print("POW! Tiros disparados!")
	
	var start_pos = global_position + Vector3(0, 1.2, 0)
	if is_armed and weapon_slot.get_child_count() > 0:
		start_pos = weapon_slot.get_child(0).global_position
		
	var end_pos = start_pos + visual.global_transform.basis.z * 50.0
		
	var bullet_script = preload("res://bullet.gd")
	var bullet = bullet_script.new()
	
	# Adiciona o projétil à cena raiz
	get_tree().root.add_child(bullet)
	
	# Define a posição e direção
	bullet.global_position = start_pos
	bullet.direction = (end_pos - start_pos).normalized()
	
func _punch():
	print("Tentando dar soco. is_punching: ", is_punching, " on floor: ", is_on_floor())
	if is_punching or not is_on_floor(): return
	is_punching = true
	if anim_player and anim_player.has_animation("Punch"):
		print("Iniciando animacao de Punch")
		anim_player.play("Punch", 0.1)
	else:
		print("ERRO: animacao Punch não encontrada!")

func _on_animation_finished(anim_name: String):
	if anim_name == "Punch":
		print("Animacao Punch finalizada!")
		is_punching = false

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

func _on_hotbar_updated(slot_index, drag_data):
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
		if to_slot == 999:
			if item.begins_with("mochila") or item == "mochila.fbx":
				var temp = backpack_item
				backpack_item = item
				inventory[from_slot] = temp
				_update_backpack_model()
		elif from_slot == 999:
			var temp = inventory[to_slot]
			inventory[to_slot] = backpack_item
			backpack_item = temp
			_update_backpack_model()
		else:
			var temp = inventory[to_slot]
			inventory[to_slot] = item
			inventory[from_slot] = temp
	elif source == "hotbar":
		var from_hotbar = drag_data["slot"]
		if to_slot == 999:
			if item.begins_with("mochila") or item == "mochila.fbx":
				var temp = backpack_item
				backpack_item = item
				hotbar_items[from_hotbar] = temp
				_update_backpack_model()
		else:
			var temp = inventory[to_slot]
			inventory[to_slot] = item
			hotbar_items[from_hotbar] = temp
		
	update_all_ui()
	
func _update_backpack_model():
	if not backpack_node: return
	for child in backpack_node.get_children():
		child.queue_free()
	
	if backpack_item != "":
		var bp = load("res://mochilas/mochila.fbx").instantiate()
		backpack_node.add_child(bp)
		bp.position = pos_mochila
		bp.rotation_degrees = rot_mochila
		bp.scale = scale_mochila

func update_all_ui():
	if has_node("InventoryUI"):
		$InventoryUI.update_inventory(inventory, backpack_item)
		for i in range(hotbar_items.size()):
			var hs = $InventoryUI.hotbar_slots[i]
			hs.item_id = hotbar_items[i]
			if hs.has_method("update_visuals"):
				hs.update_visuals()

func _pickup_item(item):
	var item_id = item.get_item_id()
	for i in range(inventory.size()):
		if inventory[i] == "":
			inventory[i] = item_id
			if has_node("InventoryUI"):
				$InventoryUI.update_inventory(inventory, backpack_item)
			item.queue_free()
			return

func _equip_item(item_id):
	for child in weapon_slot.get_children():
		child.queue_free()
		
	if item_id == "ak47":
		var ak = load("res://ak47/Meshy_AI_AK_47_with_wooden_sto_0706200409_texture.fbx").instantiate()
		weapon_slot.add_child(ak)
		ak.position = pos_arma
		ak.rotation_degrees = rot_arma
		ak.scale = scale_arma

func _on_item_dropped(item_id):
	inventory.erase(item_id)
	if has_node("InventoryUI"):
		$InventoryUI.update_inventory(inventory, backpack_item)
		
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
	if is_grappling:
		var player_pos = global_position + Vector3(0, 1, 0)
		var rope_vec = player_pos - grapple_point
		var current_dist = rope_vec.length()
		var rope_dir = rope_vec.normalized()
		
		if Input.is_action_pressed("ui_up"):
			rope_length = max(2.0, rope_length - 10.0 * delta)
		if Input.is_action_pressed("ui_down"):
			rope_length += 10.0 * delta
			
		if current_dist > rope_length:
			var target_pos = grapple_point + rope_dir * rope_length
			var correction = target_pos - player_pos
			
			if is_on_floor() and not Input.is_action_pressed("ui_up"):
				var dy = abs(grapple_point.y - player_pos.y)
				if rope_length > dy:
					var anchor_xz = Vector3(grapple_point.x, player_pos.y, grapple_point.z)
					var dist_xz = player_pos.distance_to(anchor_xz)
					var max_r = sqrt(rope_length * rope_length - dy * dy)
					if dist_xz > max_r:
						var dir_xz = (player_pos - anchor_xz).normalized()
						if dir_xz.length_squared() == 0: dir_xz = Vector3.RIGHT
						var target_xz = anchor_xz + dir_xz * max_r
						global_position.x = target_xz.x
						global_position.z = target_xz.z
						
						var v_xz = Vector3(velocity.x, 0, velocity.z)
						var v_dot = v_xz.dot(dir_xz)
						if v_dot > 0:
							v_xz -= dir_xz * v_dot
							velocity.x = v_xz.x
							velocity.z = v_xz.z
				else:
					global_position += correction
					var v_dot = velocity.dot(rope_dir)
					if v_dot > 0: velocity -= rope_dir * v_dot
			else:
				global_position += correction
				var v_dot = velocity.dot(rope_dir)
				if v_dot > 0:
					velocity -= rope_dir * v_dot
				
		_update_rope_visual(delta)

		if Input.is_action_just_pressed("grapple_equip"):
			is_grappling = false
			grapple_equipped = false
			if rope_mesh:
				rope_mesh.queue_free()
				rope_mesh = null
				
		if Input.is_action_just_pressed("ui_accept"): # Pular da corda
			is_grappling = false
			grapple_equipped = false
			if rope_mesh:
				rope_mesh.queue_free()
				rope_mesh = null
			velocity += Vector3.UP * 16.0 + velocity.normalized() * 5.0
				
	_update_water_state()

	var current_on_floor = is_on_floor()
	if current_on_floor != was_on_floor:
		# Na água os braços são controlados pela braçada, então o ragdoll de
		# queda não pode entrar ou ele briga com a pose procedural.
		if not current_on_floor and not is_in_water:
			if my_skeleton and arm_bone_names.size() > 0:
				my_skeleton.physical_bones_start_simulation(arm_bone_names)
		else:
			if my_skeleton:
				my_skeleton.physical_bones_stop_simulation()
	was_on_floor = current_on_floor

	if is_swimming:
		_apply_buoyancy(delta)
	elif not current_on_floor:
		velocity.y -= 25.0 * delta
	elif Input.is_action_just_pressed("ui_accept") and not is_grappling:
		velocity.y = 10.0
		
	current_aim_target = Vector3.ZERO
	var is_aiming = false # Desabilitando mira com mouse
	var use_armed_anim = is_armed or grapple_equipped
					
	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if is_punching and is_on_floor():
		direction = Vector3.ZERO
	
	var is_swinging = is_grappling and not is_on_floor()
	if is_swinging:
		var pump_dir = Vector3(input_dir.x, 0, input_dir.y)
		if pump_dir != Vector3.ZERO:
			pump_dir = (transform.basis * pump_dir).normalized()
			var player_pos = global_position + Vector3(0, 1, 0)
			var rope_dir = (player_pos - grapple_point).normalized()
			
			var tangent_push = pump_dir - rope_dir * pump_dir.dot(rope_dir)
			if tangent_push.length_squared() > 0.001:
				tangent_push = tangent_push.normalized()
				var current_speed_in_dir = velocity.dot(tangent_push)
				var max_swing_speed = 15.0
				if current_speed_in_dir < max_swing_speed:
					velocity += tangent_push * 10.0 * delta
					
		# Adicionando um pouco de resistência do ar para parecer mais pesado e natural
		velocity.x *= 1.0 - (0.5 * delta)
		velocity.z *= 1.0 - (0.5 * delta)
			
		if not is_aiming and velocity.length() > 0.5:
			var planar_vel = Vector3(velocity.x, 0, velocity.z).normalized()
			if planar_vel.length_squared() > 0.01:
				var target_rotation = atan2(planar_vel.x, planar_vel.z)
				visual.rotation.y = lerp_angle(visual.rotation.y, target_rotation, ROTATION_SPEED * delta)
			
		var run_anim = "ArmedRun" if use_armed_anim else "Run"
		if anim_player and anim_player.has_animation(run_anim) and anim_player.current_animation != run_anim:
			anim_player.play(run_anim, 0.2)
	else:
		var move_speed := swim_speed if is_swimming else SPEED
		if direction.length() > 0:
			velocity.x = move_toward(velocity.x, direction.x * move_speed, ACCELERATION * delta)
			velocity.z = move_toward(velocity.z, direction.z * move_speed, ACCELERATION * delta)

			if not is_aiming:
				var target_rotation = atan2(direction.x, direction.z)
				visual.rotation.y = lerp_angle(visual.rotation.y, target_rotation, ROTATION_SPEED * delta)
		else:
			velocity.x = move_toward(velocity.x, 0, ACCELERATION * delta)
			velocity.z = move_toward(velocity.z, 0, ACCELERATION * delta)

		if is_swimming:
			# A pose vem de _update_swim_pose, não do AnimationPlayer.
			pass
		elif not is_on_floor():
			if anim_player and anim_player.has_animation("Jump") and anim_player.assigned_animation != "Jump":
				anim_player.play("Jump", 0.1)
		else:
			if is_punching:
				pass
			elif direction.length() > 0:
				var run_anim = "ArmedRun" if use_armed_anim else "Run"
				if anim_player and anim_player.has_animation(run_anim) and anim_player.current_animation != run_anim:
					anim_player.play(run_anim, 0.2)
			else:
				var idle_anim = "ArmedIdle" if use_armed_anim else "Idle"
				if anim_player and anim_player.has_animation(idle_anim) and anim_player.current_animation != idle_anim:
					anim_player.play(idle_anim, 0.2)
			
	if walk_particles:
		# A fumaça de pisada não sai debaixo d'água.
		var is_walking = velocity.length() > 0.5 and is_on_floor() and not is_in_water
		walk_particles.emitting = is_walking

	_update_water_fx(delta)

	move_and_slide()

# --- água ---------------------------------------------------------------------

## Descobre em que água o personagem está e o quanto está submerso.
func _update_water_state() -> void:
	water_body = null
	for w in get_tree().get_nodes_in_group("water"):
		if w.has_method("contains_xz") and w.contains_xz(global_position):
			water_body = w
			break

	if water_body:
		water_depth = water_body.get_surface_y() - global_position.y
	else:
		water_depth = -999.0

	is_in_water = water_depth > 0.05

	# Histerese. O empuxo estabiliza o corpo em float_depth, que é mais raso do
	# que o swim_depth em que a natação começa; sem dois limiares diferentes ele
	# ficaria alternando entre nadar e afundar todo frame.
	if is_swimming:
		is_swimming = water_depth > float_depth * 0.5
	else:
		is_swimming = water_depth > swim_depth

## Empuxo: puxa o corpo de volta pra linha d'água em vez de aplicar gravidade.
func _apply_buoyancy(delta: float) -> void:
	var target_y := (water_depth - float_depth) * buoyancy
	if Input.is_action_pressed("ui_accept"):
		target_y = swim_vertical_speed
	target_y = clampf(target_y, -swim_vertical_speed, swim_vertical_speed)
	velocity.y = move_toward(velocity.y, target_y, 12.0 * delta)

## Respingos e rastros na superfície.
func _update_water_fx(delta: float) -> void:
	if splash_particles:
		var moving := Vector2(velocity.x, velocity.z).length() > 0.8
		splash_particles.emitting = is_in_water and moving
		if is_in_water:
			# Os respingos saem na linha d'água, não nos pés.
			splash_particles.global_position = Vector3(
				global_position.x, water_body.get_surface_y(), global_position.z)

	if not is_in_water or not water_body:
		_ripple_travel = 0.0
		_last_ripple_pos = global_position
		return

	# Um anel a cada ripple_spacing metros percorridos, pra o rastro ficar
	# espaçado igual independente da velocidade.
	var moved := Vector2(global_position.x - _last_ripple_pos.x,
		global_position.z - _last_ripple_pos.z).length()
	_last_ripple_pos = global_position
	_ripple_travel += moved

	if _ripple_travel >= ripple_spacing:
		_ripple_travel = 0.0
		var speed := Vector2(velocity.x, velocity.z).length()
		water_body.spawn_ripple(global_position, clampf(speed / SPEED, 0.35, 1.0))

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

func _shoot_grapple(target_pos: Vector3):
	grapple_point = target_pos
	var player_pos = global_position + Vector3(0, 1, 0)
	rope_length = player_pos.distance_to(grapple_point)
	is_grappling = true
	
	rope_mesh = MeshInstance3D.new()
	rope_mesh.set_script(load("res://rope.gd"))
	get_tree().root.add_child(rope_mesh)
	rope_mesh.setup(grapple_point, _rope_hand_pos(), rope_length)

## De onde a corda sai no personagem. O weapon_slot já é filho do osso da mão
## (ver _setup_bone_attachment), então a corda acompanha a mão de graça.
func _rope_hand_pos() -> Vector3:
	if weapon_slot:
		return weapon_slot.global_position
	return global_position + Vector3(0, 1, 0)

func _update_rope_visual(delta: float):
	if not rope_mesh:
		return
	rope_mesh.update_rope(grapple_point, _rope_hand_pos(), rope_length, delta)

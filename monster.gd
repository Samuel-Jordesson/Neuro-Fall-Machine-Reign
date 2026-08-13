extends CharacterBody3D

# IA simples de monstro: fica parado (idle), persegue o player quando ele
# entra no raio de deteccao, e ataca quando chega perto. Cada estado usa um
# modelo/GLB separado (idle, run, attack), trocando a visibilidade entre eles.

enum State { IDLE, CHASE, ATTACK, DEAD }

@export_group("Comportamento")
## Distancia em que o monstro percebe o player e comeca a perseguir.
@export var detection_range: float = 15.0
## Distancia em que para de perseguir e comeca a atacar.
@export var attack_range: float = 2.0
## Se o player sair alem disso, o monstro desiste e volta pra idle.
@export var lose_range: float = 22.0
## Velocidade de perseguicao (m/s).
@export var move_speed: float = 3.5
## Velocidade de giro pra encarar o player.
@export var turn_speed: float = 8.0

@export_group("Combate")
## Dano por golpe.
@export var attack_damage: float = 15.0
## Tempo entre um ataque e outro (segundos).
@export var attack_cooldown: float = 2.5
## Momento dentro da animacao de ataque em que o dano e aplicado (0..1).
@export var attack_hit_time: float = 0.45
## Vida do monstro.
@export var max_health: float = 60.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

var state: int = State.IDLE
var health: float = 60.0
var player: Node3D = null
var _attack_timer: float = 0.0
var _hit_applied: bool = false

# Modelos e seus AnimationPlayers
@onready var idle_model: Node3D = $IdleModel
@onready var run_model: Node3D = $RunModel
@onready var attack_model: Node3D = $AttackModel

const ANIM_IDLE := "Armature|Idle_8|baselayer"
const ANIM_RUN := "Armature|run_fast_7|baselayer"
const ANIM_ATTACK := "rigify_clip"

var _idle_ap: AnimationPlayer
var _run_ap: AnimationPlayer
var _attack_ap: AnimationPlayer


func _ready() -> void:
	add_to_group("monster")
	health = max_health
	_idle_ap = _find_anim_player(idle_model)
	_run_ap = _find_anim_player(run_model)
	_attack_ap = _find_anim_player(attack_model)

	# Loop nas animacoes continuas.
	_set_loop(_idle_ap, ANIM_IDLE, true)
	_set_loop(_run_ap, ANIM_RUN, true)

	# A animacao de corrida vem com "root motion" (o quadril anda pra frente e
	# reseta ao reiniciar). Como o movimento e feito por codigo, travamos o
	# deslocamento horizontal do quadril pra animacao ficar no lugar.
	_strip_root_motion(_run_ap, ANIM_RUN)

	if _attack_ap and not _attack_ap.animation_finished.is_connected(_on_attack_anim_finished):
		_attack_ap.animation_finished.connect(_on_attack_anim_finished)

	# Deixa os tres modelos com o mesmo acabamento fosco (sem brilho). Cada GLB
	# foi exportado com roughness diferente, entao a pele mudava de brilho entre
	# as animacoes. Padroniza todos igual ao modelo de ataque.
	for model in [idle_model, run_model, attack_model]:
		_make_matte(model)

	_find_player()
	_enter_state(State.IDLE)


func _find_player() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	# gravidade
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	if player == null or not is_instance_valid(player):
		_find_player()

	var dist := INF
	if player:
		dist = global_position.distance_to(player.global_position)

	match state:
		State.IDLE:
			velocity.x = 0.0
			velocity.z = 0.0
			if player and dist <= detection_range:
				_enter_state(State.CHASE)
		State.CHASE:
			if player == null or dist > lose_range:
				_enter_state(State.IDLE)
			elif dist <= attack_range:
				_enter_state(State.ATTACK)
			else:
				_chase(delta)
		State.ATTACK:
			velocity.x = 0.0
			velocity.z = 0.0
			if player:
				_face_player(delta)
			_attack_timer -= delta
			# aplica o dano no meio da animacao
			if not _hit_applied and _attack_ap and _attack_ap.is_playing():
				var a := _attack_ap.get_animation(ANIM_ATTACK)
				if a and _attack_ap.current_animation_position >= a.length * attack_hit_time:
					_deal_damage()
			if _attack_timer <= 0.0:
				if player and dist <= attack_range:
					_start_attack_swing()
				else:
					_enter_state(State.CHASE)

	move_and_slide()


func _chase(delta: float) -> void:
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var dir := to_player.normalized()
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed
	_face_dir(dir, delta)


func _face_player(delta: float) -> void:
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	if to_player.length() > 0.01:
		_face_dir(to_player.normalized(), delta)


func _face_dir(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.01:
		return
	var target_yaw := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clamp(turn_speed * delta, 0.0, 1.0))


func _enter_state(new_state: int) -> void:
	state = new_state
	match new_state:
		State.IDLE:
			_show_model(idle_model)
			if _idle_ap: _idle_ap.play(ANIM_IDLE)
		State.CHASE:
			_show_model(run_model)
			if _run_ap: _run_ap.play(ANIM_RUN)
		State.ATTACK:
			_attack_timer = 0.0
			_start_attack_swing()
		State.DEAD:
			_show_model(idle_model)


func _start_attack_swing() -> void:
	_show_model(attack_model)
	_hit_applied = false
	_attack_timer = attack_cooldown
	if _attack_ap:
		_attack_ap.stop()
		_attack_ap.play(ANIM_ATTACK)


func _deal_damage() -> void:
	_hit_applied = true
	if player and is_instance_valid(player) and player.has_method("take_damage"):
		# so acerta se ainda estiver no alcance
		if global_position.distance_to(player.global_position) <= attack_range + 0.6:
			player.take_damage(attack_damage)


func _on_attack_anim_finished(anim_name: StringName) -> void:
	if anim_name == ANIM_ATTACK and state == State.ATTACK:
		# volta pra idle da pose de ataque enquanto espera o cooldown
		_show_model(idle_model)
		if _idle_ap: _idle_ap.play(ANIM_IDLE)


func take_damage(amount: float) -> void:
	if state == State.DEAD:
		return
	health -= amount
	if health <= 0.0:
		_die()
	elif state == State.IDLE:
		_enter_state(State.CHASE)


func _die() -> void:
	state = State.DEAD
	velocity = Vector3.ZERO
	set_physics_process(false)
	queue_free()


# --- helpers ---
func _show_model(active: Node3D) -> void:
	for m in [idle_model, run_model, attack_model]:
		if m:
			m.visible = (m == active)


func _make_matte(node: Node) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		var mesh: Mesh = node.mesh
		if mesh:
			for s in range(mesh.get_surface_count()):
				var mat: Material = node.get_active_material(s)
				if mat is StandardMaterial3D:
					var m: StandardMaterial3D = mat.duplicate()
					m.roughness = 1.0
					m.metallic = 0.0
					m.metallic_specular = 0.0
					node.set_surface_override_material(s, m)
	for c in node.get_children():
		_make_matte(c)


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var ap := _find_anim_player(c)
		if ap:
			return ap
	return null


func _strip_root_motion(ap: AnimationPlayer, anim_name: String) -> void:
	if ap == null or not ap.has_animation(anim_name):
		return
	var a := ap.get_animation(anim_name)
	for i in range(a.get_track_count()):
		if a.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		var path := String(a.track_get_path(i))
		# so mexe na raiz (quadril), preservando o resto do esqueleto
		if not path.ends_with(":Hips"):
			continue
		var kc := a.track_get_key_count(i)
		if kc == 0:
			continue
		var base: Vector3 = a.track_get_key_value(i, 0)
		for k in range(kc):
			var v: Vector3 = a.track_get_key_value(i, k)
			# trava X e Z (deslocamento), mantem Y (balanco vertical)
			a.track_set_key_value(i, k, Vector3(base.x, v.y, base.z))


func _set_loop(ap: AnimationPlayer, anim_name: String, enabled: bool) -> void:
	if ap == null or not ap.has_animation(anim_name):
		return
	var a := ap.get_animation(anim_name)
	a.loop_mode = Animation.LOOP_LINEAR if enabled else Animation.LOOP_NONE

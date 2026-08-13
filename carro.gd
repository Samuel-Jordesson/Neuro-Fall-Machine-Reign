extends VehicleBody3D

# MEDIDO no Godot 4.7 + Jolt (teste headless, nao deduzido da documentacao):
# engine_force NEGATIVO empurra o carro para o -Z local. -Z e a frente do Godot
# e e onde estao as rodas WheelFront da cena, entao tudo bate: a frente do carro
# e -Z, o esterco fica no eixo dianteiro e o sinal do volante e o padrao.
# Se algum dia uma versao do Godot inverter isso, o carro anda de re e basta
# trocar esta constante para 1.0.
const ENGINE_FORCE_SIGN := -1.0

## Tolerancia em km/h antes de tratar o acelerador contrario como freio. Precisa
## ser maior que o tremido do carro parado, senao ele freia a si mesmo.
const REVERSE_DEADBAND_KMH := 3.0

@export_group("Motor")
## Forca por roda de tracao. As 4 rodas tracionam, entao o total e 4x isso.
@export var max_engine_force := 6000.0
@export var max_speed_kmh := 170.0
@export var max_reverse_kmh := 50.0
## Freio de servico (S andando pra frente, W andando de re).
@export var brake_force := 60.0
## Freio de mao: trava so o eixo traseiro e solta a aderencia dele.
@export var handbrake_force := 130.0
## Desaceleracao quando solta o acelerador, pra nao planar pra sempre.
@export var engine_brake := 3.0

@export_group("Direcao")
## Esterco maximo parado, em radianos (~31 graus).
@export var steer_angle_low := 0.55
## Esterco maximo na velocidade de referencia (~7 graus).
@export var steer_angle_high := 0.12
## Velocidade em km/h onde o esterco ja esta totalmente fechado.
@export var steer_speed_ref := 110.0
@export var steer_turn_rate := 3.0
## Volta ao centro mais rapido do que vira, igual jogo arcade.
@export var steer_return_rate := 6.0

@export_group("Estabilidade")
## Forca pra baixo proporcional a velocidade ao quadrado. Cola o carro no chao.
## So aparece em velocidade alta; se subir demais o carro fica pesado.
@export var downforce := 3.0
@export var grip_front := 10.5
@export var grip_rear := 9.5
## Aderencia traseira com o freio de mao puxado (derrapagem controlada).
@export var handbrake_grip_rear := 3.0
## Endireita o carro quando esta com as 4 rodas no ar.
@export var air_righting := 1.5

var driver = null
@onready var camera_arm = $CameraArm
@onready var camera = $CameraArm/Camera3D
@onready var interact_area = $InteractArea

var _all_wheels: Array[VehicleWheel3D] = []
var _front_wheels: Array[VehicleWheel3D] = []
var _rear_wheels: Array[VehicleWheel3D] = []

func _ready():
	add_to_group("interactable")
	camera_arm.top_level = true
	if camera:
		camera.current = false
	_ensure_input(&"handbrake", KEY_SPACE)
	_setup_wheels()

func _process(delta):
	if camera_arm:
		camera_arm.global_position = global_position

func get_interaction_text() -> String:
	return "Press E to Drive"

func interact(player):
	if driver == null:
		driver = player
		player.enter_vehicle(self)
		if camera:
			camera.current = true

func _physics_process(delta):
	if driver == null:
		return

	var speed_kmh := _signed_speed() * 3.6

	_apply_steering(speed_kmh, delta)
	_apply_drive(speed_kmh)
	_apply_stability(delta)

	if Input.is_action_just_pressed("interact"):
		_exit()

## Direcao em que o carro anda pra frente, em espaco global.
func _forward_dir() -> Vector3:
	return -global_transform.basis.z

## Velocidade em m/s, positiva andando pra frente e negativa de re.
func _signed_speed() -> float:
	return linear_velocity.dot(_forward_dir())

# --- direcao ------------------------------------------------------------------

func _apply_steering(speed_kmh: float, delta: float) -> void:
	# O esterco maximo encolhe com a velocidade. Sem isso, 45 graus de esterco a
	# 120 km/h rodopiam o carro na hora.
	var t := clampf(absf(speed_kmh) / steer_speed_ref, 0.0, 1.0)
	var max_lock: float = lerpf(steer_angle_low, steer_angle_high, t * t)

	var steer_input := Input.get_axis(&"move_right", &"move_left")
	var target := steer_input * max_lock
	var returning := is_zero_approx(steer_input) \
		or (not is_zero_approx(steering) and signf(target) != signf(steering))
	var rate := steer_return_rate if returning else steer_turn_rate
	steering = move_toward(steering, target, rate * delta)

# --- motor e freio ------------------------------------------------------------

func _apply_drive(speed_kmh: float) -> void:
	var throttle := Input.get_action_strength(&"move_up")
	var reverse_in := Input.get_action_strength(&"move_down")
	var handbrake_on := Input.is_action_pressed(&"handbrake")

	var force := 0.0
	var brake_amount := 0.0

	if handbrake_on:
		brake_amount = handbrake_force
	elif throttle > 0.0 and speed_kmh > -REVERSE_DEADBAND_KMH:
		force = throttle * max_engine_force * _power_curve(speed_kmh, max_speed_kmh)
	elif reverse_in > 0.0 and speed_kmh < REVERSE_DEADBAND_KMH:
		# Re tem bem menos forca, igual GTA.
		force = -reverse_in * max_engine_force * 0.55 * _power_curve(-speed_kmh, max_reverse_kmh)
	elif throttle > 0.0 or reverse_in > 0.0:
		# Direcao contraria ao movimento vira freio, nao marcha a re instantanea.
		brake_amount = brake_force * maxf(throttle, reverse_in)
	else:
		brake_amount = engine_brake

	engine_force = force * ENGINE_FORCE_SIGN

	# brake do VehicleBody3D escreve em todas as rodas, entao o freio de mao
	# sobrescreve as traseiras depois.
	brake = brake_amount
	if handbrake_on:
		for w in _front_wheels:
			w.brake = brake_amount * 0.25
		for w in _rear_wheels:
			w.wheel_friction_slip = handbrake_grip_rear
	else:
		for w in _rear_wheels:
			w.wheel_friction_slip = grip_rear

func _power_curve(kmh: float, top_kmh: float) -> float:
	if kmh <= 0.0:
		return 1.0
	if kmh >= top_kmh:
		return 0.0
	return 1.0 - pow(kmh / top_kmh, 2.0)

# --- estabilidade -------------------------------------------------------------

func _apply_stability(delta: float) -> void:
	var speed := linear_velocity.length()
	apply_central_force(-global_transform.basis.y * downforce * speed * speed)

	var grounded := false
	for w in _all_wheels:
		if w.is_in_contact():
			grounded = true
			break

	if not grounded:
		# Sem isso um pulo acaba quase sempre com o carro de rodas pra cima.
		var correction := global_transform.basis.y.cross(Vector3.UP)
		apply_torque(correction * air_righting * mass)

# --- setup / saida ------------------------------------------------------------

func _setup_wheels() -> void:
	for child in get_children():
		if child is VehicleWheel3D:
			_all_wheels.append(child)

	for w in _all_wheels:
		# A frente do carro e -Z, entao as rodas com z negativo sao as dianteiras.
		if w.position.z < 0.0:
			_front_wheels.append(w)
			w.use_as_steering = true
			w.wheel_friction_slip = grip_front
		else:
			_rear_wheels.append(w)
			w.use_as_steering = false
			w.wheel_friction_slip = grip_rear
		w.use_as_traction = true

func _ensure_input(action: StringName, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)

func _exit() -> void:
	var exit_pos := global_position + (transform.basis * Vector3(-2.5, 0.5, 0))
	driver.exit_vehicle(exit_pos)
	driver = null
	if camera:
		camera.current = false
	engine_force = 0
	steering = 0
	# Freio residual pra nao sair rolando sozinho, e devolve a aderencia caso o
	# jogador tenha saido com o freio de mao puxado.
	brake = engine_brake
	for w in _rear_wheels:
		w.wheel_friction_slip = grip_rear

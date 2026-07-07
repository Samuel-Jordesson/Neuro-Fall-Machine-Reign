extends VehicleBody3D

@export var max_engine_force = 2000.0
@export var max_steer = 0.8

var driver = null
@onready var camera_arm = $CameraArm
@onready var camera = $CameraArm/Camera3D
@onready var interact_area = $InteractArea

func _ready():
	add_to_group("interactable")
	camera_arm.top_level = true
	if camera:
		camera.current = false

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
	if driver != null:
		var steering_input = Input.get_axis("move_right", "move_left")
		steering = move_toward(steering, steering_input * max_steer, delta * 2.5)
		
		var accel_input = Input.get_axis("move_down", "move_up")
		# Inverted so W goes forward
		engine_force = -accel_input * max_engine_force
		
		if Input.is_action_just_pressed("interact"):
			# Exit slightly to the left of the car
			var exit_pos = global_position + (transform.basis * Vector3(-2.5, 0.5, 0))
			driver.exit_vehicle(exit_pos)
			driver = null
			if camera:
				camera.current = false
			engine_force = 0
			steering = 0

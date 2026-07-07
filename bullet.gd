extends Area3D

var speed = 40.0
var direction = Vector3.ZERO
var damage = 10

func _ready():
	top_level = true
	
	# Visual (Bolinha amarela brilhante)
	var mesh_inst = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.1
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 0)
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 0)
	sphere.material = mat
	mesh_inst.mesh = sphere
	add_child(mesh_inst)
	
	# Colisão
	var shape = CollisionShape3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = 0.05
	shape.shape = sphere_shape
	add_child(shape)
	
	# Opcional: Rastro (Trail)
	var trail = OmniLight3D.new()
	trail.light_color = Color(1, 1, 0)
	trail.light_energy = 0.5
	trail.omni_range = 1.0
	add_child(trail)
	
	body_entered.connect(_on_body_entered)
	
	# Destrói o projétil depois de 2 segundos para não pesar o jogo
	get_tree().create_timer(2.0).timeout.connect(queue_free)

func _physics_process(delta):
	global_position += direction * speed * delta

func _on_body_entered(body):
	# Se acertar algo que toma dano, aplica dano
	if body.has_method("take_damage"):
		body.take_damage(damage)
	
	# Se acertar qualquer coisa, destrói o projétil
	if body.name != "Player": # Evita que bata no próprio jogador caso spawne muito perto
		queue_free()

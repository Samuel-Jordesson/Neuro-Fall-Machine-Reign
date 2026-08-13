extends MeshInstance3D

# Superficie de agua. Alem de desenhar, responde duas perguntas pra quem estiver
# dentro dela (onde fica a superficie, e se um ponto esta dentro do plano) e
# guarda o pool de rastros.

@export_group("Rastros")
## Quantos aneis podem existir ao mesmo tempo. Passou disso, reaproveita o mais velho.
@export var ripple_pool_size := 28
## Segundos que um anel leva pra crescer todo e sumir.
@export var ripple_lifetime := 1.8
@export var ripple_start_size := 0.7
@export var ripple_max_size := 3.4
## Altura do anel acima da superficie, so pra nao brigar com o z-buffer da agua.
@export var ripple_offset_y := 0.03

var _ripples: Array[MeshInstance3D] = []
var _ripple_age: PackedFloat32Array = []
var _next_ripple := 0

func _ready() -> void:
	add_to_group("water")
	_build_ripple_pool()

## Altura Y da superficie em repouso (a onda do shader oscila em volta disso).
func get_surface_y() -> float:
	return global_position.y

## O ponto esta dentro do retangulo do plano de agua, olhando so X e Z?
func contains_xz(p: Vector3) -> bool:
	var plane := mesh as PlaneMesh
	if not plane:
		return false
	var s := global_basis.get_scale()
	var half_x: float = plane.size.x * 0.5 * s.x
	var half_z: float = plane.size.y * 0.5 * s.z
	var local := p - global_position
	return absf(local.x) <= half_x and absf(local.z) <= half_z

## Cria um anel de rastro na superficie, na vertical de world_pos.
func spawn_ripple(world_pos: Vector3, strength: float = 1.0) -> void:
	if _ripples.is_empty():
		return
	var i := _next_ripple
	_next_ripple = (_next_ripple + 1) % _ripples.size()

	var r := _ripples[i]
	r.global_position = Vector3(world_pos.x, get_surface_y() + ripple_offset_y, world_pos.z)
	r.set_instance_shader_parameter(&"strength", clampf(strength, 0.0, 1.0))
	r.visible = true
	_ripple_age[i] = 0.0

func _process(delta: float) -> void:
	# A animacao do rastro e toda aqui: o anel cresce e apaga com a idade.
	for i in range(_ripples.size()):
		var r := _ripples[i]
		if not r.visible:
			continue

		_ripple_age[i] += delta
		var t := _ripple_age[i] / ripple_lifetime
		if t >= 1.0:
			r.visible = false
			continue

		# Cresce rapido no comeco e vai desacelerando, como onda de verdade.
		var eased := 1.0 - pow(1.0 - t, 2.0)
		var size: float = lerpf(ripple_start_size, ripple_max_size, eased)
		r.scale = Vector3(size, 1.0, size)
		r.set_instance_shader_parameter(&"progress", eased)

func _build_ripple_pool() -> void:
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	# Subdivisao pro anel acompanhar a curva da onda em vez de cortar reto.
	quad.subdivide_width = 8
	quad.subdivide_depth = 8

	var mat := ShaderMaterial.new()
	mat.shader = load("res://ripple.gdshader")
	mat.render_priority = 1
	_copy_wave_params_from_water(mat)
	quad.material = mat

	_ripple_age.resize(ripple_pool_size)
	for i in range(ripple_pool_size):
		var r := MeshInstance3D.new()
		r.mesh = quad
		r.visible = false
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# top_level pro anel ficar parado no mundo, sem herdar a escala da agua.
		r.top_level = true
		add_child(r)
		_ripples.append(r)
		_ripple_age[i] = 0.0

## Copia onda/tempo/escala do material da agua pro material do anel, pra que os
## dois usem exatamente a mesma deformacao e o anel nao afunde na crista.
func _copy_wave_params_from_water(ripple_mat: ShaderMaterial) -> void:
	var water_mat := get_active_material(0) as ShaderMaterial
	if not water_mat:
		return
	for p in ["wave", "wave2", "wave_dir", "wave_dir2", "time_scale", "wave_scale", "wave_height"]:
		var v = water_mat.get_shader_parameter(p)
		if v != null:
			ripple_mat.set_shader_parameter(p, v)

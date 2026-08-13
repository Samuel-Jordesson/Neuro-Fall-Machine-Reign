extends MeshInstance3D

# Corda do gancho: simulacao Verlet com restricoes de distancia.
#
# Em vez de um cilindro esticado entre as duas pontas, a corda e uma fila de
# pontos livres presos so nas extremidades. Cada ponto cai por conta propria e
# depois as restricoes puxam os vizinhos de volta pro comprimento certo. E isso
# que faz ela ceder quando sobra corda, esticar quando o jogador chega no limite
# e chicotear no balanco, em vez de ficar dura.
#
# O dono (player.gd) chama update_rope() uma vez por frame de fisica; nao ha
# _physics_process aqui de proposito, pra ordem de execucao ser determinista.

## Quantos pontos a corda tem. Mais = mais maleavel e mais caro.
@export var segments := 24
@export var thickness := 0.045
## Lados do tubo. 6 ja fica redondo o bastante nessa espessura.
@export var sides := 6
@export var rope_color := Color(0.32, 0.24, 0.16)

@export_group("Simulação")
@export var gravity := 20.0
## Quanto da velocidade sobrevive a cada frame. Menor = corda mais "morta".
@export var damping := 0.94
## Passadas de restrição por frame. Mais = corda menos elástica.
@export var iterations := 14
## Quanto da velocidade gerada pelas próprias restrições é descartada.
## Sem isso a corda esticada entra em ressonância (ver comentário em _simulate).
@export_range(0.0, 1.0) var constraint_damping := 0.35
## Folga aplicada ao comprimento, pra corda nunca ficar 100% reta e sem vida.
@export var slack := 1.02

var _points: PackedVector3Array = PackedVector3Array()
var _prev: PackedVector3Array = PackedVector3Array()
var _anchor := Vector3.ZERO
var _hand := Vector3.ZERO
var _length := 1.0
var _im: ImmediateMesh

func _ready() -> void:
	_im = ImmediateMesh.new()
	mesh = _im

	var mat := StandardMaterial3D.new()
	mat.albedo_color = rope_color
	mat.roughness = 0.9
	mat.metallic = 0.0
	material_override = mat

	# Os vertices sao gerados em coordenadas de mundo, entao o no fica na origem.
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

## Nasce a corda esticada entre as duas pontas, parada.
func setup(anchor: Vector3, hand: Vector3, length: float) -> void:
	_anchor = anchor
	_hand = hand
	_length = maxf(length, 0.1)

	_points.resize(segments)
	_prev.resize(segments)
	for i in range(segments):
		var t := float(i) / float(segments - 1)
		var p := anchor.lerp(hand, t)
		_points[i] = p
		_prev[i] = p

## Chamada pelo dono a cada frame de física: move as pontas, simula e redesenha.
func update_rope(anchor: Vector3, hand: Vector3, length: float, delta: float) -> void:
	if _points.size() < 2:
		setup(anchor, hand, length)
		return

	_anchor = anchor
	_hand = hand
	_length = maxf(length, 0.1)

	_simulate(delta)
	_rebuild_mesh()

func _simulate(delta: float) -> void:
	var n := _points.size()
	var seg_len := (_length * slack) / float(n - 1)

	# Verlet: a velocidade está implícita na diferença entre a posição atual e a
	# anterior, então não preciso guardar velocidade nenhuma.
	var g := Vector3.DOWN * gravity * delta * delta
	for i in range(n):
		var cur := _points[i]
		var vel := (cur - _prev[i]) * damping
		_prev[i] = cur
		_points[i] = cur + vel + g

	_points[0] = _anchor
	_points[n - 1] = _hand

	# Relaxação: várias passadas puxando cada par de vizinhos de volta pro
	# comprimento de segmento.
	#
	# O sentido da varredura alterna a cada passada de propósito. Varrendo
	# sempre pro mesmo lado, a tensão só se propaga um segmento por passada
	# naquela direção, e uma corda vertical esticada (onde o topo precisa
	# segurar o peso de tudo que está pendurado abaixo) fica 20% mais comprida
	# do que devia. Alternando, a informação sobe e desce e ela para de esticar.
	for it in range(iterations):
		var forward := it % 2 == 0
		for k in range(n - 1):
			var i := k if forward else (n - 2 - k)
			var a_fixed := i == 0
			var b_fixed := i + 1 == n - 1
			if a_fixed and b_fixed:
				continue

			var d := _points[i + 1] - _points[i]
			var dist := d.length()
			if dist < 0.00001:
				continue

			var corr := d * ((dist - seg_len) / dist)
			if a_fixed:
				# Ponta presa não anda, então o vizinho absorve a correção toda.
				_points[i + 1] -= corr
			elif b_fixed:
				_points[i] += corr
			else:
				_points[i] += corr * 0.5
				_points[i + 1] -= corr * 0.5

		_points[0] = _anchor
		_points[n - 1] = _hand

	# No Verlet a velocidade é implícita na diferença pra posição anterior, então
	# tudo que as restrições corrigiram vira velocidade no frame seguinte. Numa
	# corda tensa isso se realimenta: a correção pra dentro vira velocidade pra
	# dentro, o ponto passa do alvo, a restrição empurra pra fora, e a corda
	# entra em onda estacionária (segmentos medidos oscilando entre 0.30 e 0.74
	# quando o alvo era 0.44). Devolver parte da correção pro _prev descarta
	# essa energia e a corda volta a ficar uniforme quando esticada.
	for i in range(n):
		_prev[i] = _prev[i].lerp(_points[i], constraint_damping)

## Gera o tubo em volta da linha de pontos.
func _rebuild_mesh() -> void:
	_im.clear_surfaces()
	var n := _points.size()
	if n < 2:
		return

	# Transporte paralelo do quadro de referência: cada anel herda a orientação
	# do anterior em vez de recalcular do zero, senão o tubo torce sozinho
	# quando a corda fica quase vertical.
	var normals: Array[Vector3] = []
	var binormals: Array[Vector3] = []
	var carried := Vector3.UP
	for i in range(n):
		var t := _tangent(i)
		var nrm := carried - t * carried.dot(t)
		if nrm.length_squared() < 0.000001:
			var fallback := Vector3.RIGHT if absf(t.x) < 0.9 else Vector3.FORWARD
			nrm = fallback - t * fallback.dot(t)
		nrm = nrm.normalized()
		normals.append(nrm)
		binormals.append(t.cross(nrm).normalized())
		carried = nrm

	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(n - 1):
		var p0 := _points[i]
		var p1 := _points[i + 1]
		for s in range(sides):
			var a0 := float(s) / float(sides) * TAU
			var a1 := float(s + 1) / float(sides) * TAU

			var d00 := normals[i] * cos(a0) + binormals[i] * sin(a0)
			var d01 := normals[i] * cos(a1) + binormals[i] * sin(a1)
			var d10 := normals[i + 1] * cos(a0) + binormals[i + 1] * sin(a0)
			var d11 := normals[i + 1] * cos(a1) + binormals[i + 1] * sin(a1)

			_tri(p0 + d00 * thickness, d00, p1 + d10 * thickness, d10, p1 + d11 * thickness, d11)
			_tri(p0 + d00 * thickness, d00, p1 + d11 * thickness, d11, p0 + d01 * thickness, d01)
	_im.surface_end()

func _tri(a: Vector3, na: Vector3, b: Vector3, nb: Vector3, c: Vector3, nc: Vector3) -> void:
	_im.surface_set_normal(na)
	_im.surface_add_vertex(a)
	_im.surface_set_normal(nb)
	_im.surface_add_vertex(b)
	_im.surface_set_normal(nc)
	_im.surface_add_vertex(c)

func _tangent(i: int) -> Vector3:
	var n := _points.size()
	var t: Vector3
	if i == 0:
		t = _points[1] - _points[0]
	elif i == n - 1:
		t = _points[n - 1] - _points[n - 2]
	else:
		t = _points[i + 1] - _points[i - 1]
	if t.length_squared() < 0.00000001:
		return Vector3.FORWARD
	return t.normalized()

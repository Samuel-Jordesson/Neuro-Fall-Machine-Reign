@tool
extends Node3D

# Gera o cenario principal do jogo: chao verde, praia com areia e mar, grama 3D
# espalhada, arvores, e as casas posicionadas. Tudo fica dentro de um no
# "Generated" que e recriado a cada carregamento (semente fixa = sempre igual).
# Marque "rebuild" no Inspector pra regenerar depois de mexer nos parametros.

const GRASS_SCENE := preload("res://arvores/grama2/grama.glb")
const TREE_SCENE := preload("res://arvores/arvore-anime/jabami_anime_tree_v1.glb")
const WATER_SCENE := preload("res://water.tscn")

const CASA1 := preload("res://casas/casa1.glb")
const CASA2 := preload("res://casas/casa2.glb")
const CASA3 := preload("res://casas/casa3.glb")
const CASA4 := preload("res://casas/casa4.glb")
const CASA5 := preload("res://casas/casa5.glb")
const CASA_PRAIA := preload("res://casas/casa-de-madeira-praia.glb")

@export_group("Terreno")
## Lado do mapa (quadrado) em metros.
@export var ground_size: float = 240.0
## Se ligado, o chao vem do no Terrain3D da cena; o plano verde nao e criado.
@export var use_terrain3d: bool = true
## Cor do chao (verde bem claro). So usado quando use_terrain3d = false.
@export var ground_color: Color = Color(0.55, 0.78, 0.42)
## Cor da areia da praia.
@export var sand_color: Color = Color(0.86, 0.79, 0.58)

@export_group("Praia / Mar")
## Centro da regiao de praia+mar.
@export var beach_center: Vector2 = Vector2(70, 30)
## Tamanho (X,Z) da faixa de areia.
@export var sand_size: Vector2 = Vector2(90, 80)
## Tamanho (X,Z) do mar.
@export var sea_size: Vector2 = Vector2(70, 60)
## Altura da superficie do mar (abaixo de zero = afunda um pouco).
@export var sea_level: float = -0.5

@export_group("Vegetacao")
## Quantidade de tufos de grama 3D.
@export var grass_count: int = 260
## Quantidade de arvores.
@export var tree_count: int = 40
## Escala das arvores (o modelo original e gigante).
@export var tree_scale: float = 0.016
## Altura pra apoiar a base da arvore no chao (depende da escala).
@export var tree_y_offset: float = 4.1

@export_group("Casas")
## Multiplicador geral do tamanho das casas.
@export var house_scale_mult: float = 1.5

@export_group("Acoes")
@export var rebuild: bool = false:
	set(_v):
		if is_inside_tree():
			_build()

var _rng := RandomNumberGenerator.new()
var _gen: Node3D


func _ready() -> void:
	_build()


func _build() -> void:
	_rng.seed = 20260813
	var old := get_node_or_null("Generated")
	if old:
		old.free()
	_gen = Node3D.new()
	_gen.name = "Generated"
	add_child(_gen)
	if Engine.is_editor_hint() and owner:
		_gen.owner = null  # conteudo procedural nao e salvo na cena

	if not use_terrain3d:
		_build_ground()
	_build_beach_and_sea()
	_build_houses()
	_scatter_grass()
	_scatter_trees()


# --- Chao ---
func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(ground_size, ground_size)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ground_color
	mat.roughness = 1.0
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = plane
	_gen.add_child(mi)

	# colisao: plano infinito no y=0
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	var col := CollisionShape3D.new()
	var shape := WorldBoundaryShape3D.new()
	col.shape = shape
	body.add_child(col)
	_gen.add_child(body)


# --- Praia e mar ---
func _build_beach_and_sea() -> void:
	# areia
	var sand := PlaneMesh.new()
	sand.size = sand_size
	var smat := StandardMaterial3D.new()
	smat.albedo_color = sand_color
	smat.roughness = 1.0
	sand.material = smat
	var sand_mi := MeshInstance3D.new()
	sand_mi.name = "Sand"
	sand_mi.mesh = sand
	sand_mi.position = Vector3(beach_center.x, 0.05, beach_center.y)
	_gen.add_child(sand_mi)

	# mar (usa a agua com shader e sistema de natacao)
	var water := WATER_SCENE.instantiate()
	water.name = "Sea"
	water.position = Vector3(beach_center.x, sea_level, beach_center.y)
	# a agua e um plano 100x100; ajusta a escala pro tamanho pedido
	water.scale = Vector3(sea_size.x / 100.0, 1.0, sea_size.y / 100.0)
	_gen.add_child(water)


# --- Casas ---
func _build_houses() -> void:
	# [cena, posicao_xz, escala_base, rotacao_graus]
	var casas := [
		[CASA1, Vector3(-42, 0, -26), 3.0, 20.0],
		[CASA2, Vector3(-22, 0, -28), 1.0, 10.0],
		[CASA3, Vector3(-4, 0, -26), 1.6, -15.0],
		[CASA4, Vector3(16, 0, -28), 1.0, 5.0],
		[CASA5, Vector3(36, 0, -27), 1.0, -25.0],
		# casa de praia perto do mar
		[CASA_PRAIA, Vector3(beach_center.x - 30, 0, beach_center.y + 15), 1.0, 200.0],
	]
	for c in casas:
		var scene: PackedScene = c[0]
		var inst := scene.instantiate()
		_gen.add_child(inst)
		inst.scale = Vector3.ONE * (float(c[2]) * house_scale_mult)
		inst.rotation_degrees = Vector3(0, float(c[3]), 0)
		var pos: Vector3 = c[1]
		pos.y = 0.0
		inst.position = pos
		_drop_to_ground(inst)  # assenta a base no chao (y=0) medindo o modelo
		_add_trimesh_collision(inst)


func _add_trimesh_collision(root: Node) -> void:
	for mi in _all_meshes(root):
		mi.create_trimesh_collision()


# Move o no verticalmente pra que a base do modelo fique em y=0, medindo o
# AABB real ja com escala/rotacao aplicadas (independe do pivo do GLB).
func _drop_to_ground(inst: Node3D) -> void:
	inst.force_update_transform()
	var box := _world_aabb(inst)
	if box.size == Vector3.ZERO:
		return
	inst.position.y -= box.position.y

func _world_aabb(inst: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in _all_meshes(inst):
		var a: AABB = mi.global_transform * mi.get_aabb()
		if first:
			box = a
			first = false
		else:
			box = box.merge(a)
	return box


# --- Grama ---
func _scatter_grass() -> void:
	var half := ground_size * 0.5 - 4.0
	var placed := 0
	var tries := 0
	while placed < grass_count and tries < grass_count * 8:
		tries += 1
		var p := Vector2(_rng.randf_range(-half, half), _rng.randf_range(-half, half))
		if _in_sand(p) or _in_sea(p):
			continue
		var g := GRASS_SCENE.instantiate()
		_gen.add_child(g)
		g.position = Vector3(p.x, 0, p.y)
		g.rotation_degrees = Vector3(0, _rng.randf_range(0, 360), 0)
		g.scale = Vector3.ONE * _rng.randf_range(0.8, 1.6)
		placed += 1


# --- Arvores ---
func _scatter_trees() -> void:
	var half := ground_size * 0.5 - 10.0
	var placed := 0
	var tries := 0
	while placed < tree_count and tries < tree_count * 12:
		tries += 1
		var p := Vector2(_rng.randf_range(-half, half), _rng.randf_range(-half, half))
		if _in_sand(p) or _in_sea(p):
			continue
		# nao nascer em cima da rua/casas (faixa central)
		if p.y > -32.0 and p.y < -20.0:
			continue
		var t := TREE_SCENE.instantiate()
		_gen.add_child(t)
		t.scale = Vector3.ONE * tree_scale * _rng.randf_range(0.85, 1.2)
		t.rotation_degrees = Vector3(0, _rng.randf_range(0, 360), 0)
		t.position = Vector3(p.x, 0, p.y)
		_drop_to_ground(t)  # assenta a base da arvore no chao
		placed += 1


# --- helpers de regiao ---
func _in_sand(p: Vector2) -> bool:
	return abs(p.x - beach_center.x) <= sand_size.x * 0.5 \
		and abs(p.y - beach_center.y) <= sand_size.y * 0.5

func _in_sea(p: Vector2) -> bool:
	return abs(p.x - beach_center.x) <= sea_size.x * 0.5 \
		and abs(p.y - beach_center.y) <= sea_size.y * 0.5

func _all_meshes(n: Node, acc: Array = []) -> Array:
	if n is MeshInstance3D and n.mesh:
		acc.append(n)
	for c in n.get_children():
		_all_meshes(c, acc)
	return acc

extends Node2D
## Phase 2A reconstructible presentation adapter. TerrainRenderer owns which
## chunks exist; this node owns only their optional oblique mesh projections.

const Catalog = preload("res://scripts/terrain_catalog.gd")
const ObliqueProjection = preload("res://scripts/oblique_projection.gd")
const MeshBuilder = preload("res://scripts/oblique_terrain_mesh_builder.gd")
const ObliqueShader = preload("res://shaders/oblique_terrain.gdshader")

const CHUNK_SIZE := 32
const MATERIAL_COUNT := 8
const SOURCE_SIZE := Vector2i(32, 32)

var world_seed: int = 0
var max_elevation: int = 3
var material_lookup: Callable
var height_lookup: Callable
var liquid_by_id: Dictionary
var refinement_enabled: bool = false
var chunk_meshes: Dictionary = {} # Vector2i -> MeshInstance2D
var chunk_stats: Dictionary = {} # Vector2i -> compact geometry counters
var last_build_usec: int = 0
var total_build_usec: int = 0
var total_build_count: int = 0
var total_vertices: int = 0
var total_triangles: int = 0
var total_faces: int = 0

var _shared_material: ShaderMaterial


func configure(
		seed: int, maximum_elevation: int,
		world_material_lookup: Callable, world_height_lookup: Callable,
		liquids: Dictionary, refined: bool = false) -> void:
	world_seed = seed
	max_elevation = maximum_elevation
	material_lookup = world_material_lookup
	height_lookup = world_height_lookup
	liquid_by_id = liquids
	refinement_enabled = refined
	y_sort_enabled = true
	_shared_material = ShaderMaterial.new()
	_shared_material.shader = ObliqueShader
	_shared_material.set_shader_parameter("material_atlas", _build_material_atlas())
	_shared_material.set_shader_parameter("material_palette", _build_material_palette())
	_shared_material.set_shader_parameter("refinement_enabled", refinement_enabled)
	_shared_material.set_shader_parameter("seed_offset", Vector2(
		float(posmod(world_seed * 7 + 1871, 8192)),
		float(posmod(world_seed * 11 + 3917, 8192))))


func rebuild_chunk(chunk_coord: Vector2i) -> void:
	if not material_lookup.is_valid() or not height_lookup.is_valid():
		return
	var result: Dictionary = MeshBuilder.build(
		chunk_coord, world_seed, material_lookup, height_lookup,
		liquid_by_id, refinement_enabled)
	var layer: MeshInstance2D
	if chunk_meshes.has(chunk_coord):
		layer = chunk_meshes[chunk_coord]
	else:
		layer = MeshInstance2D.new()
		layer.name = "ObliqueTerrainChunk_%d_%d" % [chunk_coord.x, chunk_coord.y]
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		layer.material = _shared_material
		add_child(layer)
		chunk_meshes[chunk_coord] = layer
	layer.position = result.origin
	layer.mesh = result.mesh
	chunk_stats[chunk_coord] = {
		"build_usec": int(result.build_usec),
		"vertices": int(result.vertex_count),
		"triangles": int(result.triangle_count),
		"faces": int(result.face_count),
	}
	last_build_usec = int(result.build_usec)
	total_build_usec += last_build_usec
	total_build_count += 1
	_recalculate_geometry_totals()


func remove_chunk(chunk_coord: Vector2i) -> void:
	if not chunk_meshes.has(chunk_coord):
		return
	var layer: MeshInstance2D = chunk_meshes[chunk_coord]
	chunk_meshes.erase(chunk_coord)
	chunk_stats.erase(chunk_coord)
	layer.queue_free()
	_recalculate_geometry_totals()


func clear_chunks() -> void:
	for layer in chunk_meshes.values():
		layer.queue_free()
	chunk_meshes.clear()
	chunk_stats.clear()
	_recalculate_geometry_totals()


func get_projected_cell_polygon(world_cell: Vector2i) -> PackedVector2Array:
	return ObliqueProjection.cell_polygon(
		world_cell, int(height_lookup.call(world_cell)), world_seed,
		refinement_enabled, height_lookup)


func get_visible_cell_bounds(screen_rect: Rect2) -> Rect2i:
	return ObliqueProjection.visible_cell_bounds(screen_rect, max_elevation)


func pick(screen_position: Vector2, targets_ground: bool = false) -> Dictionary:
	var candidates: Dictionary = {}
	for elevation in range(max_elevation, -1, -1):
		var logical: Vector2 = ObliqueProjection.inverse_ground_point(screen_position, elevation)
		var center := Vector2i(floori(logical.x), floori(logical.y))
		for y in range(center.y - 1, center.y + 2):
			for x in range(center.x - 1, center.x + 2):
				candidates[Vector2i(x, y)] = true

	var best: Dictionary = {}
	var best_score: int = -2147483648
	for cell in candidates:
		var elevation: int = int(height_lookup.call(cell))
		if ObliqueProjection.contains_point(
				cell, elevation, screen_position, world_seed,
				refinement_enabled, height_lookup):
			var score: int = elevation * 100000 + (cell.x + cell.y)
			if score > best_score:
				best_score = score
				best = {
					"cell": cell, "elevation": elevation,
					"is_cliff": false, "cliff_drop": 0,
					"targets_ground": targets_ground,
				}
		if targets_ground:
			continue
		for direction in range(4):
			var neighbor_height: int = int(height_lookup.call(
				cell + ObliqueProjection.edge_neighbor(direction)))
			if elevation <= neighbor_height:
				continue
			var top := ObliqueProjection.edge_points(
				cell, direction, elevation, world_seed,
				refinement_enabled, height_lookup)
			var bottom := ObliqueProjection.edge_points(
				cell, direction, neighbor_height, world_seed,
				refinement_enabled, height_lookup)
			for segment in range(2):
				var face := PackedVector2Array([
					top[segment], top[segment + 1],
					bottom[segment + 1], bottom[segment]])
				if not Geometry2D.is_point_in_polygon(screen_position, face):
					continue
				var score: int = elevation * 100000 + (cell.x + cell.y) - 1
				if score > best_score:
					best_score = score
					best = {
						"cell": cell, "elevation": elevation,
						"is_cliff": true,
						"cliff_drop": elevation - neighbor_height,
						"targets_ground": false,
					}
	if best.is_empty():
		var logical := ObliqueProjection.inverse_ground_point(screen_position, 0.0)
		var fallback := Vector2i(floori(logical.x), floori(logical.y))
		best = {
			"cell": fallback,
			"elevation": int(height_lookup.call(fallback)),
			"is_cliff": false, "cliff_drop": 0,
			"targets_ground": targets_ground,
		}
	return best


func get_metrics() -> Dictionary:
	var current_build_usec := 0
	for stats in chunk_stats.values():
		current_build_usec += int(stats.build_usec)
	return {
		"chunk_count": chunk_meshes.size(),
		"last_build_usec": last_build_usec,
		"average_build_usec": (
			float(total_build_usec) / float(total_build_count)
			if total_build_count > 0 else 0.0),
		"current_average_build_usec": (
			float(current_build_usec) / float(chunk_stats.size())
			if not chunk_stats.is_empty() else 0.0),
		"vertices": total_vertices,
		"triangles": total_triangles,
		"faces": total_faces,
	}


func set_refinement_enabled(enabled: bool) -> void:
	if refinement_enabled == enabled:
		return
	refinement_enabled = enabled
	_shared_material.set_shader_parameter("refinement_enabled", enabled)
	for chunk_coord in chunk_meshes.keys():
		rebuild_chunk(chunk_coord)


func _build_material_atlas() -> ImageTexture:
	var atlas := Image.create(
		SOURCE_SIZE.x * MATERIAL_COUNT, SOURCE_SIZE.y, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.MAGENTA)
	for definition in Catalog.MATERIALS:
		var material_id: int = int(definition.id)
		if material_id < 0 or material_id >= MATERIAL_COUNT:
			continue
		var texture: Texture2D = load(String(definition.texture_path)) as Texture2D
		assert(texture != null, "Missing Phase 2A terrain texture")
		var source: Image = texture.get_image()
		if source.get_size() != SOURCE_SIZE:
			source.resize(SOURCE_SIZE.x, SOURCE_SIZE.y, Image.INTERPOLATE_NEAREST)
		source.convert(Image.FORMAT_RGBA8)
		atlas.blit_rect(source, Rect2i(Vector2i.ZERO, SOURCE_SIZE), Vector2i(
			material_id * SOURCE_SIZE.x, 0))
	return ImageTexture.create_from_image(atlas)


func _build_material_palette() -> ImageTexture:
	var palette := Image.create(MATERIAL_COUNT, 1, false, Image.FORMAT_RGBA8)
	palette.fill(Color.MAGENTA)
	for definition in Catalog.MATERIALS:
		var material_id: int = int(definition.id)
		if material_id < 0 or material_id >= MATERIAL_COUNT:
			continue
		var texture: Texture2D = load(String(definition.texture_path)) as Texture2D
		assert(texture != null, "Missing Phase 2B terrain texture")
		var source: Image = texture.get_image()
		source.convert(Image.FORMAT_RGBA8)
		var average := Color(0.0, 0.0, 0.0, 0.0)
		for y in range(source.get_height()):
			for x in range(source.get_width()):
				average += source.get_pixel(x, y)
		average /= float(source.get_width() * source.get_height())
		palette.set_pixel(material_id, 0, average)
	return ImageTexture.create_from_image(palette)


func _recalculate_geometry_totals() -> void:
	total_vertices = 0
	total_triangles = 0
	total_faces = 0
	for stats in chunk_stats.values():
		total_vertices += int(stats.vertices)
		total_triangles += int(stats.triangles)
		total_faces += int(stats.faces)

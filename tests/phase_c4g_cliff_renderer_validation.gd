extends SceneTree
## C4G presentation-only selector, canonical surface, and rollback checks.

const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")
const OrganicCliffMeshBuilder = preload("res://scripts/organic_cliff_mesh_builder.gd")

var _heights: Dictionary = {}
var _materials: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_build_fixture()
	var legacy := _build(OrganicCliffMeshBuilder.ExperimentalCliffMode.LEGACY)
	var grid := _build(OrganicCliffMeshBuilder.ExperimentalCliffMode.GRID)
	var unified := _build(OrganicCliffMeshBuilder.ExperimentalCliffMode.UNIFIED)
	var stylised := _build(OrganicCliffMeshBuilder.ExperimentalCliffMode.STYLISED)
	var unified_repeat := _build(OrganicCliffMeshBuilder.ExperimentalCliffMode.UNIFIED)
	assert(legacy.shared_surface_sources.is_empty(), "LEGACY must not replace surfaces")
	assert(grid.shared_surface_sources.is_empty(), "GRID must preserve the C4F surface path")
	assert(unified.shared_surface_sources.size() == 32 * 32)
	assert(stylised.shared_surface_sources == unified.shared_surface_sources)
	assert(stylised.shared_surface_heights == unified.shared_surface_heights)
	assert(_geometry_result_signature(unified_repeat) == _geometry_result_signature(unified),
		"Canonical geometry must regenerate deterministically")
	assert(unified.face_count < grid.face_count,
		"Canonical square corners must remove C4F bevel-only segments")
	assert(unified.triangle_count >= unified.face_count * 2
		and unified.triangle_count <= unified.face_count * 4)
	assert(stylised.triangle_count > unified.triangle_count)
	assert(_shared_surface_count(unified) == 9)
	assert(_shared_surface_count(stylised) == 9)
	_test_chunk_seam_equivalence()

	var demo = load("res://main.tscn").instantiate()
	root.add_child(demo)
	await _wait_frames(8)
	var terrain = demo.terrain
	assert(terrain.get_cliff_rendering_mode() == TerrainRenderer.CliffRenderingMode.LEGACY)
	await _wait_until_ready(terrain)
	var authority_before := _authority_signature(terrain)
	var legacy_geometry_before := _geometry_signature(terrain)
	for mode in [
			TerrainRenderer.CliffRenderingMode.GRID,
			TerrainRenderer.CliffRenderingMode.UNIFIED,
			TerrainRenderer.CliffRenderingMode.STYLISED,
			TerrainRenderer.CliffRenderingMode.LEGACY]:
		terrain.set_cliff_rendering_mode(mode)
		await _wait_until_ready(terrain)
		assert(terrain.get_cliff_rendering_mode() == mode)
		_validate_loaded_chunk_mode(terrain, mode)
	assert(_authority_signature(terrain) == authority_before,
		"Rendering mode changes must not mutate terrain authority")
	assert(_geometry_signature(terrain) == legacy_geometry_before,
		"LEGACY rollback must reproduce its original geometry totals")
	for chunk in terrain.loaded_chunks.values():
		for layer in chunk.shared_boundary_surface_layers:
			if layer != null:
				assert(not layer.visible, "LEGACY rollback must hide C4G surfaces")
	print("PHASE_C4G_VALIDATION: PASS legacy=%d grid=%d unified=%d stylised=%d" % [
		legacy.triangle_count, grid.triangle_count,
		unified.triangle_count, stylised.triangle_count])
	quit(0)


func _build_fixture() -> void:
	for y in range(3):
		for x in range(3):
			_heights[Vector2i(x, y)] = 1 + (1 if x == 1 and y == 1 else 0)
			_materials[Vector2i(x, y)] = 4 if x < 2 else 3


func _build(mode: int) -> Dictionary:
	return _build_for_chunk(Vector2i.ZERO, mode)


func _build_for_chunk(chunk_coord: Vector2i, mode: int) -> Dictionary:
	return OrganicCliffMeshBuilder.build(
		chunk_coord, 3, 84521,
		func(pos: Vector2i) -> int: return int(_materials.get(pos, 3)),
		func(pos: Vector2i) -> int: return int(_heights.get(pos, 0)),
		{6: true}, true, true, true, true, 32, true, false, mode)


func _test_chunk_seam_equivalence() -> void:
	_heights.clear()
	_materials.clear()
	for y in range(10, 12):
		for x in range(10, 12):
			_heights[Vector2i(x, y)] = 2
			_materials[Vector2i(x, y)] = 4
	var inside := _build_for_chunk(
		Vector2i.ZERO, OrganicCliffMeshBuilder.ExperimentalCliffMode.UNIFIED)
	_heights.clear()
	_materials.clear()
	for y in range(10, 12):
		for x in range(31, 33):
			_heights[Vector2i(x, y)] = 2
			_materials[Vector2i(x, y)] = 4
	var seam_left := _build_for_chunk(
		Vector2i.ZERO, OrganicCliffMeshBuilder.ExperimentalCliffMode.UNIFIED)
	var seam_right := _build_for_chunk(
		Vector2i.RIGHT, OrganicCliffMeshBuilder.ExperimentalCliffMode.UNIFIED)
	assert(int(inside.face_count) == int(seam_left.face_count) + int(seam_right.face_count))
	assert(int(inside.triangle_count)
		== int(seam_left.triangle_count) + int(seam_right.triangle_count))
	assert(_shared_surface_count(seam_left) + _shared_surface_count(seam_right) == 4)
	_build_fixture()


func _geometry_result_signature(result: Dictionary) -> PackedInt64Array:
	return PackedInt64Array([
		int(result.face_count), int(result.vertex_count), int(result.triangle_count),
		int(result.edge_component_count), int(result.shadow_count),
	])


func _shared_surface_count(result: Dictionary) -> int:
	var count: int = 0
	for source_id in result.shared_surface_sources:
		if int(source_id) >= 0:
			count += 1
	return count


func _authority_signature(terrain) -> PackedInt32Array:
	var signature := PackedInt32Array()
	for pos in [Vector2i.ZERO, Vector2i(1, 1), Vector2i(31, 0), Vector2i(32, 0)]:
		signature.append(terrain.get_world_cell(pos))
		signature.append(terrain.get_world_surface_elevation(pos))
	return signature


func _geometry_signature(terrain) -> PackedInt64Array:
	var signature := PackedInt64Array()
	var faces: int = 0
	var vertices: int = 0
	var triangles: int = 0
	for chunk in terrain.loaded_chunks.values():
		var stats: Dictionary = chunk.get_organic_cliff_geometry_stats()
		faces += int(stats.face_count)
		vertices += int(stats.vertex_count)
		triangles += int(stats.triangle_count)
	signature.append_array([terrain.loaded_chunks.size(), faces, vertices, triangles])
	return signature


func _validate_loaded_chunk_mode(terrain, mode: int) -> void:
	var shared_cell_count: int = 0
	var shared_visible_count: int = 0
	for chunk in terrain.loaded_chunks.values():
		assert(chunk._experimental_cliff_mode == mode)
		for layer in chunk.shared_boundary_surface_layers:
			if layer != null:
				shared_cell_count += layer.get_used_cells().size()
				shared_visible_count += 1 if layer.visible else 0
	if mode >= TerrainRenderer.CliffRenderingMode.UNIFIED:
		assert(shared_cell_count > 0, "Shared-boundary mode must populate canonical surfaces")
		assert(shared_visible_count > 0, "Shared-boundary surfaces must become visible atomically")
	else:
		assert(shared_visible_count == 0, "LEGACY/GRID must keep canonical surfaces hidden")


func _wait_until_ready(terrain) -> void:
	for _frame in range(600):
		if terrain.get_pending_chunk_count() == 0:
			await _wait_frames(2)
			return
		await process_frame
	assert(false, "C4G runtime switch did not settle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame

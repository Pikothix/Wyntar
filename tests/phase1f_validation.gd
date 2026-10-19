extends SceneTree
## Phase 1F validates deterministic resumable geometry, shared halo reuse,
## atomic edit replacement, stale-job invalidation and pending mode changes.

const OrganicCliffMeshBuilder = preload("res://scripts/organic_cliff_mesh_builder.gd")

var failures: Array[String] = []
var demo
var terrain


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_incremental_equivalence()
	await _test_runtime_job_lifecycle()
	if failures.is_empty():
		print("PHASE1F_VALIDATION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE1F_VALIDATION: FAIL (%d)" % failures.size())
	quit(1)


func _test_incremental_equivalence() -> void:
	var heights := PackedByteArray()
	var materials := PackedInt32Array()
	heights.resize(34 * 34)
	materials.resize(34 * 34)
	materials.fill(3)
	for halo_y in range(34):
		for halo_x in range(34):
			var world_pos := Vector2i(halo_x - 1, halo_y - 1)
			if world_pos.x >= 3 and world_pos.x <= 27 and world_pos.y >= 2 and world_pos.y <= 25:
				heights[halo_y * 34 + halo_x] = 1 + posmod(world_pos.x / 7 + world_pos.y / 6, 3)
				materials[halo_y * 34 + halo_x] = 4 if posmod(world_pos.x + world_pos.y, 5) else 2
	var state: Dictionary = OrganicCliffMeshBuilder.create_incremental(
		Vector2i.ZERO, 3, 84521, materials, heights, {0: true}, true, true)
	var previous_index: int = 0
	while not OrganicCliffMeshBuilder.is_incremental_ready(state):
		var processed: int = OrganicCliffMeshBuilder.process_incremental(state, 7)
		_expect(processed <= 7 and int(state.cell_index) > previous_index,
			"each geometry quantum is bounded and resumes forward")
		previous_index = int(state.cell_index)
	var incremental: Dictionary = OrganicCliffMeshBuilder.finalize_incremental(state)
	var height_lookup := func(pos: Vector2i) -> int:
		var local := pos + Vector2i.ONE
		if local.x < 0 or local.y < 0 or local.x >= 34 or local.y >= 34:
			return 0
		return int(heights[local.y * 34 + local.x])
	var material_lookup := func(pos: Vector2i) -> int:
		var local := pos + Vector2i.ONE
		if local.x < 0 or local.y < 0 or local.x >= 34 or local.y >= 34:
			return 3
		return int(materials[local.y * 34 + local.x])
	var synchronous: Dictionary = OrganicCliffMeshBuilder.build(
		Vector2i.ZERO, 3, 84521, material_lookup, height_lookup,
		{0: true}, true, true)
	_expect(_geometry_signature(incremental) == _geometry_signature(synchronous),
		"incremental scheduling preserves Phase 1E geometry byte-for-byte")


func _test_runtime_job_lifecycle() -> void:
	demo = load("res://main.tscn").instantiate()
	root.add_child(demo)
	await _wait_frames(6)
	demo.cursor.visible = false
	terrain = demo.terrain
	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)
	var center := Vector2i(16000, 8000)
	for y in range(-18, 19):
		for x in range(-24, 25):
			terrain.world.set_override(center + Vector2i(x, y), 4)
			terrain.world.set_elevation_override(
				center + Vector2i(x, y), 3 if y < 7 + posmod(x, 4) else 0)
	terrain._invalidate_streamed_chunks()
	await _move_camera(center)
	var chunk_coord: Vector2i = terrain.world_cell_to_chunk(center)
	var chunk = terrain.loaded_chunks[chunk_coord]
	var old_mesh: ArrayMesh = chunk.organic_cliff_mesh_layers[2].mesh
	var old_mesh_id: int = old_mesh.get_instance_id()
	var terrain_authority_before: String = JSON.stringify(
		terrain.export_authoritative_snapshot().terrain)
	terrain.set_world_elevation(center, 0)
	await process_frame
	_expect(terrain.get_pending_chunk_count() > 0,
		"editing creates a resumable organic replacement job")
	_expect(chunk.organic_cliff_mesh_layers[2].mesh.get_instance_id() == old_mesh_id,
		"the previous complete mesh remains visible while replacement is pending")
	# Invalidate the unfinished snapshot twice; only the final authoritative edit
	# is allowed to commit.
	terrain.set_world_elevation(center, 2)
	terrain.set_world_elevation(center, 1)
	terrain.set_refined_cliff_silhouettes_enabled(false)
	terrain.set_refined_cliff_silhouettes_enabled(true)
	terrain.set_unified_cliff_components_enabled(false)
	terrain.set_unified_cliff_components_enabled(true)
	await _wait_until_idle()
	_expect(chunk.organic_cliff_mesh_layers[2].mesh.get_instance_id() != old_mesh_id,
		"the newest complete replacement commits after stale jobs are discarded")
	_expect(terrain.get_world_surface_elevation(center) == 1,
		"repeated pending edits preserve the latest authoritative elevation")
	_expect(terrain.is_refined_cliff_silhouettes_enabled()
		and terrain.is_unified_cliff_components_enabled(),
		"the final requested Phase 1E mode wins while builds are pending")
	var stats: Dictionary = chunk.get_organic_cliff_geometry_stats()
	_expect(int(stats.height_query_count) == 34 * 34
		and int(stats.material_query_count) == 34 * 34,
		"one sampled 34x34 halo supplies each replacement")
	_expect(int(stats.mesh_count) + int(stats.edge_mesh_count)
		+ int(stats.shadow_mesh_count) <= 9,
		"cliffs stay batched by component and elevation rather than by cell")
	var authority_after_mode_changes: String = JSON.stringify(
		terrain.export_authoritative_snapshot().terrain)
	_expect(authority_after_mode_changes != terrain_authority_before,
		"only the requested terrain edit changes authoritative terrain")
	# Rapid movement must cancel jobs for chunks that leave the retained region.
	terrain.set_world_elevation(center + Vector2i(1, 0), 0)
	var distant := Vector2i(-16000, -8000)
	demo.camera.position = Vector2(distant * terrain.TILE_SIZE)
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	await _wait_until_idle()
	_expect(not terrain.loaded_chunks.has(chunk_coord),
		"rapid camera movement unloads the old chunk and cancels its replacement")


func _geometry_signature(result: Dictionary) -> Array:
	var signature: Array = [
		int(result.face_count), int(result.edge_component_count),
		int(result.shadow_count), int(result.vertex_count), int(result.triangle_count)]
	for key in ["meshes", "edge_meshes", "shadow_meshes"]:
		for mesh in result[key]:
			if mesh == null:
				signature.append(null)
				continue
			signature.append(hash(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]))
			signature.append(hash(mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]))
			signature.append(hash(mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]))
	return signature


func _move_camera(cell: Vector2i) -> void:
	demo.camera.position = Vector2(cell * terrain.TILE_SIZE) + Vector2(16, 16)
	demo.camera.zoom = Vector2.ONE
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	await _wait_until_idle()


func _wait_until_idle(max_frames: int = 3000) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	assert(false, "Phase 1F validation streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

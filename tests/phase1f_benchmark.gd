extends SceneTree
## Reproducible Phase 1F streaming, mode-switch and editing benchmark using the
## same dense cliff fixture as Phase 1E.

const OUTPUT_PATH := "res://.artifacts/phase1f_benchmark.json"
const SAMPLE_FRAMES := 180

var demo
var terrain


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	demo = load("res://main.tscn").instantiate()
	demo.chunk_profiling_enabled = true
	root.add_child(demo)
	await _wait_frames(8)
	terrain = demo.terrain
	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.cursor.visible = false
	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)
	terrain.set_organic_cliff_geometry_enabled(true)
	terrain.set_unified_cliff_components_enabled(true)
	terrain.set_refined_cliff_silhouettes_enabled(true)
	var center := Vector2i(10200, 5100)
	_build_fixture(center)
	terrain._invalidate_streamed_chunks()
	demo.camera.position = Vector2(center * terrain.TILE_SIZE) + Vector2(16, 16)
	demo.camera.zoom = Vector2.ONE
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	var profiled_streaming: Dictionary = await _sample_until_idle()
	var detailed_geometry: Dictionary = _geometry_totals()
	# Repeat the identical stream without fine-grained profiling so the primary
	# frame-impact figures represent normal play rather than instrumentation.
	terrain.profiling_enabled = false
	terrain.reset_incremental_cliff_scheduler_metrics()
	terrain._invalidate_streamed_chunks()
	demo._update_visible_world_region()
	var streaming: Dictionary = await _sample_until_idle()
	var steady: Dictionary = await _sample_fixed_frames(SAMPLE_FRAMES)
	terrain.set_refined_cliff_silhouettes_enabled(false)
	await _wait_until_idle()
	terrain.reset_incremental_cliff_scheduler_metrics()
	var toggle_enqueue_started: int = Time.get_ticks_usec()
	terrain.set_refined_cliff_silhouettes_enabled(true)
	var toggle_enqueue_usec: int = Time.get_ticks_usec() - toggle_enqueue_started
	var toggle: Dictionary = await _sample_until_idle()
	toggle.enqueue_ms = float(toggle_enqueue_usec) / 1000.0
	var old_mesh_id: int = _representative_mesh_id()
	terrain.reset_incremental_cliff_scheduler_metrics()
	var edit_started: int = Time.get_ticks_usec()
	var edits: Array[Dictionary] = [{
		"cell": center, "kind": "elevation",
		"state": {"has_override": true, "value": 0},
	}]
	var changed: int = terrain.apply_world_edit_states(edits)
	var old_mesh_preserved: bool = _representative_mesh_id() == old_mesh_id
	var edit: Dictionary = await _sample_until_idle()
	edit.changed = changed
	edit.elapsed_wall_ms = float(Time.get_ticks_usec() - edit_started) / 1000.0
	edit.old_mesh_preserved_while_pending = old_mesh_preserved
	edit.dirty_chunks = terrain.last_edit_dirty_chunk_count
	var result := {
		"display_server": DisplayServer.get_name(),
		"streaming": streaming,
		"profiled_streaming": profiled_streaming,
		"steady_state": steady,
		"mode_toggle": toggle,
		"editing": edit,
		"geometry": detailed_geometry,
		"scheduler": terrain.get_incremental_cliff_scheduler_metrics(),
	}
	var encoded: String = JSON.stringify(result, "\t")
	var specific_path: String = (
		"res://.artifacts/phase1f_benchmark_headless.json"
		if DisplayServer.get_name() == "headless"
		else "res://.artifacts/phase1f_benchmark_graphical.json")
	for output_path in [OUTPUT_PATH, specific_path]:
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file == null:
			push_error("Could not write Phase 1F benchmark result")
			quit(1)
			return
		file.store_string(encoded)
		file.close()
	print("PHASE1F_BENCHMARK: %s" % JSON.stringify(result))
	quit(0)


func _sample_until_idle(max_frames: int = 3000) -> Dictionary:
	var values: Array[float] = []
	var geometry_frame_values: Array[float] = []
	var draw_total: float = 0.0
	var visible_ready_frame: int = -1
	var started_usec: int = Time.get_ticks_usec()
	for frame_index in range(max_frames):
		var frame_started_usec: int = Time.get_ticks_usec()
		await process_frame
		values.append(float(Time.get_ticks_usec() - frame_started_usec) / 1000.0)
		geometry_frame_values.append(
			float(terrain.organic_geometry_processing_usec_this_frame) / 1000.0)
		draw_total += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		if visible_ready_frame < 0 and terrain.get_pending_visible_chunk_count() == 0:
			visible_ready_frame = frame_index + 1
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return _summarize(
				values, geometry_frame_values, draw_total,
				Time.get_ticks_usec() - started_usec, visible_ready_frame)
	assert(false, "Phase 1F benchmark did not become idle")
	return {}


func _sample_fixed_frames(frame_count: int) -> Dictionary:
	var values: Array[float] = []
	var geometry_values: Array[float] = []
	var draw_total: float = 0.0
	var started_usec: int = Time.get_ticks_usec()
	for _frame in range(frame_count):
		var frame_started_usec: int = Time.get_ticks_usec()
		await process_frame
		values.append(float(Time.get_ticks_usec() - frame_started_usec) / 1000.0)
		geometry_values.append(
			float(terrain.organic_geometry_processing_usec_this_frame) / 1000.0)
		draw_total += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	return _summarize(
		values, geometry_values, draw_total,
		Time.get_ticks_usec() - started_usec, 0)


func _summarize(
		values: Array[float], geometry_values: Array[float], draw_total: float,
		elapsed_usec: int, visible_ready_frame: int) -> Dictionary:
	values.sort()
	geometry_values.sort()
	var total: float = 0.0
	var geometry_total: float = 0.0
	for value in values:
		total += value
	for value in geometry_values:
		geometry_total += value
	return {
		"frames": values.size(),
		"elapsed_ms": float(elapsed_usec) / 1000.0,
		"visible_ready_frame": visible_ready_frame,
		"average_frame_ms": total / values.size(),
		"p95_frame_ms": _percentile(values, 0.95),
		"p99_frame_ms": _percentile(values, 0.99),
		"worst_frame_ms": values[-1],
		"geometry_cpu_ms": geometry_total,
		"worst_geometry_frame_ms": geometry_values[-1],
		"average_draw_calls": draw_total / values.size(),
		"static_memory_mib": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"worst_chunk_finalisation_ms": float(terrain.worst_chunk_finalisation_usec) / 1000.0,
	}


func _geometry_totals() -> Dictionary:
	var totals := {
		"build_ms": 0.0, "shared_halo_sampling_ms": 0.0,
		"face_construction_ms": 0.0, "contour_generation_ms": 0.0,
		"vertex_assembly_ms": 0.0,
		"mesh_resource_ms": 0.0, "scene_attachment_ms": 0.0,
		"face_meshes": 0, "edge_meshes": 0, "shadow_meshes": 0,
		"faces": 0, "edge_components": 0, "shadows": 0,
		"vertices": 0, "triangles": 0,
		"height_queries": 0, "material_queries": 0,
	}
	for chunk in terrain.loaded_chunks.values():
		var stats: Dictionary = chunk.get_organic_cliff_geometry_stats()
		totals.build_ms += float(stats.build_usec) / 1000.0
		totals.shared_halo_sampling_ms += float(stats.sampling_usec) / 1000.0
		totals.face_construction_ms += float(stats.face_construction_usec) / 1000.0
		totals.contour_generation_ms += float(stats.contour_generation_usec) / 1000.0
		totals.vertex_assembly_ms += float(stats.vertex_assembly_usec) / 1000.0
		totals.mesh_resource_ms += float(stats.mesh_resource_usec) / 1000.0
		totals.scene_attachment_ms += float(stats.scene_attachment_usec) / 1000.0
		totals.face_meshes += int(stats.mesh_count)
		totals.edge_meshes += int(stats.edge_mesh_count)
		totals.shadow_meshes += int(stats.shadow_mesh_count)
		totals.faces += int(stats.face_count)
		totals.edge_components += int(stats.edge_component_count)
		totals.shadows += int(stats.shadow_count)
		totals.vertices += int(stats.vertex_count)
		totals.triangles += int(stats.triangle_count)
		totals.height_queries += int(stats.height_query_count)
		totals.material_queries += int(stats.material_query_count)
	totals.chunks = terrain.loaded_chunks.size()
	return totals


func _representative_mesh_id() -> int:
	var chunk = terrain.loaded_chunks[terrain.world_cell_to_chunk(Vector2i(10200, 5100))]
	for layer in chunk.organic_cliff_mesh_layers:
		if layer != null and layer.mesh != null:
			return layer.mesh.get_instance_id()
	return 0


func _build_fixture(center: Vector2i) -> void:
	_fill(center - Vector2i(54, 42), Vector2i(108, 84), 3, 0)
	for y in range(-38, 39):
		for x in range(-50, 51):
			var ridge: float = sin(float(x) * 0.28) + cos(float(y) * 0.23)
			var height: int = clampi(floori((ridge + 2.0) * 0.99), 0, 3)
			if height > 0:
				_set_cell(center + Vector2i(x, y), 4 if (x + y) % 4 else 2, height)


func _fill(origin: Vector2i, size: Vector2i, material_id: int, elevation: int) -> void:
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			_set_cell(Vector2i(x, y), material_id, elevation)


func _set_cell(pos: Vector2i, material_id: int, elevation: int) -> void:
	terrain.world.set_override(pos, material_id)
	terrain.world.set_elevation_override(pos, elevation)


func _wait_until_idle(max_frames: int = 3000) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	assert(false, "Phase 1F benchmark wait did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _percentile(values: Array[float], percentile: float) -> float:
	return values[clampi(ceili(values.size() * percentile) - 1, 0, values.size() - 1)]

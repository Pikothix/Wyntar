extends SceneTree
## Phase 3A startup, atlas-cache, streaming and repeated-retirement benchmark.

const ProcTrees = preload("res://scripts/procgen/proc_trees.gd")
const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")

var terrain


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var family_started: int = Time.get_ticks_usec()
	for archetype in ["deciduous", "conifer"]:
		for variant in range(12):
			ProcTrees.generate_tree(
				31001 + variant * 7919, 32, archetype, "GRASS", "large", "mature")
	var family_generation_usec: int = Time.get_ticks_usec() - family_started

	var startup_started: int = Time.get_ticks_usec()
	terrain = TerrainRenderer.new()
	terrain.profiling_enabled = true
	root.add_child(terrain)
	await process_frame
	var startup_usec: int = Time.get_ticks_usec() - startup_started
	var atlas_before: Dictionary = terrain.get_environment_atlas_metrics()
	var procedural_texture_id: int = int(atlas_before.procedural_texture_instance_id)
	var legacy_texture_id: int = int(atlas_before.legacy_texture_instance_id)
	var toggle_started: int = Time.get_ticks_usec()
	for toggle_index in range(20):
		terrain.set_procedural_vegetation_enabled(toggle_index % 2 == 0)
	terrain.set_procedural_vegetation_enabled(true)
	var toggle_usec: int = Time.get_ticks_usec() - toggle_started

	var routes: Array[Rect2] = [
		Rect2(Vector2(-640, -360), Vector2(1280, 720)),
		Rect2(Vector2(32000, 16000), Vector2(1280, 720)),
		Rect2(Vector2(-24000, 28000), Vector2(1280, 720)),
		Rect2(Vector2(64000, -32000), Vector2(1280, 720)),
		Rect2(Vector2(-640, -360), Vector2(1280, 720)),
	]
	var streams: Array[Dictionary] = []
	for visible_rect in routes:
		terrain.reset_incremental_cliff_scheduler_metrics()
		terrain.update_visible_world_rect(visible_rect)
		streams.append(await _sample_until_settled())
	var atlas_after: Dictionary = terrain.get_environment_atlas_metrics()
	var phase1g_baseline: Dictionary = _read_phase1g_baseline()
	var result := {
		"display_server": DisplayServer.get_name(),
		"family_24_variant_generation_ms": float(family_generation_usec) / 1000.0,
		"startup_ms": float(startup_usec) / 1000.0,
		"atlas_generation_ms": float(atlas_before.generation_usec) / 1000.0,
		"legacy_atlas_generation_ms": float(atlas_before.legacy_generation_usec) / 1000.0,
		"atlas_variants": int(atlas_before.variant_count),
		"procedural_tree_variants": int(atlas_before.procedural_tree_variant_count),
		"atlas_dimensions": atlas_before.dimensions,
		"atlas_texture_memory_mib": float(atlas_before.texture_memory_bytes) / 1048576.0,
		"twenty_toggle_ms": float(toggle_usec) / 1000.0,
		"cache_texture_ids_stable": (
			procedural_texture_id == int(atlas_after.procedural_texture_instance_id)
			and legacy_texture_id == int(atlas_after.legacy_texture_instance_id)),
		"runtime_generation_count": int(atlas_after.runtime_generation_count),
		"logical_cache_hit_rate": 1.0 if int(atlas_after.runtime_generation_count) == 0 else 0.0,
		"streaming_runs": streams,
		"streaming_aggregate": _aggregate(streams),
		"final_static_memory_mib": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"final_nodes": roundi(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"final_resources": roundi(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"phase1g_baseline": phase1g_baseline,
	}
	var suffix: String = "headless" if DisplayServer.get_name() == "headless" else "graphical"
	var output_path: String = "res://.artifacts/phase3a_benchmark_%s.json" % suffix
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("PHASE3A_BENCHMARK: %s" % JSON.stringify(result))
	terrain.queue_free()
	quit(0)


func _sample_until_settled(max_frames: int = 3000) -> Dictionary:
	var frames: Array[float] = []
	var draw_total: float = 0.0
	var memory_peak: float = 0.0
	var preparation_before: int = terrain.profile_total_environment_usec
	var submission_before: int = terrain.profile_total_environment_submission_usec
	var started_usec: int = Time.get_ticks_usec()
	for _frame in range(max_frames):
		var frame_started: int = Time.get_ticks_usec()
		await process_frame
		frames.append(float(Time.get_ticks_usec() - frame_started) / 1000.0)
		draw_total += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		memory_peak = maxf(memory_peak, Performance.get_monitor(Performance.MEMORY_STATIC))
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_chunk_retirement_count() == 0):
			frames.sort()
			var total: float = 0.0
			for value in frames:
				total += value
			return {
				"frames": frames.size(),
				"elapsed_ms": float(Time.get_ticks_usec() - started_usec) / 1000.0,
				"average_frame_ms": total / frames.size(),
				"p95_frame_ms": _percentile(frames, 0.95),
				"p99_frame_ms": _percentile(frames, 0.99),
				"worst_frame_ms": frames[-1],
				"average_draw_calls": draw_total / frames.size(),
				"peak_static_memory_mib": memory_peak / 1048576.0,
				"objects": terrain.get_visible_environment_object_count(),
				"environment_preparation_ms": float(
					terrain.profile_total_environment_usec - preparation_before) / 1000.0,
				"environment_submission_ms": float(
					terrain.profile_total_environment_submission_usec - submission_before) / 1000.0,
				"worst_chunk_finalisation_ms": float(terrain.worst_chunk_finalisation_usec) / 1000.0,
			}
	assert(false, "Phase 3A benchmark did not settle")
	return {}


func _aggregate(samples: Array[Dictionary]) -> Dictionary:
	var average_total: float = 0.0
	var p95_total: float = 0.0
	var p99_total: float = 0.0
	var worst: float = 0.0
	var draw_total: float = 0.0
	for sample in samples:
		average_total += float(sample.average_frame_ms)
		p95_total += float(sample.p95_frame_ms)
		p99_total += float(sample.p99_frame_ms)
		worst = maxf(worst, float(sample.worst_frame_ms))
		draw_total += float(sample.average_draw_calls)
	return {
		"runs": samples.size(),
		"mean_average_frame_ms": average_total / samples.size(),
		"mean_p95_frame_ms": p95_total / samples.size(),
		"mean_p99_frame_ms": p99_total / samples.size(),
		"worst_frame_ms": worst,
		"mean_average_draw_calls": draw_total / samples.size(),
	}


func _read_phase1g_baseline() -> Dictionary:
	var suffix: String = "headless" if DisplayServer.get_name() == "headless" else "graphical"
	var path: String = "res://.artifacts/phase1g_benchmark_%s.json" % suffix
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {}
	return parsed.get("streaming_aggregate", {})


func _percentile(values: Array[float], percentile: float) -> float:
	return values[clampi(ceili(values.size() * percentile) - 1, 0, values.size() - 1)]

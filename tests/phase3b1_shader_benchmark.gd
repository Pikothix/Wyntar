extends "res://tests/phase1g_benchmark.gd"
## Controlled same-session comparison of the pre-3B and current cliff shaders.
## Both shaders are compiled and warmed before ten alternating measured runs.

const OUTPUT_PATH := "res://screenshots/phase3b1_shader_benchmark_graphical.json"
const BASELINE_SHADER := preload(
	"res://tests/fixtures/phase3b_pre_geological_cliff.gdshader")
const PROTOTYPE_SHADER := preload("res://shaders/cliff_procedural.gdshader")
const STEADY_RUNS_PER_MODE := 5
const STEADY_FRAMES_PER_RUN := 240
const SWITCH_WARMUP_FRAMES := 45
const COMPILE_WARMUP_FRAMES := 180
const STREAM_RUNS_PER_MODE := 3

var material_records: Array[Dictionary] = []


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
	await _move_camera(center)
	material_records = _collect_material_records()

	# Compile, render and synchronise both variants before any timed frame.
	await _compile_and_warm(BASELINE_SHADER)
	await _compile_and_warm(PROTOTYPE_SHADER)
	await _capture_comparison(center)
	await _capture_fractional_pan(center)
	_set_camera(center)
	await _wait_frames(SWITCH_WARMUP_FRAMES)

	var steady_runs := {"baseline": [], "prototype": []}
	for run_index in range(STEADY_RUNS_PER_MODE * 2):
		var label: String = "baseline" if run_index % 2 == 0 else "prototype"
		_set_cliff_shader(BASELINE_SHADER if label == "baseline" else PROTOTYPE_SHADER)
		await _wait_frames(SWITCH_WARMUP_FRAMES)
		steady_runs[label].append(await _measure_steady_run(label, run_index / 2))

	var stream_runs := {"baseline": [], "prototype": []}
	for run_index in range(STREAM_RUNS_PER_MODE * 2):
		var label: String = "prototype" if run_index % 2 == 0 else "baseline"
		_set_cliff_shader(PROTOTYPE_SHADER if label == "prototype" else BASELINE_SHADER)
		await _wait_frames(SWITCH_WARMUP_FRAMES)
		stream_runs[label].append(await _measure_streaming_run(label, run_index / 2))

	var baseline_summary: Dictionary = _aggregate_steady(steady_runs.baseline)
	var prototype_summary: Dictionary = _aggregate_steady(steady_runs.prototype)
	var result := {
		"engine": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"fixture": "phase1g_dense_exact",
		"viewport": [1280, 720],
		"camera_cell": [center.x, center.y],
		"baseline_commit": "9f2d75d",
		"baseline_shader": BASELINE_SHADER.resource_path,
		"prototype_shader": PROTOTYPE_SHADER.resource_path,
		"steady_frames_per_run": STEADY_FRAMES_PER_RUN,
		"switch_warmup_frames": SWITCH_WARMUP_FRAMES,
		"compile_warmup_frames": COMPILE_WARMUP_FRAMES,
		"steady_run_order": [
			"baseline", "prototype", "baseline", "prototype", "baseline",
			"prototype", "baseline", "prototype", "baseline", "prototype"],
		"steady_runs": _serializable_runs(steady_runs),
		"steady_aggregate": {
			"baseline": baseline_summary,
			"prototype": prototype_summary,
			"mean_regression_percent": _percent_change(
				float(baseline_summary.mean_frame_ms),
				float(prototype_summary.mean_frame_ms)),
			"median_regression_percent": _percent_change(
				float(baseline_summary.median_frame_ms),
				float(prototype_summary.median_frame_ms)),
			"p95_regression_percent": _percent_change(
				float(baseline_summary.p95_frame_ms),
				float(prototype_summary.p95_frame_ms)),
		},
		"stream_run_order": [
			"prototype", "baseline", "prototype",
			"baseline", "prototype", "baseline"],
		"stream_runs": stream_runs,
		"stream_aggregate": {
			"baseline": _aggregate_streaming(stream_runs.baseline),
			"prototype": _aggregate_streaming(stream_runs.prototype),
		},
		"material_count": material_records.size(),
		"final_nodes": roundi(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"final_resources": roundi(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"static_memory_mib": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
	}
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not write Phase 3B.1 benchmark")
		quit(1)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("PHASE3B1_SHADER_BENCHMARK: %s" % JSON.stringify(result))
	quit(0)


func _collect_material_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var seen: Dictionary = {}
	var candidates: Array = [terrain.organic_cliff_material]
	candidates.append_array(terrain.cliff_material_by_source.values())
	candidates.append_array(terrain.cliff_shadow_material_by_source.values())
	for candidate in candidates:
		if not candidate is ShaderMaterial:
			continue
		var material: ShaderMaterial = candidate
		if seen.has(material.get_instance_id()):
			continue
		seen[material.get_instance_id()] = true
		records.append({
			"material": material,
			"source_texture": material.get_shader_parameter("source_texture"),
			"dirt_texture": material.get_shader_parameter("dirt_texture"),
			"stone_texture": material.get_shader_parameter("stone_texture"),
			"procedural_enabled": material.get_shader_parameter("procedural_enabled"),
			"stone_style": material.get_shader_parameter("stone_style"),
			"shoreline": material.get_shader_parameter("shoreline"),
			"contact_shadow": material.get_shader_parameter("contact_shadow"),
			"geometry_mesh": material.get_shader_parameter("geometry_mesh"),
			"combined_geometry": material.get_shader_parameter("combined_geometry"),
			"seed_offset": material.get_shader_parameter("seed_offset"),
		})
	return records


func _set_cliff_shader(shader: Shader) -> void:
	for record in material_records:
		var material: ShaderMaterial = record.material
		material.shader = shader
		for parameter in [
			"source_texture", "dirt_texture", "stone_texture",
			"procedural_enabled", "stone_style", "shoreline", "contact_shadow",
			"geometry_mesh", "combined_geometry", "seed_offset"]:
			material.set_shader_parameter(parameter, record[parameter])
		if shader == PROTOTYPE_SHADER:
			material.set_shader_parameter("detail_level", 1.0)


func _compile_and_warm(shader: Shader) -> void:
	_set_cliff_shader(shader)
	await _wait_frames(COMPILE_WARMUP_FRAMES)
	await _wait_frames(15)


func _measure_steady_run(label: String, index: int) -> Dictionary:
	var samples: Array[float] = []
	var draw_calls_total: float = 0.0
	var primitives_total: float = 0.0
	for _frame in range(STEADY_FRAMES_PER_RUN):
		var started: int = Time.get_ticks_usec()
		await process_frame
		samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
		draw_calls_total += Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		primitives_total += Performance.get_monitor(
			Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var summary: Dictionary = _summarize_frames(samples)
	summary.label = label
	summary.index = index
	summary.average_draw_calls = draw_calls_total / STEADY_FRAMES_PER_RUN
	summary.average_primitives = primitives_total / STEADY_FRAMES_PER_RUN
	summary.samples = samples
	return summary


func _measure_streaming_run(label: String, index: int) -> Dictionary:
	terrain.reset_incremental_cliff_scheduler_metrics()
	terrain._invalidate_streamed_chunks()
	demo._update_visible_world_region()
	var frames: Array[float] = []
	var chunk_cpu_ms: float = 0.0
	var geometry_cpu_ms: float = 0.0
	for _frame in range(3000):
		var started: int = Time.get_ticks_usec()
		await process_frame
		frames.append(float(Time.get_ticks_usec() - started) / 1000.0)
		chunk_cpu_ms += float(terrain.chunk_processing_usec_this_frame) / 1000.0
		geometry_cpu_ms += float(
			terrain.organic_geometry_processing_usec_this_frame) / 1000.0
		if _is_ready() and terrain.get_pending_chunk_retirement_count() == 0:
			var result: Dictionary = _summarize_frames(frames)
			result.label = label
			result.index = index
			result.chunk_cpu_ms = chunk_cpu_ms
			result.geometry_cpu_ms = geometry_cpu_ms
			result.lifecycle = terrain.get_incremental_cliff_scheduler_metrics()
			return result
	assert(false, "Phase 3B.1 streaming sample did not settle")
	return {}


func _summarize_frames(values: Array[float]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total: float = 0.0
	for value in sorted:
		total += value
	return {
		"frames": sorted.size(),
		"mean_frame_ms": total / sorted.size(),
		"median_frame_ms": _percentile(sorted, 0.5),
		"p95_frame_ms": _percentile(sorted, 0.95),
		"worst_frame_ms": sorted[-1],
	}


func _aggregate_steady(runs: Array) -> Dictionary:
	var all_samples: Array[float] = []
	var draw_calls_total: float = 0.0
	var primitives_total: float = 0.0
	for run in runs:
		all_samples.append_array(run.samples)
		draw_calls_total += float(run.average_draw_calls)
		primitives_total += float(run.average_primitives)
	var summary: Dictionary = _summarize_frames(all_samples)
	summary.runs = runs.size()
	summary.average_draw_calls = draw_calls_total / runs.size()
	summary.average_primitives = primitives_total / runs.size()
	return summary


func _aggregate_streaming(runs: Array) -> Dictionary:
	var frame_means: Array[float] = []
	var chunk_cpu: Array[float] = []
	var geometry_cpu: Array[float] = []
	for run in runs:
		frame_means.append(float(run.mean_frame_ms))
		chunk_cpu.append(float(run.chunk_cpu_ms))
		geometry_cpu.append(float(run.geometry_cpu_ms))
	return {
		"runs": runs.size(),
		"mean_frame_ms": _mean(frame_means),
		"median_chunk_cpu_ms": _median(chunk_cpu),
		"mean_chunk_cpu_ms": _mean(chunk_cpu),
		"median_geometry_cpu_ms": _median(geometry_cpu),
		"mean_geometry_cpu_ms": _mean(geometry_cpu),
	}


func _serializable_runs(grouped: Dictionary) -> Dictionary:
	var result := {"baseline": [], "prototype": []}
	for label in ["baseline", "prototype"]:
		for run in grouped[label]:
			var copy: Dictionary = run.duplicate()
			copy.erase("samples")
			result[label].append(copy)
	return result


func _median(values: Array[float]) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return _percentile(sorted, 0.5)


func _percent_change(baseline: float, prototype: float) -> float:
	return (prototype / baseline - 1.0) * 100.0


func _capture_comparison(center: Vector2i) -> void:
	for zoom in [1.0, 3.0]:
		demo.camera.position = Vector2(center * terrain.TILE_SIZE) + Vector2(16, 16)
		demo.camera.zoom = Vector2.ONE * zoom
		demo.camera.force_update_scroll()
		demo._update_visible_world_region()
		await _wait_frames(10)
		_set_cliff_shader(BASELINE_SHADER)
		await _wait_frames(15)
		await _save_frame("phase3b1_baseline_dense_%s.png" % _zoom_label(zoom))
		_set_cliff_shader(PROTOTYPE_SHADER)
		await _wait_frames(15)
		await _save_frame("phase3b1_prototype_dense_%s.png" % _zoom_label(zoom))


func _capture_fractional_pan(center: Vector2i) -> void:
	_set_cliff_shader(PROTOTYPE_SHADER)
	var base := Vector2(center * terrain.TILE_SIZE) + Vector2(16, 16)
	demo.camera.zoom = Vector2.ONE * 3.0
	for step_index in range(8):
		var offset := Vector2(float(step_index) * 0.25, float(step_index) * 0.125)
		demo.camera.position = base + offset
		demo.camera.force_update_scroll()
		demo._update_visible_world_region()
		await _wait_frames(4)
		await _save_frame("phase3b1_shimmer_%02d.png" % step_index)


func _save_frame(file_name: String) -> void:
	var image: Image = root.get_texture().get_image()
	if image == null or image.save_png("res://screenshots/%s" % file_name) != OK:
		push_error("Could not save Phase 3B.1 frame %s" % file_name)
		quit(1)


func _zoom_label(zoom: float) -> String:
	return "1_0x" if is_equal_approx(zoom, 1.0) else "3_0x"

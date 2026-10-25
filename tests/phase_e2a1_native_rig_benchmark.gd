extends SceneTree
## E2A.1 native presentation benchmark. CPU transform updates and complete
## rendered frame time are measured independently for shared and unique art.

const Species = preload("res://scripts/creatures/creature_species.gd")
const Generator = preload("res://scripts/creatures/creature_generator.gd")
const Rig = preload("res://scripts/creatures/creature_rig.gd")
const PoseEvaluator = preload("res://scripts/creatures/creature_pose_evaluator.gd")
const RigVisualCache = preload("res://scripts/creatures/creature_rig_visual_cache.gd")
const RigPresenter = preload("res://scripts/creatures/creature_rig_presenter.gd")
const RigRenderer = preload("res://scripts/creatures/creature_rig_renderer.gd")

const COUNTS := [1, 10, 50, 100]
const UPDATE_BATCHES := 240
const FRAME_SAMPLES := 90

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var result := {
		"display_server": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"pose_evaluation": _benchmark_pose_evaluation(),
		"cpu_compositor_same_run": _benchmark_cpu_compositor(),
		"shared_artwork": {},
		"unique_artwork": {},
		"cpu_compositor_baseline": _read_json("res://.artifacts/phase_e2a_creature_rig_benchmark.json"),
	}
	for count in COUNTS:
		result.shared_artwork[str(count)] = await _benchmark_scenario(count, false)
	for count in COUNTS:
		result.unique_artwork[str(count)] = await _benchmark_scenario(count, true)
	var file := FileAccess.open("res://.artifacts/phase_e2a1_native_rig_benchmark.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("PHASE_E2A1_NATIVE_BENCHMARK: %s" % JSON.stringify(result))
	quit(0)

func _benchmark_pose_evaluation() -> Dictionary:
	var anatomy := _anatomy(0)
	var rig := Rig.build(anatomy)
	const SAMPLES := 20000
	var started := Time.get_ticks_usec()
	for index in range(SAMPLES):
		PoseEvaluator.evaluate_pose(rig, "walk", float(index) / 60.0)
	var total_usec := Time.get_ticks_usec() - started
	return {"samples": SAMPLES, "total_ms": float(total_usec) / 1000.0, "average_usec": float(total_usec) / SAMPLES}

func _benchmark_cpu_compositor() -> Dictionary:
	var anatomy := _anatomy(0)
	var rig := Rig.build(anatomy)
	var cache := RigVisualCache.new()
	var visual := cache.get_or_generate(anatomy, rig)
	var composer := RigRenderer.new()
	composer.configure(rig, visual)
	const SAMPLES := 300
	var started := Time.get_ticks_usec()
	for index in range(SAMPLES):
		var pose := PoseEvaluator.evaluate_pose(rig, "walk", float(index) / 60.0)
		composer.compose(pose)
	var total_usec := Time.get_ticks_usec() - started
	return {"samples": SAMPLES, "total_ms": float(total_usec) / 1000.0, "average_ms": float(total_usec) / 1000.0 / SAMPLES}

func _benchmark_scenario(count: int, unique_artwork: bool) -> Dictionary:
	var memory_before := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var cache := RigVisualCache.new()
	var rigs: Array[Dictionary] = []
	var visuals: Array[Dictionary] = []
	var art_started := Time.get_ticks_usec()
	for index in range(count):
		var anatomy := _anatomy(index if unique_artwork else 0)
		var rig := Rig.build(anatomy)
		rigs.append(rig)
		visuals.append(cache.get_or_generate(anatomy, rig))
	var art_texture_ms := float(Time.get_ticks_usec() - art_started) / 1000.0
	var stage := Node2D.new()
	root.add_child(stage)
	var presenters: Array[Node2D] = []
	var presenter_started := Time.get_ticks_usec()
	for index in range(count):
		var presenter := RigPresenter.new()
		presenter.position = Vector2(42 + (index % 10) * 68, 42 + (index / 10) * 68)
		presenter.configure(rigs[index], visuals[index])
		presenter.apply_pose(PoseEvaluator.evaluate_pose(rigs[index], "walk", float(index) * 0.037))
		stage.add_child(presenter)
		presenters.append(presenter)
	var presenter_setup_ms := float(Time.get_ticks_usec() - presenter_started) / 1000.0
	await process_frame
	await process_frame
	var poses: Array[Dictionary] = []
	for index in range(count):
		poses.append(PoseEvaluator.evaluate_pose(rigs[index], "walk", 0.31 + float(index) * 0.017))
	var update_started := Time.get_ticks_usec()
	for _batch in range(UPDATE_BATCHES):
		for index in range(count):
			presenters[index].apply_pose(poses[index])
	var update_total_usec := Time.get_ticks_usec() - update_started
	var frame_total_ms := 0.0
	var frame_worst_ms := 0.0
	for frame in range(FRAME_SAMPLES):
		var frame_started := Time.get_ticks_usec()
		for index in range(count):
			var pose := PoseEvaluator.evaluate_pose(rigs[index], "walk", float(frame) / 60.0 + float(index) * 0.017)
			presenters[index].apply_pose(pose)
		await process_frame
		var elapsed_ms := float(Time.get_ticks_usec() - frame_started) / 1000.0
		frame_total_ms += elapsed_ms
		frame_worst_ms = maxf(frame_worst_ms, elapsed_ms)
	var memory_after := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var scenario_result := {
		"creatures": count,
		"unique_artwork": unique_artwork,
		"artwork_and_texture_creation_ms": art_texture_ms,
		"presenter_setup_ms": presenter_setup_ms,
		"texture_creations": cache.texture_creation_count,
		"cache_entries": cache.entry_count(),
		"estimated_cache_bytes": cache.approximate_memory_bytes(),
		"observed_static_memory_delta_bytes": maxi(0, memory_after - memory_before),
		"native_update_total_ms": float(update_total_usec) / 1000.0,
		"native_update_average_usec_per_creature": float(update_total_usec) / float(UPDATE_BATCHES * count),
		"total_frame_average_ms": frame_total_ms / FRAME_SAMPLES,
		"total_frame_worst_ms": frame_worst_ms,
		"frame_samples": FRAME_SAMPLES,
	}
	stage.queue_free()
	await process_frame
	await process_frame
	return scenario_result

func _anatomy(index: int) -> Dictionary:
	return Generator.generate_creature(Species.SPECIES_ID, Generator.individual_seed(84521, index), 0.6, Generator.mixed_archetype(84521, index), true)

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

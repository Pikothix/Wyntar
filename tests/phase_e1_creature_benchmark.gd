extends SceneTree
## E1B isolated generation benchmark with persisted E1 comparison.

const Species = preload("res://scripts/creatures/creature_species.gd")
const Generator = preload("res://scripts/creatures/creature_generator.gd")
const AppearanceCache = preload("res://scripts/creatures/creature_appearance_cache.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var cache := AppearanceCache.new()
	var timings: Array[int] = []
	var batch_started := Time.get_ticks_usec()
	for index in range(48):
		var started := Time.get_ticks_usec()
		var anatomy := Generator.generate_creature(Species.SPECIES_ID, Generator.individual_seed(84521, index), 0.6, Generator.mixed_archetype(84521, index), true)
		cache.get_or_generate(anatomy)
		timings.append(Time.get_ticks_usec() - started)
	var total_usec := Time.get_ticks_usec() - batch_started
	var workshop = load("res://scenes/creatures/creature_workshop.tscn").instantiate()
	root.add_child(workshop)
	await process_frame
	var frame_times: Array[float] = []
	for _index in range(120):
		var frame_started := Time.get_ticks_usec()
		await process_frame
		frame_times.append(float(Time.get_ticks_usec() - frame_started) / 1000.0)
	var total_frame_ms := 0.0
	var worst_frame_ms := 0.0
	for value in frame_times:
		total_frame_ms += value
		worst_frame_ms = maxf(worst_frame_ms, value)
	var baseline := _read_e1_baseline()
	var result := {
		"display_server": DisplayServer.get_name(),
		"batch_count": 48,
		"total_generation_ms": float(total_usec) / 1000.0,
		"average_generation_ms": float(total_usec) / 48000.0,
		"worst_individual_generation_ms": float(timings.max()) / 1000.0,
		"approximate_image_cache_bytes": cache.approximate_memory_bytes(),
		"settled_average_frame_ms": total_frame_ms / frame_times.size(),
		"settled_worst_frame_ms": worst_frame_ms,
		"e1_baseline": baseline,
	}
	if baseline.has("total_generation_ms"):
		result["generation_regression_percent"] = (float(result.total_generation_ms) / float(baseline.total_generation_ms) - 1.0) * 100.0
	var file := FileAccess.open("res://.artifacts/phase_e1b_creature_benchmark.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("PHASE_E1B_BENCHMARK: %s" % JSON.stringify(result))
	quit(0)

func _read_e1_baseline() -> Dictionary:
	var path := "res://.artifacts/phase_e1_creature_benchmark.json"
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

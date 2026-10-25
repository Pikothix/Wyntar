extends SceneTree
## Separates pure pose cost from cached animated-presentation composition cost.

const Species = preload("res://scripts/creatures/creature_species.gd")
const Generator = preload("res://scripts/creatures/creature_generator.gd")
const Rig = preload("res://scripts/creatures/creature_rig.gd")
const PoseEvaluator = preload("res://scripts/creatures/creature_pose_evaluator.gd")
const RigVisualCache = preload("res://scripts/creatures/creature_rig_visual_cache.gd")
const RigRenderer = preload("res://scripts/creatures/creature_rig_renderer.gd")

func _initialize() -> void:
	_run()

func _run() -> void:
	var anatomy := Generator.generate_creature(Species.SPECIES_ID, 84521, 0.6, "elongated", true)
	var rig := Rig.build(anatomy)
	var visual_cache := RigVisualCache.new()
	var visual_started := Time.get_ticks_usec()
	var visual := visual_cache.get_or_generate(anatomy, rig)
	var visual_generation_usec := Time.get_ticks_usec() - visual_started
	var composer := RigRenderer.new()
	composer.configure(rig, visual)
	const POSE_SAMPLES := 20000
	var pose_started := Time.get_ticks_usec()
	var last_pose: Dictionary
	for index in range(POSE_SAMPLES):
		last_pose = PoseEvaluator.evaluate_pose(rig, "walk", float(index) / 60.0, {"speed": 1.0, "intensity": 1.0})
	var pose_total_usec := Time.get_ticks_usec() - pose_started
	const PRESENTATION_SAMPLES := 600
	var presentation_started := Time.get_ticks_usec()
	for index in range(PRESENTATION_SAMPLES):
		var pose := PoseEvaluator.evaluate_pose(rig, "walk", float(index) / 60.0)
		composer.compose(pose)
	var presentation_total_usec := Time.get_ticks_usec() - presentation_started
	var result := {
		"display_server": DisplayServer.get_name(),
		"pose_samples": POSE_SAMPLES,
		"pose_total_ms": float(pose_total_usec) / 1000.0,
		"pose_average_usec": float(pose_total_usec) / POSE_SAMPLES,
		"presentation_samples": PRESENTATION_SAMPLES,
		"presentation_total_ms": float(presentation_total_usec) / 1000.0,
		"presentation_average_ms": float(presentation_total_usec) / 1000.0 / PRESENTATION_SAMPLES,
		"part_art_generation_ms": float(visual_generation_usec) / 1000.0,
		"part_art_generation_count": visual_cache.generation_count,
		"output_image_reused": composer.output_instance_id() == composer.output_image().get_instance_id(),
		"e1b_baseline": _read_json("res://.artifacts/phase_e1b_creature_benchmark.json"),
	}
	var file := FileAccess.open("res://.artifacts/phase_e2a_creature_rig_benchmark.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("PHASE_E2A_BENCHMARK: %s" % JSON.stringify(result))
	quit(0)

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

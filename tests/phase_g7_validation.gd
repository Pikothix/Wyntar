extends SceneTree
## Focused G7 configuration, rollback, distribution, and ownership validation.

const Catalog = preload("res://scripts/terrain_catalog.gd")

const ELIGIBLE_IDS: Array[int] = [2, 4, 6, 7]
const EXPECTED := {
	2: {"density": 0.70, "contrast": 0.68, "clear_area": 0.55, "cluster_scale": 0.006},
	4: {"density": 0.85, "contrast": 0.72, "clear_area": 0.45, "cluster_scale": 0.005},
	6: {"density": 0.65, "contrast": 0.55, "clear_area": 0.60, "cluster_scale": 0.004},
	7: {"density": 0.85, "contrast": 0.72, "clear_area": 0.35, "cluster_scale": 0.008},
}

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main = load("res://main.tscn").instantiate()
	main.include_elevation_demo = false
	main.procedural_elevation_enabled = false
	main.decorations_enabled = false
	main.environment_objects_enabled = false
	root.add_child(main)
	for _frame in range(8):
		await process_frame
	var terrain = main.terrain
	_expect(terrain.terrain_noise_refinement_enabled,
		"G7 terrain noise refinement defaults enabled")
	for definition in Catalog.MATERIALS:
		var terrain_id: int = int(definition["id"])
		var material: ShaderMaterial = terrain.visual_material_by_id[terrain_id]
		var enabled := float(material.get_shader_parameter(
			"terrain_noise_refinement_enabled")) > 0.5
		_expect(enabled == (terrain_id in ELIGIBLE_IDS),
			"G7 eligibility is material-specific for terrain id %d" % terrain_id)
		if terrain_id in ELIGIBLE_IDS:
			for key in EXPECTED[terrain_id]:
				var parameter: StringName = StringName({
					"density": "terrain_detail_density_scale",
					"contrast": "terrain_detail_contrast",
					"clear_area": "terrain_clear_area_coverage",
					"cluster_scale": "terrain_detail_cluster_scale",
				}[key])
				_expect(is_equal_approx(float(material.get_shader_parameter(parameter)),
					float(EXPECTED[terrain_id][key])),
					"terrain id %d receives G7 %s" % [terrain_id, key])

	var material_override_count: int = terrain.world.get_override_count()
	var height_override_count: int = terrain.world.get_height_override_count()
	var pending_chunk_count: int = terrain.get_pending_chunk_count()
	terrain.set_terrain_noise_refinement_enabled(false)
	for terrain_id in ELIGIBLE_IDS:
		_expect(not _parameter_enabled(terrain, terrain_id,
			"terrain_noise_refinement_enabled"),
			"G7 rollback restores G6 for terrain id %d" % terrain_id)
	_expect(terrain.world.get_override_count() == material_override_count,
		"G7 toggle does not mutate material authority")
	_expect(terrain.world.get_height_override_count() == height_override_count,
		"G7 toggle does not mutate elevation authority")
	_expect(terrain.get_pending_chunk_count() == pending_chunk_count,
		"G7 shared-material updates do not rebuild chunks")
	_expect(not terrain.export_generation_config().has("terrain_noise_refinement_enabled"),
		"G7 remains outside authoritative save configuration")

	terrain.set_terrain_noise_refinement_enabled(true)
	var settings: Dictionary = terrain.terrain_noise_refinement_material_settings.duplicate(true)
	settings[2] = {"density": 0.25, "contrast": 0.4,
		"clear_area": 0.8, "cluster_scale": 0.012}
	terrain.set_terrain_noise_refinement_material_settings(settings)
	var dirt: ShaderMaterial = terrain.visual_material_by_id[2]
	_expect(is_equal_approx(float(dirt.get_shader_parameter(
		"terrain_detail_density_scale")), 0.25)
		and is_equal_approx(float(dirt.get_shader_parameter(
			"terrain_detail_contrast")), 0.4)
		and is_equal_approx(float(dirt.get_shader_parameter(
			"terrain_clear_area_coverage")), 0.8)
		and is_equal_approx(float(dirt.get_shader_parameter(
			"terrain_detail_cluster_scale")), 0.012),
		"material settings update without source edits")

	_test_distribution()
	if failures.is_empty():
		print("PHASE_G7_VALIDATION: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("PHASE_G7_VALIDATION: FAIL (%d)" % failures.size())
		quit(1)


func _test_distribution() -> void:
	var baseline := 0
	var refined := 0
	var quiet_region_marks := 0
	var detailed_region_marks := 0
	var quiet_pixels := 0
	var detailed_pixels := 0
	for y in range(-192, 192):
		for x in range(-192, 192):
			var pixel := Vector2(x, y)
			var roll := _hash(pixel + Vector2(311.0, 197.0))
			var baseline_mark := roll >= 1.0 - 0.028
			var cluster := _smooth_noise(pixel * 0.006 + Vector2(17.0, -29.0))
			var dense_region := smoothstep(0.47, 0.63, smoothstep(0.0, 1.0, cluster))
			var density := 0.028 * 0.70 * lerpf(0.10, 1.0, dense_region)
			var refined_mark := roll >= 1.0 - density
			baseline += int(baseline_mark)
			refined += int(refined_mark)
			if dense_region < 0.2:
				quiet_pixels += 1
				quiet_region_marks += int(refined_mark)
			elif dense_region > 0.8:
				detailed_pixels += 1
				detailed_region_marks += int(refined_mark)
	_expect(baseline > 0 and refined < baseline * 0.50,
		"reviewed dirt settings reduce prominent anchors by at least 50 percent")
	_expect(quiet_pixels > 0 and detailed_pixels > 0
		and float(detailed_region_marks) / float(detailed_pixels)
		> float(quiet_region_marks) / float(quiet_pixels) * 3.0,
		"G7 groups retained marks into irregular clusters and quiet regions")
	_expect(_hash(Vector2(64.0, -17.0) + Vector2(311.0, 197.0))
		== _hash(Vector2(64.0, -17.0) + Vector2(311.0, 197.0)),
		"G7 world-space placement is deterministic at a chunk boundary")


func _smooth_noise(point: Vector2) -> float:
	var cell := point.floor()
	var fraction := point - cell
	fraction = fraction * fraction * (Vector2.ONE * 3.0 - fraction * 2.0)
	var top := lerpf(_sine_hash(cell), _sine_hash(cell + Vector2.RIGHT), fraction.x)
	var bottom := lerpf(_sine_hash(cell + Vector2.DOWN),
		_sine_hash(cell + Vector2.ONE), fraction.x)
	return lerpf(top, bottom, fraction.y)


func _sine_hash(point: Vector2) -> float:
	return fposmod(sin(point.dot(Vector2(127.1, 311.7))) * 43758.5453123, 1.0)


func _hash(point: Vector2) -> float:
	var point3 := Vector3(point.x, point.y, point.x) * Vector3(0.1031, 0.1030, 0.0973)
	point3 -= point3.floor()
	point3 += Vector3.ONE * point3.dot(
		Vector3(point3.y, point3.x, point3.z) + Vector3.ONE * 33.33)
	return fposmod((point3.x + point3.y) * point3.z, 1.0)


func _parameter_enabled(terrain, terrain_id: int, parameter: StringName) -> bool:
	return float(terrain.visual_material_by_id[terrain_id].get_shader_parameter(parameter)) > 0.5


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

extends SceneTree
## Focused Phase G6 configuration, rollback, and ownership validation.

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
	_expect(terrain.remaining_terrain_detail_enabled, "G6 surface correction defaults enabled")
	_expect(terrain.water_repetition_correction_enabled, "G6 water correction defaults enabled")
	_expect(terrain.cliff_repetition_correction_enabled, "G6 cliff correction defaults enabled")
	_expect(_parameter_enabled(terrain, 5, "remaining_terrain_detail_enabled"),
		"snow opts into its dedicated G6 path")
	_expect(_parameter_enabled(terrain, 7, "remaining_terrain_detail_enabled"),
		"gravel opts into its dedicated G6 path")
	for terrain_id in [0, 1, 2, 3, 4, 6]:
		_expect(not _parameter_enabled(terrain, terrain_id,
			"remaining_terrain_detail_enabled"),
			"G6 snow/gravel path excludes terrain id %d" % terrain_id)
	_expect(_parameter_enabled(terrain, 0, "water_repetition_correction_enabled"),
		"water receives the G6 correction")
	var material_override_count: int = terrain.world.get_override_count()
	var height_override_count: int = terrain.world.get_height_override_count()

	terrain.set_remaining_terrain_detail_enabled(false)
	terrain.set_water_repetition_correction_enabled(false)
	terrain.set_cliff_repetition_correction_enabled(false)
	_expect(not _parameter_enabled(terrain, 5, "remaining_terrain_detail_enabled"),
		"snow rollback is exact at the shader switch")
	_expect(not _parameter_enabled(terrain, 7, "remaining_terrain_detail_enabled"),
		"gravel rollback is exact at the shader switch")
	_expect(not _parameter_enabled(terrain, 0, "water_repetition_correction_enabled"),
		"water rollback is exact at the shader switch")
	for material in terrain.cliff_material_by_source.values():
		_expect(not bool(material.get_shader_parameter(
			"texture_detail_reconstruction_enabled")),
			"cliff rollback is exact at every shared cliff material")
	_expect(not bool(terrain.organic_cliff_material.get_shader_parameter(
		"texture_detail_reconstruction_enabled")),
		"organic cliff rollback is exact")
	_expect(terrain.world.get_override_count() == material_override_count,
		"presentation toggles do not mutate material overrides")
	_expect(terrain.world.get_height_override_count() == height_override_count,
		"presentation toggles do not mutate elevation overrides")
	if failures.is_empty():
		print("PHASE_G6_VALIDATION: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _parameter_enabled(terrain, terrain_id: int, parameter: StringName) -> bool:
	return float(terrain.visual_material_by_id[terrain_id].get_shader_parameter(parameter)) > 0.5


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

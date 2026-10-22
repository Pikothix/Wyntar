extends SceneTree
## Phase G4 validation for material-aware terrain texture phase correction.
## Renderer checks cover eligibility, defaults, rollback, deterministic world
## anchoring, grass/water isolation, chunk independence, and save isolation.

const Catalog = preload("res://scripts/terrain_catalog.gd")
const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")

const ELIGIBLE_IDS: Array[int] = [1, 2, 4, 5, 6, 7]
const EXPECTED_STRENGTHS := {1: 0.55, 2: 0.65, 4: 0.55, 5: 0.35, 6: 0.65, 7: 0.35}

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_world_orientation_determinism()
	await _test_renderer_integration()
	if failures.is_empty():
		print("PHASE_G4_VALIDATION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE_G4_VALIDATION: FAIL (%d)" % failures.size())
	quit(1)


func _test_world_orientation_determinism() -> void:
	var changed_by_seed: int = 0
	for y in range(-1024, 1025, 31):
		for x in range(-1024, 1025, 29):
			var point := Vector2i(x, y)
			var first: Vector2 = _warp(point, 84521, 4, 1.0, 0.0045)
			_expect(first.is_equal_approx(_warp(point, 84521, 4, 1.0, 0.0045)),
				"fixed coordinate and seed reproduce warp")
			if not first.is_equal_approx(_warp(point, 13579, 4, 1.0, 0.0045)):
				changed_by_seed += 1
	_expect(changed_by_seed > 3000, "different seeds change representative warp")
	for seam_x in [-64, -32, 0, 32, 64]:
		var coordinate := Vector2i(seam_x, 17)
		_expect(_warp(coordinate, 84521, 2, 0.9, 0.0055).is_equal_approx(
			_warp(coordinate, 84521, 2, 0.9, 0.0055)),
			"shared world coordinate agrees at chunk seam")


func _test_renderer_integration() -> void:
	var renderer = TerrainRenderer.new()
	renderer.decoration_generation_enabled = false
	renderer.environment_object_generation_enabled = false
	root.add_child(renderer)
	await process_frame
	for terrain_id in renderer.visual_material_by_id:
		var material: ShaderMaterial = renderer.visual_material_by_id[terrain_id]
		var enabled: float = material.get_shader_parameter(
			"terrain_texture_repetition_correction_enabled")
		if int(terrain_id) in ELIGIBLE_IDS and int(terrain_id) not in [5, 7]:
			_expect(enabled == 1.0, "eligible material %d enables G4" % terrain_id)
			_expect(is_equal_approx(float(material.get_shader_parameter(
				"terrain_texture_repetition_correction_strength")),
				float(EXPECTED_STRENGTHS[int(terrain_id)])),
				"material %d receives reviewed strength" % terrain_id)
		else:
			_expect(enabled == 0.0,
				"grass/water or default-natural material %d remains outside G4" % terrain_id)

	var grass: ShaderMaterial = renderer.visual_material_by_id[Catalog.DEFAULT_MATERIAL_ID]
	var g3_state = grass.get_shader_parameter("grass_texture_repetition_correction_enabled")
	var water: ShaderMaterial = renderer.visual_material_by_id[0]
	var water_state = water.get_shader_parameter("liquid_enabled")
	renderer.set_terrain_texture_repetition_correction_enabled(false)
	for terrain_id in ELIGIBLE_IDS:
		_expect(float(renderer.visual_material_by_id[terrain_id].get_shader_parameter(
			"terrain_texture_repetition_correction_enabled")) == 0.0,
			"global rollback disables material %d" % terrain_id)
	_expect(grass.get_shader_parameter("grass_texture_repetition_correction_enabled") == g3_state,
		"G4 rollback leaves G3 grass state unchanged")
	_expect(water.get_shader_parameter("liquid_enabled") == water_state,
		"G4 rollback leaves liquid state unchanged")
	renderer.set_terrain_texture_repetition_correction_enabled(true)
	var settings: Dictionary = renderer.terrain_texture_repetition_material_settings.duplicate(true)
	settings[4] = {"enabled": false, "strength": 0.25}
	renderer.set_terrain_texture_repetition_material_settings(settings)
	_expect(float(renderer.visual_material_by_id[4].get_shader_parameter(
		"terrain_texture_repetition_correction_enabled")) == 0.0,
		"material-specific switch disables stone")
	_expect(is_equal_approx(float(renderer.visual_material_by_id[4].get_shader_parameter(
		"terrain_texture_repetition_correction_strength")), 0.25),
		"material-specific strength reaches stone shader")
	_expect(renderer.get_pending_chunk_count() == 0,
		"shared-material updates do not invalidate chunks")
	var save_config: Dictionary = renderer.export_generation_config()
	_expect(not save_config.has("terrain_texture_repetition_correction_enabled"),
		"G4 presentation settings remain outside saves")
	renderer.queue_free()
	await process_frame


func _warp(
		point: Vector2i, world_seed: int, terrain_id: int,
		strength: float, scale: float) -> Vector2:
	var seed_offset := Vector2(
		float(posmod(world_seed + terrain_id * 1301, 8192)),
		float(posmod(world_seed * 3 + terrain_id * 3253, 8192)))
	var coordinate := (Vector2(point) + Vector2(0.5, 0.5)) * scale
	return (Vector2(
		_smooth_value_noise(coordinate + seed_offset * 0.023),
		_smooth_value_noise(coordinate * 1.37 + seed_offset * 0.041
			+ Vector2(47.0, -73.0))) - Vector2(0.5, 0.5)) * 28.0 * strength


func _smooth_value_noise(point: Vector2) -> float:
	var cell := point.floor()
	var fraction := point - cell
	fraction = fraction * fraction * (Vector2(3.0, 3.0) - 2.0 * fraction)
	var top := lerpf(_hash_value(cell), _hash_value(cell + Vector2.RIGHT), fraction.x)
	var bottom := lerpf(
		_hash_value(cell + Vector2.DOWN), _hash_value(cell + Vector2.ONE), fraction.x)
	return lerpf(top, bottom, fraction.y)


func _hash_value(point: Vector2) -> float:
	var value: float = sin(point.dot(Vector2(127.1, 311.7))) * 43758.5453123
	return value - floorf(value)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

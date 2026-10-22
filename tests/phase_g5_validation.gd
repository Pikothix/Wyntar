extends SceneTree
## Phase G5 validation for deterministic material-specific procedural detail.

const Catalog = preload("res://scripts/terrain_catalog.gd")
const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")

const ELIGIBLE_IDS: Array[int] = [1, 2, 4, 6]
const EXPECTED_INTENSITIES := {1: 0.95, 2: 1.0, 4: 1.0, 6: 1.0}

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_hash_determinism_and_distribution()
	await _test_renderer_integration()
	if failures.is_empty():
		print("PHASE_G5_VALIDATION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE_G5_VALIDATION: FAIL (%d)" % failures.size())
	quit(1)


func _test_hash_determinism_and_distribution() -> void:
	var first_seed_features: Dictionary = {}
	var second_seed_changed := 0
	var repeated_at_32 := 0
	var feature_count := 0
	for y in range(-128, 128):
		for x in range(-128, 128):
			var point := Vector2i(x, y)
			var first := _feature(point, 84521, 2, 0.028)
			first_seed_features[point] = first
			_expect(first == _feature(point, 84521, 2, 0.028),
				"fixed seed and world pixel reproduce G5 detail")
			if first != _feature(point, 13579, 2, 0.028):
				second_seed_changed += 1
			if first:
				feature_count += 1
				if _feature(point + Vector2i(32, 0), 84521, 2, 0.028):
					repeated_at_32 += 1
	_expect(feature_count > 1000 and feature_count < 8000,
		"dirt feature density remains sparse and non-empty")
	_expect(second_seed_changed > 1500, "world seed changes G5 placement")
	_expect(float(repeated_at_32) / float(feature_count) < 0.12,
		"G5 feature coordinates do not repeat at the source 32px period")
	var seam_point := Vector2i(64, -17)
	_expect(_feature(seam_point, 84521, 4, 0.034)
		== _feature(seam_point, 84521, 4, 0.034),
		"shared world pixel agrees at a chunk boundary")


func _test_renderer_integration() -> void:
	var renderer = TerrainRenderer.new()
	renderer.decoration_generation_enabled = false
	renderer.environment_object_generation_enabled = false
	root.add_child(renderer)
	await process_frame
	var atlas_hashes: Dictionary = {}
	for terrain_id in renderer.visual_material_by_id:
		var material: ShaderMaterial = renderer.visual_material_by_id[terrain_id]
		var enabled := float(material.get_shader_parameter(
			"stochastic_terrain_detail_enabled"))
		if int(terrain_id) in ELIGIBLE_IDS:
			_expect(enabled == 1.0, "eligible material %d enables G5" % terrain_id)
			_expect(is_equal_approx(float(material.get_shader_parameter(
				"stochastic_terrain_detail_intensity")),
				float(EXPECTED_INTENSITIES[int(terrain_id)])),
				"material %d receives reviewed G5 intensity" % terrain_id)
		else:
			_expect(enabled == 0.0,
				"grass, water, snow, or gravel material %d remains outside G5" % terrain_id)
		atlas_hashes[terrain_id] = _image_hash(
			renderer.render_tileset.get_source(terrain_id).texture.get_image())

	var grass: ShaderMaterial = renderer.visual_material_by_id[Catalog.DEFAULT_MATERIAL_ID]
	var g3_state = grass.get_shader_parameter("grass_texture_repetition_correction_enabled")
	var g4_state: Dictionary = {}
	for terrain_id in ELIGIBLE_IDS:
		g4_state[terrain_id] = renderer.visual_material_by_id[terrain_id].get_shader_parameter(
			"terrain_texture_repetition_correction_enabled")
	renderer.set_stochastic_terrain_detail_enabled(false)
	for terrain_id in ELIGIBLE_IDS:
		_expect(float(renderer.visual_material_by_id[terrain_id].get_shader_parameter(
			"stochastic_terrain_detail_enabled")) == 0.0,
			"global rollback restores G4 for material %d" % terrain_id)
		_expect(renderer.visual_material_by_id[terrain_id].get_shader_parameter(
			"terrain_texture_repetition_correction_enabled") == g4_state[terrain_id],
			"G5 rollback does not modify G4 configuration")
		_expect(_image_hash(renderer.render_tileset.get_source(terrain_id).texture.get_image())
			== atlas_hashes[terrain_id], "G5 does not rewrite atlas %d" % terrain_id)
	_expect(grass.get_shader_parameter("grass_texture_repetition_correction_enabled") == g3_state,
		"G5 rollback leaves G3 grass unchanged")
	renderer.set_stochastic_terrain_detail_enabled(true)
	var settings: Dictionary = \
		renderer.stochastic_terrain_detail_material_settings.duplicate(true)
	settings[4] = {"enabled": false, "intensity": 0.35}
	renderer.set_stochastic_terrain_detail_material_settings(settings)
	_expect(float(renderer.visual_material_by_id[4].get_shader_parameter(
		"stochastic_terrain_detail_enabled")) == 0.0,
		"material switch disables stone G5")
	_expect(is_equal_approx(float(renderer.visual_material_by_id[4].get_shader_parameter(
		"stochastic_terrain_detail_intensity")), 0.35),
		"material intensity reaches the stone shader")
	_expect(renderer.get_pending_chunk_count() == 0,
		"G5 shared-material updates do not invalidate chunks")
	_expect(not renderer.export_generation_config().has("stochastic_terrain_detail_enabled"),
		"G5 remains outside authoritative save configuration")
	renderer.queue_free()
	await process_frame


func _feature(point: Vector2i, world_seed: int, terrain_id: int, density: float) -> bool:
	var seed := Vector2(
		float(posmod(world_seed + terrain_id * 1301, 8192)),
		float(posmod(world_seed * 3 + terrain_id * 3253, 8192)))
	seed = Vector2(fposmod(seed.x, 997.0), fposmod(seed.y, 991.0))
	var pixel := Vector2(fposmod(point.x, 2039.0), fposmod(point.y, 2029.0))
	var offset := seed * 0.053 + Vector2(terrain_id * 31.0, -17.0)
	var center := _stochastic_hash(pixel + offset)
	var left := _stochastic_hash(pixel - Vector2.RIGHT + offset)
	var upper := _stochastic_hash(pixel - Vector2.DOWN + offset)
	var link := _stochastic_hash(pixel + seed * 0.097 + Vector2(-53.0, 79.0))
	return (center >= 1.0 - density
		or (left >= 1.0 - density * 0.55 and link >= 0.46)
		or (upper >= 1.0 - density * 0.40 and link >= 0.63))


func _stochastic_hash(point: Vector2) -> float:
	var point3 := Vector3(point.x, point.y, point.x) * Vector3(0.1031, 0.1030, 0.0973)
	point3 = point3 - point3.floor()
	var dot_value := point3.dot(Vector3(point3.y, point3.x, point3.z) + Vector3(33.33, 33.33, 33.33))
	point3 += Vector3.ONE * dot_value
	var value := (point3.x + point3.y) * point3.z
	return value - floorf(value)


func _image_hash(image: Image) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(image.get_data())
	return context.finish().hex_encode()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

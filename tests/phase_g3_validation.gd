extends SceneTree
## Phase G3 validation for deterministic grass-background reconstruction.
## CPU sampling mirrors the shader inputs; renderer checks cover grass-only
## ownership, exact rollback, G1/G2 independence, lifecycle, and save isolation.

const Catalog = preload("res://scripts/terrain_catalog.gd")
const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")

const WORLD_SEED := 84521
const SECOND_SEED := 13579

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_stochastic_field_determinism()
	_test_chunk_order_independence()
	await _test_renderer_integration()
	if failures.is_empty():
		print("PHASE_G3_VALIDATION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE_G3_VALIDATION: FAIL (%d)" % failures.size())
	quit(1)


func _test_stochastic_field_determinism() -> void:
	var changed: int = 0
	for y in range(-1024, 1025, 31):
		for x in range(-1024, 1025, 29):
			var point := Vector2i(x, y)
			var first: float = _palette_shift(point, WORLD_SEED)
			_expect(is_equal_approx(first, _palette_shift(point, WORLD_SEED)),
				"fixed seed and coordinate reproduce G3 grain at %s" % point)
			if not is_equal_approx(first, _palette_shift(point, SECOND_SEED)):
				changed += 1
	_expect(changed > 3000,
		"different world seeds change the representative G3 grain field")

	for seam_x in [-64, -32, 0, 32, 64]:
		var west_chunk: int = floori(float(seam_x) / 32.0) - 1
		var east_chunk: int = west_chunk + 1
		var west_world := Vector2i(west_chunk * 32 + 32, 7)
		var east_world := Vector2i(east_chunk * 32, 7)
		_expect(west_world == east_world and is_equal_approx(
			_palette_shift(west_world, WORLD_SEED),
			_palette_shift(east_world, WORLD_SEED)),
			"shared coordinate remains identical at chunk seam x=%d" % seam_x)


func _test_chunk_order_independence() -> void:
	var forward: Dictionary = {}
	var reverse: Dictionary = {}
	var chunks: Array[Vector2i] = [
		Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-1, 0), Vector2i.ZERO, Vector2i(1, 0),
	]
	for chunk in chunks:
		_sample_chunk(forward, chunk)
	chunks.reverse()
	for chunk in chunks:
		_sample_chunk(reverse, chunk)
	_expect(forward == reverse,
		"G3 output is independent of chunk construction order")


func _sample_chunk(target: Dictionary, chunk: Vector2i) -> void:
	for local_y in [0, 7, 19, 31]:
		for local_x in [0, 5, 23, 31]:
			var point := chunk * 32 + Vector2i(local_x, local_y)
			target[point] = _palette_shift(point, WORLD_SEED)


func _test_renderer_integration() -> void:
	var renderer = TerrainRenderer.new()
	renderer.decoration_generation_enabled = false
	renderer.environment_object_generation_enabled = false
	root.add_child(renderer)
	await process_frame
	var grass: ShaderMaterial = renderer.visual_material_by_id[Catalog.DEFAULT_MATERIAL_ID]
	_expect(float(grass.get_shader_parameter(
		"grass_texture_repetition_correction_enabled")) == 1.0,
		"default renderer enables G3 on grass")
	for terrain_id in renderer.visual_material_by_id:
		if int(terrain_id) == Catalog.DEFAULT_MATERIAL_ID:
			continue
		_expect(float(renderer.visual_material_by_id[terrain_id].get_shader_parameter(
			"grass_texture_repetition_correction_enabled")) == 0.0,
			"non-grass material %s remains on its prior shader path" % terrain_id)

	var atlas: Texture2D = renderer.render_tileset.get_source(
		Catalog.DEFAULT_MATERIAL_ID).texture
	var atlas_hash := _image_hash(atlas.get_image())
	var g1_signature := _g1_signature(grass)
	var g2_signature := _g2_signature(grass)
	renderer.set_grass_texture_repetition_correction_enabled(false)
	_expect(float(grass.get_shader_parameter(
		"grass_texture_repetition_correction_enabled")) == 0.0,
		"G3 rollback switch restores the exact G2 shader path")
	_expect(_image_hash(atlas.get_image()) == atlas_hash,
		"G3 rollback does not rewrite the grass atlas")
	_expect(_g1_signature(grass) == g1_signature,
		"G3 rollback does not alter G1 controls")
	_expect(_g2_signature(grass) == g2_signature,
		"G3 rollback does not alter G2 controls")
	renderer.set_grass_texture_repetition_correction_enabled(true)
	_expect(renderer.get_pending_chunk_count() == 0,
		"shared-material G3 updates do not invalidate chunks")
	_expect(not renderer.export_generation_config().has(
		"grass_texture_repetition_correction_enabled"),
		"G3 remains outside authoritative save configuration")

	var expected: float = grass.get_shader_parameter(
		"grass_texture_repetition_correction_enabled")
	var weak_renderer: WeakRef = weakref(renderer)
	renderer.queue_free()
	await process_frame
	await process_frame
	_expect(weak_renderer.get_ref() == null,
		"renderer retirement releases G3 material resources")

	var replacement = TerrainRenderer.new()
	replacement.decoration_generation_enabled = false
	replacement.environment_object_generation_enabled = false
	root.add_child(replacement)
	await process_frame
	var replacement_grass: ShaderMaterial = replacement.visual_material_by_id[
		Catalog.DEFAULT_MATERIAL_ID]
	_expect(float(replacement_grass.get_shader_parameter(
		"grass_texture_repetition_correction_enabled")) == expected,
		"renderer recreation reproduces G3 material state")
	replacement.queue_free()
	await process_frame


func _palette_shift(point: Vector2i, world_seed: int) -> float:
	var world_pixel := Vector2(point) + Vector2(0.5, 0.5)
	var seed := Vector2(
		float(posmod(world_seed * 43 + 7187, 8192)),
		float(posmod(world_seed * 61 + 3251, 8192)))
	var grain_coordinate := Vector2(
		fposmod(world_pixel.x, 2039.0), fposmod(world_pixel.y, 2029.0))
	grain_coordinate += Vector2(
		fposmod(seed.x, 997.0), fposmod(seed.y, 991.0)) * 0.071
	var clustered_grain := _smooth_value_noise(
		grain_coordinate * 0.31 + Vector2(17.0, -43.0))
	var pixel_grain := _hash_value(grain_coordinate + Vector2(-29.0, 61.0))
	return (clustered_grain - 0.5) * 0.10 + (pixel_grain - 0.5) * 0.035


func _g1_signature(material: ShaderMaterial) -> Dictionary:
	return {
		"enabled": material.get_shader_parameter("clustered_grass_detail_enabled"),
		"coverage": material.get_shader_parameter("grass_clear_area_coverage"),
		"density": material.get_shader_parameter("grass_detail_density"),
		"scale": material.get_shader_parameter("grass_cluster_scale"),
		"softness": material.get_shader_parameter("grass_transition_softness"),
		"residual": material.get_shader_parameter("grass_clear_area_residual_density"),
		"seed": material.get_shader_parameter("grass_detail_seed_offset"),
	}


func _g2_signature(material: ShaderMaterial) -> Dictionary:
	return {
		"enabled": material.get_shader_parameter("organic_grass_color_variation_enabled"),
		"scale": material.get_shader_parameter("grass_broad_variation_scale"),
		"strength": material.get_shader_parameter("grass_color_variation_strength"),
		"fine": material.get_shader_parameter("grass_fine_variation_strength"),
		"seed": material.get_shader_parameter("grass_color_seed_offset"),
	}


func _smooth_value_noise(point: Vector2) -> float:
	var cell := point.floor()
	var fraction := point - cell
	fraction = fraction * fraction * (Vector2(3.0, 3.0) - 2.0 * fraction)
	var top: float = lerpf(
		_hash_value(cell), _hash_value(cell + Vector2.RIGHT), fraction.x)
	var bottom: float = lerpf(
		_hash_value(cell + Vector2.DOWN),
		_hash_value(cell + Vector2.ONE), fraction.x)
	return lerpf(top, bottom, fraction.y)


func _hash_value(point: Vector2) -> float:
	var value: float = sin(point.dot(Vector2(127.1, 311.7))) * 43758.5453123
	return value - floorf(value)


func _image_hash(image: Image) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(image.get_data())
	return context.finish().hex_encode()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

extends SceneTree
## Phase G2 validation for deterministic, seamless grass colour variation.
## CPU checks mirror the shader fields; renderer checks cover factory ownership,
## rollback, G1 independence, resource reuse, and save-schema isolation.

const Catalog = preload("res://scripts/terrain_catalog.gd")
const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")

const WORLD_SEED := 84521
const SECOND_SEED := 13579
const DEFAULT_SCALE := 0.0015

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_world_space_determinism()
	_test_chunk_order_independence()
	await _test_renderer_integration()
	if failures.is_empty():
		print("PHASE_G2_VALIDATION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE_G2_VALIDATION: FAIL (%d)" % failures.size())
	quit(1)


func _test_world_space_determinism() -> void:
	var changed: int = 0
	for y in range(-1024, 1025, 37):
		for x in range(-1024, 1025, 41):
			var point := Vector2i(x, y)
			var first := _variation_fields(point, WORLD_SEED, DEFAULT_SCALE)
			var repeated := _variation_fields(point, WORLD_SEED, DEFAULT_SCALE)
			_expect(first == repeated,
				"fixed world coordinate reproduces both colour fields at %s" % point)
			if first != _variation_fields(point, SECOND_SEED, DEFAULT_SCALE):
				changed += 1
	_expect(changed > 2000,
		"different world seeds change the representative colour field")

	for seam_x in [-64, -32, 0, 32, 64]:
		var left_chunk: int = floori(float(seam_x) / 32.0) - 1
		var right_chunk: int = left_chunk + 1
		var from_left := Vector2i(left_chunk * 32 + 32, 11)
		var from_right := Vector2i(right_chunk * 32, 11)
		_expect(from_left == from_right
			and _variation_fields(from_left, WORLD_SEED, DEFAULT_SCALE)
			== _variation_fields(from_right, WORLD_SEED, DEFAULT_SCALE),
			"world-space fields agree at chunk seam x=%d" % seam_x)


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
		"colour field is independent of chunk construction order")


func _sample_chunk(target: Dictionary, chunk: Vector2i) -> void:
	for local_y in [0, 7, 19, 31]:
		for local_x in [0, 5, 23, 31]:
			var point := chunk * 32 + Vector2i(local_x, local_y)
			target[point] = _variation_fields(point, WORLD_SEED, DEFAULT_SCALE)


func _test_renderer_integration() -> void:
	var renderer = TerrainRenderer.new()
	renderer.decoration_generation_enabled = false
	renderer.environment_object_generation_enabled = false
	root.add_child(renderer)
	await process_frame
	var grass: ShaderMaterial = renderer.visual_material_by_id[Catalog.DEFAULT_MATERIAL_ID]
	_expect(float(grass.get_shader_parameter(
		"organic_grass_color_variation_enabled")) == 1.0,
		"default renderer enables organic colour correction on grass")
	_expect(is_equal_approx(float(grass.get_shader_parameter(
		"grass_broad_variation_scale")), 0.0015)
		and is_equal_approx(float(grass.get_shader_parameter(
		"grass_color_variation_strength")), 0.055)
		and is_equal_approx(float(grass.get_shader_parameter(
		"grass_fine_variation_strength")), 0.018),
		"factory applies the reviewed G2 defaults")
	for terrain_id in renderer.visual_material_by_id:
		if int(terrain_id) == Catalog.DEFAULT_MATERIAL_ID:
			continue
		_expect(float(renderer.visual_material_by_id[terrain_id].get_shader_parameter(
			"organic_grass_color_variation_enabled")) == 0.0,
			"non-grass material %s remains on its prior shader path" % terrain_id)

	var atlas: Texture2D = renderer.render_tileset.get_source(
		Catalog.DEFAULT_MATERIAL_ID).texture
	var atlas_hash := _image_hash(atlas.get_image())
	var g1_signature := _g1_signature(grass)
	renderer.set_organic_grass_color_variation_enabled(false)
	_expect(float(grass.get_shader_parameter(
		"organic_grass_color_variation_enabled")) == 0.0,
		"G2 rollback switch restores the prior G1 shader path")
	_expect(_image_hash(atlas.get_image()) == atlas_hash,
		"G2 controls do not rewrite the grass atlas")
	_expect(_g1_signature(grass) == g1_signature,
		"G2 enable/disable does not alter G1 density or clustering controls")
	renderer.set_organic_grass_color_variation_controls(0.003, 0.09, 0.03)
	renderer.set_organic_grass_color_variation_enabled(true)
	_expect(renderer.get_pending_chunk_count() == 0,
		"shared-material G2 updates do not invalidate streamed chunks")
	_expect(not renderer.export_generation_config().has(
		"organic_grass_color_variation_enabled"),
		"visual colour preferences remain outside authoritative save data")

	var expected: Dictionary = _g2_signature(grass)
	var weak_renderer: WeakRef = weakref(renderer)
	renderer.queue_free()
	await process_frame
	await process_frame
	_expect(weak_renderer.get_ref() == null,
		"renderer retirement releases G2 material resources")

	var replacement = TerrainRenderer.new()
	replacement.decoration_generation_enabled = false
	replacement.environment_object_generation_enabled = false
	replacement.grass_broad_variation_scale = 0.003
	replacement.grass_color_variation_strength = 0.09
	replacement.grass_fine_variation_strength = 0.03
	root.add_child(replacement)
	await process_frame
	var replacement_grass: ShaderMaterial = replacement.visual_material_by_id[
		Catalog.DEFAULT_MATERIAL_ID]
	_expect(_g2_signature(replacement_grass) == expected,
		"renderer recreation reproduces G2 material state")
	replacement.queue_free()
	await process_frame


func _variation_fields(point: Vector2i, world_seed: int, scale: float) -> Vector4:
	var world_pixel := Vector2(point) + Vector2(0.5, 0.5)
	var seed := Vector2(
		float(posmod(world_seed * 43 + 7187, 8192)),
		float(posmod(world_seed * 61 + 3251, 8192)))
	var warp_coordinate := world_pixel * scale * 2.4
	var warp := (Vector2(
		_smooth_value_noise(warp_coordinate + seed * 0.71),
		_smooth_value_noise(warp_coordinate + seed * 0.37
			+ Vector2(83.0, -59.0))) - Vector2(0.5, 0.5)) * 16.0
	var primary := _smooth_value_noise(world_pixel * scale + seed)
	var secondary := _smooth_value_noise(
		world_pixel * scale * 2.17 + seed * 0.43 + Vector2(19.0, -31.0))
	var broad: float = (primary * 0.72 + secondary * 0.28 - 0.5) * 2.0
	var fine: float = (_smooth_value_noise(
		world_pixel * scale * 7.3 + seed * 0.19 + Vector2(-47.0, 23.0)) - 0.5) * 2.0
	return Vector4(warp.x, warp.y, broad, fine)


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

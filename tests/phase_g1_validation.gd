extends SceneTree
## Phase G1 validation for presentation-only, deterministic clustered grass.
## The CPU reference mirrors the shader field for distribution-level checks;
## renderer assertions verify factory/configuration integration.

const Catalog = preload("res://scripts/terrain_catalog.gd")
const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")

const WORLD_SEED := 84521
const DEFAULT_SEED_OFFSET := 48131
const DEFAULT_SCALE := 0.004

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_deterministic_distribution()
	_test_coverage_density_and_softness()
	await _test_renderer_integration_and_recreation()
	if failures.is_empty():
		print("PHASE_G1_VALIDATION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE_G1_VALIDATION: FAIL (%d)" % failures.size())
	quit(1)


func _test_deterministic_distribution() -> void:
	var points := [
		Vector2i(-4097, -2049), Vector2i(-32, 7), Vector2i(-1, 0),
		Vector2i.ZERO, Vector2i(31, 7), Vector2i(32, 7), Vector2i(4096, 2048),
	]
	for point in points:
		var first: float = _cluster_rank(point, WORLD_SEED, DEFAULT_SEED_OFFSET, DEFAULT_SCALE)
		var second: float = _cluster_rank(point, WORLD_SEED, DEFAULT_SEED_OFFSET, DEFAULT_SCALE)
		_expect(is_equal_approx(first, second),
			"identical seed and world coordinate reproduce the same field at %s" % point)

	var changed: int = 0
	for y in range(-256, 257, 16):
		for x in range(-256, 257, 16):
			var point := Vector2i(x, y)
			if not is_equal_approx(
					_cluster_rank(point, WORLD_SEED, DEFAULT_SEED_OFFSET, DEFAULT_SCALE),
					_cluster_rank(point, WORLD_SEED, DEFAULT_SEED_OFFSET + 1, DEFAULT_SCALE)):
				changed += 1
	_expect(changed > 900,
		"different seed offsets change the representative detail distribution")

	for seam_x in [-32, 0, 32]:
		var west_chunk: int = floori(float(seam_x) / 32.0) - 1
		var east_chunk: int = west_chunk + 1
		var west_world := Vector2i(west_chunk * 32 + 32, 7)
		var east_world := Vector2i(east_chunk * 32, 7)
		_expect(west_world == east_world and is_equal_approx(
			_cluster_rank(west_world, WORLD_SEED, DEFAULT_SEED_OFFSET, DEFAULT_SCALE),
			_cluster_rank(east_world, WORLD_SEED, DEFAULT_SEED_OFFSET, DEFAULT_SCALE)),
			"shared world coordinate remains continuous at chunk seam x=%d" % seam_x)


func _test_coverage_density_and_softness() -> void:
	var clear_samples: int = 0
	var sample_count: int = 0
	var retained_low: int = 0
	var retained_default: int = 0
	var retained_high: int = 0
	var narrow_transition: int = 0
	var wide_transition: int = 0
	for y in range(-2048, 2048, 16):
		for x in range(-2048, 2048, 16):
			var point := Vector2i(x, y)
			var rank: float = _cluster_rank(
				point, WORLD_SEED, DEFAULT_SEED_OFFSET, DEFAULT_SCALE)
			if rank < 0.70:
				clear_samples += 1
			var narrow: float = _dense_region(rank, 0.70, 0.04)
			var wide: float = _dense_region(rank, 0.70, 0.24)
			if narrow > 0.001 and narrow < 0.999:
				narrow_transition += 1
			if wide > 0.001 and wide < 0.999:
				wide_transition += 1
			var roll: float = _detail_roll(point, WORLD_SEED, DEFAULT_SEED_OFFSET)
			if roll < lerpf(0.04, 0.15, _dense_region(rank, 0.70, 0.12)):
				retained_low += 1
			if roll < lerpf(0.04, 0.35, _dense_region(rank, 0.70, 0.12)):
				retained_default += 1
			if roll < lerpf(0.04, 0.60, _dense_region(rank, 0.70, 0.12)):
				retained_high += 1
			sample_count += 1
	var measured_coverage: float = float(clear_samples) / float(sample_count)
	_expect(measured_coverage >= 0.66 and measured_coverage <= 0.76,
		"70%% clear-area target is approximate over a representative sample (%.3f)"
		% measured_coverage)
	_expect(retained_low < retained_default and retained_default < retained_high,
		"detail density monotonically increases retained mark candidates")
	_expect(wide_transition > narrow_transition * 2,
		"transition softness increases the width of intermediate-density regions")


func _test_renderer_integration_and_recreation() -> void:
	var first = await _create_renderer()
	var grass: ShaderMaterial = first.visual_material_by_id[Catalog.DEFAULT_MATERIAL_ID]
	_expect(float(grass.get_shader_parameter("clustered_grass_detail_enabled")) == 1.0,
		"default renderer enables clustered detail on grass")
	_expect(is_equal_approx(float(grass.get_shader_parameter("grass_clear_area_coverage")), 0.70)
		and is_equal_approx(float(grass.get_shader_parameter("grass_detail_density")), 0.35),
		"factory applies the 70%% clear / 35%% detail target")
	for terrain_id in first.visual_material_by_id:
		if int(terrain_id) == Catalog.DEFAULT_MATERIAL_ID:
			continue
		_expect(float(first.visual_material_by_id[terrain_id].get_shader_parameter(
			"clustered_grass_detail_enabled")) == 0.0,
			"non-grass material %s remains on its previous shader path" % terrain_id)

	var atlas_hash: String = _image_hash(
		first.render_tileset.get_source(Catalog.DEFAULT_MATERIAL_ID).texture.get_image())
	first.set_clustered_grass_detail_enabled(false)
	_expect(float(grass.get_shader_parameter("clustered_grass_detail_enabled")) == 0.0,
		"rollback switch disables the grass-only shader branch")
	_expect(_image_hash(first.render_tileset.get_source(
		Catalog.DEFAULT_MATERIAL_ID).texture.get_image()) == atlas_hash,
		"rollback does not rewrite or replace the legacy grass atlas")

	var original_seed: Vector2 = grass.get_shader_parameter("grass_detail_seed_offset")
	first.set_clustered_grass_detail_controls(0.65, 0.42, 0.006, 0.18, 0.07, 9001)
	first.set_clustered_grass_detail_enabled(true)
	_expect(grass.get_shader_parameter("grass_detail_seed_offset") != original_seed,
		"runtime seed offset changes the shared grass distribution")
	_expect(first.get_pending_chunk_count() == 0,
		"shared-material control updates do not invalidate streamed chunks")
	_expect(not first.export_generation_config().has("clustered_grass_detail_enabled"),
		"visual grass preferences remain outside authoritative save configuration")

	var signature: Dictionary = _grass_signature(first)
	var weak_first: WeakRef = weakref(first)
	first.queue_free()
	await process_frame
	await process_frame
	_expect(weak_first.get_ref() == null,
		"renderer retirement releases clustered grass resources")

	var replacement = await _create_renderer()
	replacement.set_clustered_grass_detail_controls(0.65, 0.42, 0.006, 0.18, 0.07, 9001)
	_expect(_grass_signature(replacement) == signature,
		"renderer recreation reproduces clustered grass material state")
	replacement.queue_free()
	await process_frame


func _create_renderer():
	var renderer = TerrainRenderer.new()
	renderer.decoration_generation_enabled = false
	renderer.environment_object_generation_enabled = false
	root.add_child(renderer)
	await process_frame
	return renderer


func _grass_signature(renderer) -> Dictionary:
	var material: ShaderMaterial = renderer.visual_material_by_id[Catalog.DEFAULT_MATERIAL_ID]
	return {
		"enabled": material.get_shader_parameter("clustered_grass_detail_enabled"),
		"coverage": material.get_shader_parameter("grass_clear_area_coverage"),
		"density": material.get_shader_parameter("grass_detail_density"),
		"scale": material.get_shader_parameter("grass_cluster_scale"),
		"softness": material.get_shader_parameter("grass_transition_softness"),
		"residual": material.get_shader_parameter("grass_clear_area_residual_density"),
		"seed": material.get_shader_parameter("grass_detail_seed_offset"),
	}


func _cluster_rank(
		point: Vector2i, world_seed: int, seed_offset: int, scale: float) -> float:
	var offset := Vector2(
		float(posmod(world_seed * 13 + seed_offset * 17 + 2719, 8192)),
		float(posmod(world_seed * 29 + seed_offset * 31 + 6421, 8192)))
	var coordinate := (Vector2(point) + Vector2(0.5, 0.5)) * scale + offset
	return smoothstep(0.0, 1.0, _smooth_value_noise(coordinate))


func _dense_region(rank: float, coverage: float, softness: float) -> float:
	var half_softness: float = maxf(softness * 0.5, 0.0001)
	return smoothstep(coverage - half_softness, coverage + half_softness, rank)


func _detail_roll(point: Vector2i, world_seed: int, seed_offset: int) -> float:
	var grass_pixel := Vector2(point) + Vector2(0.5, 0.5)
	var detail_cell := (grass_pixel / Vector2(4.0, 3.0)).floor()
	var offset := Vector2(
		float(posmod(world_seed * 13 + seed_offset * 17 + 2719, 8192)),
		float(posmod(world_seed * 29 + seed_offset * 31 + 6421, 8192)))
	var wrapped_cell := Vector2(
		fposmod(detail_cell.x, 2039.0), fposmod(detail_cell.y, 2029.0))
	var wrapped_offset := Vector2(
		fposmod(offset.x, 997.0), fposmod(offset.y, 991.0))
	return _hash_value(wrapped_cell + wrapped_offset * 0.019 + Vector2(37.0, -53.0))


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

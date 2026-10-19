extends SceneTree
## Phase 3A validates deterministic structural tree variation, bounded atlas
## reuse, reversible presentation, placement restrictions and streaming cleanup.

const ProcTrees = preload("res://scripts/procgen/proc_trees.gd")
const SpriteFactory = preload("res://scripts/procgen/environment_object_sprite_factory.gd")
const EnvironmentObjectCatalog = preload("res://scripts/environment_object_catalog.gd")
const EnvironmentObjectPlacement = preload("res://scripts/environment_object_placement.gd")
const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_tree_families()
	_test_alignment_and_shadow()
	_test_placement_restrictions()
	await _test_cache_toggle_and_streaming()
	if failures.is_empty():
		print("PHASE3A_VALIDATION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE3A_VALIDATION: FAIL (%d)" % failures.size())
	quit(1)


func _test_tree_families() -> void:
	for archetype in ["deciduous", "conifer"]:
		var silhouettes: Dictionary = {}
		var same_size_signatures: Dictionary = {}
		var same_size_structural_difference: bool = false
		for variant in range(12):
			var seed: int = 31001 + variant * 7919
			var first: Dictionary = ProcTrees.generate_tree(
				seed, 32, archetype, "GRASS", "large", "mature")
			var second: Dictionary = ProcTrees.generate_tree(
				seed, 32, archetype, "GRASS", "large", "mature")
			var first_image: Image = first.canvas.to_image()
			var second_image: Image = second.canvas.to_image()
			_expect(first_image.get_data() == second_image.get_data(),
				"%s seed %d must reproduce identical pixels" % [archetype, seed])
			var signature: int = _silhouette_hash(first_image)
			silhouettes[signature] = true
			var size: Vector2i = first_image.get_size()
			if same_size_signatures.has(size) and int(same_size_signatures[size]) != signature:
				same_size_structural_difference = true
			same_size_signatures[size] = signature
			_expect(_opaque_color_count(first_image) >= 5,
				"%s variant %d must retain a coordinated multi-step palette" % [archetype, variant])
		_expect(silhouettes.size() >= 10,
			"%s family must provide at least ten distinct silhouettes across twelve seeds" % archetype)
		_expect(same_size_structural_difference,
			"%s variation must change structure, not only canvas scale or colour" % archetype)


func _test_alignment_and_shadow() -> void:
	for definition_index in [0, 2]:
		var definition: Dictionary = EnvironmentObjectCatalog.DEFINITIONS[definition_index]
		var atlas := Image.create(96, 96, false, Image.FORMAT_RGBA8)
		atlas.fill(Color.TRANSPARENT)
		SpriteFactory.draw_variant(atlas, 0, definition, 0)
		var root: Vector2i = definition.root_anchor
		var root_pixel_found: bool = false
		var shadow_pixel_found: bool = false
		for x in range(96):
			var pixel: Color = atlas.get_pixel(x, root.y)
			if pixel.a > 0.0:
				root_pixel_found = true
			if pixel.a > 0.0 and pixel.a < 0.4:
				shadow_pixel_found = true
		_expect(root_pixel_found, "tree %d must anchor on its configured root row" % definition_index)
		_expect(shadow_pixel_found, "tree %d must include a restrained ground shadow" % definition_index)


func _test_placement_restrictions() -> void:
	var context := {
		"definitions": EnvironmentObjectCatalog.DEFINITIONS,
		"definitions_by_id": EnvironmentObjectCatalog.build_by_id(),
		"indices_by_material": EnvironmentObjectCatalog.build_indices_by_material(),
		"max_density_by_material": EnvironmentObjectCatalog.build_max_density_by_material(),
		"liquid_by_id": {0: true, 3: false, 5: false},
		"seed": 106438, "density": 2.0,
	}
	for y in range(-16, 17):
		for x in range(-16, 17):
			var pos := Vector2i(x, y)
			var water_choice: Vector2i = EnvironmentObjectPlacement.choose(
				pos, context, _water, _height_one, _height_one)
			_expect(water_choice.x < 0, "water cell %s must reject tree placement" % pos)
	var conifer: Dictionary = EnvironmentObjectCatalog.DEFINITIONS[2]
	_expect(not EnvironmentObjectPlacement._footprint_is_valid(
		Vector2i.ZERO, 0, conifer, _grass, _height_zero, _height_zero, context.liquid_by_id),
		"conifers must reject terrain below their minimum elevation")
	_expect(not EnvironmentObjectPlacement._footprint_is_valid(
		Vector2i.ZERO, 1, conifer, _water, _height_one, _height_one, context.liquid_by_id),
		"tree footprints must reject liquid terrain")


func _test_cache_toggle_and_streaming() -> void:
	var terrain = TerrainRenderer.new()
	root.add_child(terrain)
	await process_frame
	var metrics: Dictionary = terrain.get_environment_atlas_metrics()
	_expect(int(metrics.procedural_tree_variant_count) == 14,
		"bounded atlas must contain the fourteen catalog tree appearances")
	_expect(int(metrics.runtime_generation_count) == 0,
		"runtime streaming must not rasterise procedural sprites")
	var procedural_id: int = int(metrics.procedural_texture_instance_id)
	var legacy_id: int = int(metrics.legacy_texture_instance_id)
	_expect(procedural_id != legacy_id, "A/B rollback textures must be distinct cached resources")
	var authority_before: int = hash(terrain.export_authoritative_snapshot())
	terrain.set_procedural_vegetation_enabled(false)
	_expect(int(terrain.get_environment_atlas_metrics().texture_instance_id) == legacy_id,
		"rollback selects the legacy tree atlas")
	terrain.set_procedural_vegetation_enabled(true)
	_expect(int(terrain.get_environment_atlas_metrics().texture_instance_id) == procedural_id,
		"procedural mode reuses its original cached atlas")
	_expect(hash(terrain.export_authoritative_snapshot()) == authority_before,
		"visual tree toggles must not mutate terrain or resource authority")

	terrain.update_visible_world_rect(Rect2(Vector2(-640, -360), Vector2(1280, 720)))
	await _wait_until_idle(terrain)
	terrain.update_visible_world_rect(Rect2(Vector2(180000, 180000), Vector2(1280, 720)))
	_expect(terrain.get_pending_chunk_retirement_count() > 0,
		"tree-bearing chunk transitions must use Phase 1G bounded retirement")
	await _wait_until_idle(terrain)
	await _wait_for_retirements(terrain)
	var after: Dictionary = terrain.get_environment_atlas_metrics()
	_expect(int(after.procedural_texture_instance_id) == procedural_id
		and int(after.legacy_texture_instance_id) == legacy_id,
		"streaming must preserve both bounded atlas resources")
	_expect(terrain.environment_object_renderer.get_owned_chunk_count() == terrain.loaded_chunks.size(),
		"environment batch ownership must match loaded chunk ownership")
	terrain.queue_free()


func _silhouette_hash(image: Image) -> int:
	var alpha := PackedByteArray()
	alpha.resize(image.get_width() * image.get_height())
	var index: int = 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			alpha[index] = image.get_pixel(x, y).a8
			index += 1
	return hash(alpha)


func _opaque_color_count(image: Image) -> int:
	var colors: Dictionary = {}
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a > 0.5:
				colors[pixel.to_rgba32()] = true
	return colors.size()


func _wait_until_idle(terrain, max_frames: int = 2000) -> void:
	for _frame in range(max_frames):
		await process_frame
		if terrain.get_pending_chunk_count() == 0:
			return
	assert(false, "Phase 3A streaming did not become idle")


func _wait_for_retirements(terrain, max_frames: int = 2000) -> void:
	for _frame in range(max_frames):
		if terrain.get_pending_chunk_retirement_count() == 0:
			return
		await process_frame
	assert(false, "Phase 3A retirement queue did not drain")


func _water(_pos: Vector2i) -> int:
	return 0


func _grass(_pos: Vector2i) -> int:
	return 3


func _height_zero(_pos: Vector2i) -> int:
	return 0


func _height_one(_pos: Vector2i) -> int:
	return 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

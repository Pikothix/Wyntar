extends SceneTree
## Phase 8A validation for deterministic Isolony sprite generation, bounded
## atlas precomputation, unchanged placement inputs, and four elevation batches.

const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")
const TerrainCatalog = preload("res://scripts/terrain_catalog.gd")
const EnvironmentObjectCatalog = preload("res://scripts/environment_object_catalog.gd")
const EnvironmentObjectPlacement = preload("res://scripts/environment_object_placement.gd")
const SpriteFactory = preload("res://scripts/procgen/environment_object_sprite_factory.gd")
const ProcTrees = preload("res://scripts/procgen/proc_trees.gd")
const ProcBoulders = preload("res://scripts/procgen/proc_boulders.gd")
const ProcBushes = preload("res://scripts/procgen/proc_bushes.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_generators()
	_test_factory_alignment_and_metadata()
	_test_placement_inputs_unchanged()
	await _test_renderer_cache_and_batches()
	if failures.is_empty():
		print("PHASE8A_VALIDATION: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("PHASE8A_VALIDATION: FAIL (%d)" % failures.size())
		quit(1)


func _test_generators() -> void:
	var generators: Array = [
		["tree", ProcTrees.generate_tree.bind(7123, 30, "deciduous", "GRASS", "medium", "mature")],
		["boulder", ProcBoulders.generate_boulder.bind(7123, 22, "blocky", "STONE", "medium")],
		["bush", ProcBushes.generate_bush.bind(7123, 26, "wide", "GRASS")],
	]
	for entry in generators:
		var first: Dictionary = entry[1].call()
		var second: Dictionary = entry[1].call()
		var first_image: Image = first["canvas"].to_image()
		var second_image: Image = second["canvas"].to_image()
		_expect(first_image.get_data() == second_image.get_data(),
			"%s generator must be deterministic" % entry[0])
		var opaque_pixels: int = 0
		var transparent_pixels: int = 0
		for y in range(first_image.get_height()):
			for x in range(first_image.get_width()):
				if first_image.get_pixel(x, y).a > 0.0:
					opaque_pixels += 1
				else:
					transparent_pixels += 1
		_expect(opaque_pixels > 0 and transparent_pixels > 0,
			"%s generator must produce a transparent sprite silhouette" % entry[0])
	var alternate: Dictionary = ProcTrees.generate_tree(7124, 30, "deciduous", "GRASS", "medium", "mature")
	var baseline: Dictionary = ProcTrees.generate_tree(7123, 30, "deciduous", "GRASS", "medium", "mature")
	_expect(alternate["canvas"].data != baseline["canvas"].data,
		"different presentation seeds must produce distinct tree variants")


func _test_factory_alignment_and_metadata() -> void:
	var atlas := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	var definition: Dictionary = EnvironmentObjectCatalog.DEFINITIONS[0]
	var result: Dictionary = SpriteFactory.draw_variant(atlas, 0, definition, 0)
	var root: Vector2i = definition["root_anchor"]
	var root_row_has_pixel: bool = false
	for x in range(96):
		if atlas.get_pixel(x, root.y).a > 0.0:
			root_row_has_pixel = true
			break
	_expect(root_row_has_pixel, "procedural sprite must bottom-align to its terrain root")
	_expect(result.has("seed") and result.has("atlas_size"),
		"factory must expose deterministic precompute metadata")
	for item in EnvironmentObjectCatalog.DEFINITIONS:
		if SpriteFactory.is_supported(item):
			_expect(item.has("resource_category") and item.has("future_yield"),
				"procedural resource definition %d has future simulation metadata" % item["id"])


func _test_placement_inputs_unchanged() -> void:
	var stripped_definitions: Array = []
	for definition in EnvironmentObjectCatalog.DEFINITIONS:
		var stripped: Dictionary = definition.duplicate(true)
		for key in stripped.keys():
			if String(key).begins_with("procedural_") or key in [
					"resource_category", "future_yield", "harvestable", "collectable",
					"supports_depletion", "supports_regrowth", "resource_id_strategy"]:
				stripped.erase(key)
		stripped_definitions.append(stripped)
	var liquid_by_id: Dictionary = {}
	for material in TerrainCatalog.MATERIALS:
		liquid_by_id[int(material["id"])] = bool(material.get("liquid", false))
	var current_context := _placement_context(EnvironmentObjectCatalog.DEFINITIONS, liquid_by_id)
	var stripped_context := _placement_context(stripped_definitions, liquid_by_id)
	for y in range(-40, 41):
		for x in range(-40, 41):
			var pos := Vector2i(x, y)
			if not EnvironmentObjectPlacement.is_candidate_anchor(pos, int(current_context["seed"])):
				continue
			var current: Vector2i = EnvironmentObjectPlacement.choose(
				pos, current_context, _grass, _height_one, _height_one)
			var stripped: Vector2i = EnvironmentObjectPlacement.choose(
				pos, stripped_context, _grass, _height_one, _height_one)
			_expect(current == stripped, "visual metadata changed placement at %s" % pos)


func _placement_context(definitions: Array, liquid_by_id: Dictionary) -> Dictionary:
	var by_id: Dictionary = {}
	var indices_by_material: Dictionary = {}
	var density_by_material: Dictionary = {}
	for index in range(definitions.size()):
		var definition: Dictionary = definitions[index]
		by_id[int(definition["id"])] = definition
		for material_id in definition["materials"]:
			var id: int = int(material_id)
			if not indices_by_material.has(id):
				indices_by_material[id] = []
			indices_by_material[id].append(index)
			density_by_material[id] = float(density_by_material.get(id, 0.0)) + float(definition["density"])
	return {
		"definitions": definitions, "definitions_by_id": by_id,
		"indices_by_material": indices_by_material,
		"max_density_by_material": density_by_material,
		"liquid_by_id": liquid_by_id, "seed": 175944, "density": 1.0,
	}


func _test_renderer_cache_and_batches() -> void:
	var terrain = TerrainRenderer.new()
	root.add_child(terrain)
	await process_frame
	var metrics: Dictionary = terrain.get_environment_atlas_metrics()
	var expected_variants: int = 0
	var expected_procedural: int = 0
	for definition in EnvironmentObjectCatalog.DEFINITIONS:
		var count: int = maxi(1, int(definition.get("variants", 1)))
		expected_variants += count
		if SpriteFactory.is_supported(definition):
			expected_procedural += count
		if String(definition.get("resource_category", "")) == "food":
			expected_variants += count
			expected_procedural += count
	_expect(int(metrics["variant_count"]) == expected_variants,
		"shared atlas contains exactly the bounded catalog variant count")
	_expect(int(metrics["procedural_variant_count"]) == expected_procedural,
		"all configured tree, boulder, and berry-bush variants are precomputed")
	_expect(metrics["dimensions"] == Vector2i(expected_variants * 96, 96),
		"shared atlas dimensions are bounded by catalog variants")
	_expect(terrain.environment_object_renderer.get_child_count() == 4,
		"renderer retains four elevation-aware global batches")
	var texture_id: int = int(metrics["texture_instance_id"])
	terrain.update_visible_world_rect(Rect2(Vector2(-640, -360), Vector2(1280, 720)))
	await _wait_until_idle(terrain)
	terrain.update_visible_world_rect(Rect2(Vector2(180000, 180000), Vector2(1280, 720)))
	await _wait_until_idle(terrain)
	var after: Dictionary = terrain.get_environment_atlas_metrics()
	_expect(int(after["texture_instance_id"]) == texture_id,
		"camera streaming reuses the startup atlas texture")
	_expect(int(after["variant_count"]) == expected_variants,
		"camera streaming does not grow the procedural cache")
	terrain.queue_free()


func _wait_until_idle(terrain, max_frames: int = 1200) -> void:
	for _frame in range(max_frames):
		await process_frame
		if terrain.get_pending_chunk_count() == 0:
			return
	failures.append("streaming did not become idle")


func _grass(_pos: Vector2i) -> int:
	return 3


func _height_one(_pos: Vector2i) -> int:
	return 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

extends SceneTree
## Phase C4B structural regression coverage for extracted renderer factories.
## This validates stable resource properties; it does not certify appearance.

const Catalog = preload("res://scripts/terrain_catalog.gd")
const DecorationCatalog = preload("res://scripts/decoration_catalog.gd")
const EnvironmentObjectCatalog = preload("res://scripts/environment_object_catalog.gd")
const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var first = await _create_renderer()
	var first_signature: Dictionary = _resource_signature(first)
	_test_output_structure(first)
	_test_atlas_layout(first)
	_test_material_parameters(first)
	_test_resource_identity(first)
	var first_weak: WeakRef = weakref(first)
	first.queue_free()
	await process_frame
	await process_frame
	_expect(first_weak.get_ref() == null, "retired renderer releases its owned resource graph")

	var replacement = await _create_renderer()
	var replacement_signature: Dictionary = _resource_signature(replacement)
	_expect(replacement_signature == first_signature,
		"renderer replacement recreates deterministic equivalent factory outputs")
	_test_resource_identity(replacement)
	replacement.queue_free()
	await process_frame

	if failures.is_empty():
		print("PHASE_C4B_RENDERER_FACTORY_VALIDATION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE_C4B_RENDERER_FACTORY_VALIDATION: FAIL (%d)" % failures.size())
	quit(1)


func _create_renderer():
	var renderer = TerrainRenderer.new()
	renderer.decoration_generation_enabled = false
	renderer.environment_object_generation_enabled = false
	root.add_child(renderer)
	await process_frame
	return renderer


func _test_output_structure(renderer) -> void:
	_expect(renderer.render_tileset != null, "terrain factory returns a TileSet")
	_expect(renderer.cliff_tileset != null, "cliff factory returns a legacy wall TileSet")
	_expect(renderer.cliff_edge_tileset != null, "cliff factory returns an edge TileSet")
	_expect(renderer.decoration_tileset != null, "detail factory returns a decoration TileSet")
	_expect(renderer.visual_material_by_id.size() == Catalog.MATERIALS.size(),
		"terrain material count matches the catalog")
	_expect(renderer.cliff_material_by_source.size() == 4
		and renderer.cliff_shadow_material_by_source.size() == 4,
		"legacy cliff material dictionaries retain four sources")
	_expect(renderer.organic_cliff_material != null,
		"organic cliff material remains a single shared resource")
	_expect(renderer.environment_object_atlas_by_id.size()
		== EnvironmentObjectCatalog.DEFINITIONS.size(),
		"environment atlas covers every definition")


func _test_atlas_layout(renderer) -> void:
	_expect(renderer.render_tileset.tile_size == Vector2i(32, 32),
		"terrain TileSet keeps 32x32 geometry")
	_expect(renderer.render_tileset.get_source_count() == Catalog.MATERIALS.size(),
		"terrain TileSet keeps one source per material")
	for definition in Catalog.MATERIALS:
		var source_id: int = int(definition["id"])
		var source: TileSetAtlasSource = renderer.render_tileset.get_source(source_id)
		_expect(source.texture.get_size() == Vector2(128, 128),
			"terrain masked atlas retains its 4x4 layout for source %d" % source_id)
		_expect(source.get_tiles_count() == 16,
			"terrain source %d retains sixteen mask tiles" % source_id)
	_expect(renderer.cliff_tileset.tile_size == Vector2i(32, 16),
		"legacy cliff wall geometry is unchanged")
	_expect(renderer.cliff_edge_tileset.tile_size == Vector2i(32, 32),
		"legacy cliff edge geometry is unchanged")
	for source_id in range(4):
		var wall: TileSetAtlasSource = renderer.cliff_tileset.get_source(source_id)
		var edge: TileSetAtlasSource = renderer.cliff_edge_tileset.get_source(source_id)
		_expect(wall.texture.get_size() == Vector2(1024, 32)
			and wall.get_tiles_count() == 64,
			"cliff source %d retains 32 variants and shadow row" % source_id)
		_expect(edge.texture.get_size() == Vector2(512, 288)
			and edge.get_tiles_count() == 135,
			"cliff edge source %d retains 9x15 populated variants" % source_id)
	var expected_decorations: int = 0
	for definition in DecorationCatalog.DEFINITIONS:
		expected_decorations += maxi(1, int(definition.get("variants", 1)))
	var decoration_source: TileSetAtlasSource = renderer.decoration_tileset.get_source(0)
	_expect(decoration_source.get_tiles_count() == expected_decorations,
		"decoration atlas ordering and variant count remain catalog-driven")
	_expect(renderer.environment_atlas_dimensions.y == 96
		and renderer.environment_atlas_dimensions.x
		== renderer.environment_atlas_variant_count * 96,
		"environment atlas remains a single ordered 96px row")


func _test_material_parameters(renderer) -> void:
	var water: ShaderMaterial = renderer.visual_material_by_id[0]
	_expect(water.shader.resource_path == "res://shaders/terrain_variation.gdshader",
		"terrain materials retain the variation shader")
	var expected_water_variation: float = clampf(
		renderer.texture_variation_strength
		* float(Catalog.MATERIALS[0].get("variation_strength", 1.0)), 0.0, 1.0)
	_expect(is_equal_approx(float(water.get_shader_parameter("variation_strength")),
		expected_water_variation),
		"water variation strength retains its configured value")
	_expect(float(water.get_shader_parameter("organic_edge_strength"))
		== renderer.organic_edge_strength,
		"organic boundary parameter remains unchanged")
	_expect(float(water.get_shader_parameter("water_ripple_strength"))
		== renderer.water_ripple_strength,
		"water enhancement parameters are initialized by the factory")
	for source_id in range(4):
		var cliff: ShaderMaterial = renderer.cliff_material_by_source[source_id]
		var shadow: ShaderMaterial = renderer.cliff_shadow_material_by_source[source_id]
		_expect(cliff.shader.resource_path == "res://shaders/cliff_procedural.gdshader",
			"cliff source %d retains the procedural shader" % source_id)
		_expect(not bool(cliff.get_shader_parameter("contact_shadow"))
			and bool(shadow.get_shader_parameter("contact_shadow")),
			"cliff source %d retains wall/shadow parameter separation" % source_id)


func _test_resource_identity(renderer) -> void:
	for definition in Catalog.MATERIALS:
		var source_id: int = int(definition["id"])
		var source: TileSetAtlasSource = renderer.render_tileset.get_source(source_id)
		var expected: ShaderMaterial = renderer.visual_material_by_id[source_id]
		for mask in range(16):
			var pos := Vector2i(mask & 3, mask >> 2)
			_expect(source.get_tile_data(pos, 0).material == expected,
				"terrain source %d reuses one shared material" % source_id)
	for source_id in range(4):
		var edge: TileSetAtlasSource = renderer.cliff_edge_tileset.get_source(source_id)
		_expect(edge.get_tile_data(Vector2i(1, 0), 0).material
			== renderer.cliff_material_by_source[source_id],
			"cliff edge source %d reuses the wall material" % source_id)


func _resource_signature(renderer) -> Dictionary:
	var terrain_hashes: Array[String] = []
	for definition in Catalog.MATERIALS:
		var source: TileSetAtlasSource = renderer.render_tileset.get_source(int(definition["id"]))
		terrain_hashes.append(_image_hash(source.texture.get_image()))
	var cliff_hashes: Array[String] = []
	var edge_hashes: Array[String] = []
	for source_id in range(4):
		var wall: TileSetAtlasSource = renderer.cliff_tileset.get_source(source_id)
		var edge: TileSetAtlasSource = renderer.cliff_edge_tileset.get_source(source_id)
		cliff_hashes.append(_image_hash(wall.texture.get_image()))
		edge_hashes.append(_image_hash(edge.texture.get_image()))
	return {
		"terrain": terrain_hashes,
		"cliffs": cliff_hashes,
		"edges": edge_hashes,
		"decorations": _image_hash(renderer.decoration_tileset.get_source(0).texture.get_image()),
		"environment_procedural": _image_hash(renderer.environment_object_procedural_atlas_texture.get_image()),
		"environment_legacy": _image_hash(renderer.environment_object_legacy_tree_atlas_texture.get_image()),
		"environment_layout": renderer.environment_object_atlas_by_id,
		"environment_unripe_layout": renderer.environment_object_unripe_atlas_by_id,
	}


func _image_hash(image: Image) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(image.get_data())
	return context.finish().hex_encode()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

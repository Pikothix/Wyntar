extends SceneTree
## Phase 1A ownership and rollback validation for the presentation-only cliff
## material. Authoritative terrain data and all atlas alpha remain unchanged.

const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var renderer = TerrainRenderer.new()
	root.add_child(renderer)
	await process_frame
	var authoritative_before: String = JSON.stringify(renderer.export_authoritative_snapshot())
	var child_count_before: int = renderer.get_child_count()
	var atlas_hashes: Dictionary = {}

	_expect(renderer.cliff_material_by_source.size() == 4,
		"all four existing cliff source classes receive one shared material")
	_expect(renderer.cliff_shadow_material_by_source.size() == 4,
		"all four cliff source classes receive one shared foot material")
	for source_id in range(4):
		var material: ShaderMaterial = renderer.cliff_material_by_source.get(source_id)
		var shadow_material: ShaderMaterial = (
			renderer.cliff_shadow_material_by_source.get(source_id))
		_expect(material != null, "cliff source %d has a procedural material" % source_id)
		_expect(shadow_material != null,
			"cliff source %d has a procedural foot material" % source_id)
		if material == null or shadow_material == null:
			continue
		_expect(material.shader != null and material.shader.resource_path.ends_with(
			"cliff_procedural.gdshader"),
			"cliff source %d uses the Phase 1A shader" % source_id)
		_expect(bool(material.get_shader_parameter("stone_style")) == (source_id % 2 == 1),
			"cliff source %d preserves stone classification" % source_id)
		_expect(bool(material.get_shader_parameter("shoreline")) == (source_id >= 2),
			"cliff source %d preserves shoreline classification" % source_id)
		_expect(not bool(material.get_shader_parameter("contact_shadow")),
			"face source %d remains a physical cliff material" % source_id)
		_expect(bool(shadow_material.get_shader_parameter("contact_shadow")),
			"shadow source %d receives world-stable foot darkening" % source_id)

		var face_source: TileSetAtlasSource = renderer.cliff_tileset.get_source(source_id)
		atlas_hashes[source_id] = hash(face_source.texture.get_image().get_data())
		for variant in range(32):
			_expect(face_source.get_tile_data(Vector2i(variant, 0), 0).material == material,
				"face variant %d/%d shares its source material" % [source_id, variant])
			_expect(face_source.get_tile_data(
				Vector2i(variant, 1), 0).material == shadow_material,
				"shadow variant %d/%d shares its source foot material" % [source_id, variant])

		var edge_source: TileSetAtlasSource = renderer.cliff_edge_tileset.get_source(source_id)
		for variant in range(9):
			for edge_mask in range(1, 16):
				_expect(edge_source.get_tile_data(
					Vector2i(edge_mask, variant), 0).material == material,
					"edge variant %d/%d/%d shares the continuous material" % [
						source_id, variant, edge_mask])

	renderer.set_procedural_cliff_materials_enabled(false)
	_expect(not renderer.is_procedural_cliff_materials_enabled(),
		"rollback flag reports the legacy appearance")
	for material in renderer.cliff_material_by_source.values():
		_expect(not bool(material.get_shader_parameter("procedural_enabled")),
			"rollback flag reaches every shared cliff material")
	for material in renderer.cliff_shadow_material_by_source.values():
		_expect(not bool(material.get_shader_parameter("procedural_enabled")),
			"rollback flag reaches every shared cliff-foot material")
	renderer.set_procedural_cliff_materials_enabled(true)
	_expect(renderer.is_procedural_cliff_materials_enabled(),
		"procedural appearance can be restored without rebuilding chunks")

	for source_id in range(4):
		var source: TileSetAtlasSource = renderer.cliff_tileset.get_source(source_id)
		_expect(hash(source.texture.get_image().get_data()) == atlas_hashes[source_id],
			"toggle preserves cliff atlas pixels and alpha for source %d" % source_id)
	_expect(renderer.get_child_count() == child_count_before,
		"material toggle adds no terrain nodes or per-cell objects")
	_expect(JSON.stringify(renderer.export_authoritative_snapshot()) == authoritative_before,
		"material toggle does not mutate authoritative terrain or resources")

	if failures.is_empty():
		print("PHASE1A_VALIDATION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE1A_VALIDATION: FAIL (%d)" % failures.size())
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

extends RefCounted
## Creates shared decoration and environmental-object atlases. Procedural
## sprite generation remains deterministic; the caller supplies the existing
## legacy pixel painters so fallback appearance is preserved exactly.

const EnvironmentObjectSpriteFactory = preload("res://scripts/procgen/environment_object_sprite_factory.gd")

const ENVIRONMENT_CELL_SIZE := Vector2i(96, 96)


static func create_decoration_tileset(definitions: Array, tile_size: Vector2i, legacy_draw: Callable) -> Dictionary:
	var atlas_by_id: Dictionary = {}
	var total_variants: int = 0
	for definition in definitions:
		atlas_by_id[int(definition["id"])] = total_variants
		total_variants += maxi(1, int(definition.get("variants", 1)))
	var atlas_image := Image.create(tile_size.x * total_variants, tile_size.y, false, Image.FORMAT_RGBA8)
	atlas_image.fill(Color.TRANSPARENT)
	for definition in definitions:
		var atlas_start: int = int(atlas_by_id[int(definition["id"])])
		for variant in range(maxi(1, int(definition.get("variants", 1)))):
			legacy_draw.call(atlas_image, atlas_start + variant, definition, variant)
	var source := TileSetAtlasSource.new()
	source.texture_region_size = tile_size
	source.texture = ImageTexture.create_from_image(atlas_image)
	source.use_texture_padding = true
	for atlas_x in range(total_variants):
		source.create_tile(Vector2i(atlas_x, 0))
	var tileset := TileSet.new()
	tileset.tile_size = tile_size
	var assigned_id: int = tileset.add_source(source, 0)
	assert(assigned_id == 0, "Could not add shared decoration atlas")
	return {"tileset": tileset, "atlas_by_id": atlas_by_id}


static func create_environment_atlases(definitions: Array, procedural_vegetation_enabled: bool, legacy_draw: Callable) -> Dictionary:
	var generation_start_usec: int = Time.get_ticks_usec()
	var atlas_by_id: Dictionary = {}
	var unripe_atlas_by_id: Dictionary = {}
	var total_variants: int = 0
	var procedural_variants: int = 0
	var procedural_tree_variants: int = 0
	for definition in definitions:
		atlas_by_id[int(definition["id"])] = total_variants
		var definition_variants: int = maxi(1, int(definition.get("variants", 1)))
		total_variants += definition_variants
		if EnvironmentObjectSpriteFactory.is_supported(definition):
			procedural_variants += definition_variants
			if String(definition.get("category", "")) == "trees":
				procedural_tree_variants += definition_variants
	for definition in definitions:
		if String(definition.get("resource_category", "")) != "food":
			continue
		unripe_atlas_by_id[int(definition["id"])] = total_variants
		var unripe_variants: int = maxi(1, int(definition.get("variants", 1)))
		total_variants += unripe_variants
		procedural_variants += unripe_variants
	var atlas_image := Image.create(ENVIRONMENT_CELL_SIZE.x * total_variants, ENVIRONMENT_CELL_SIZE.y, false, Image.FORMAT_RGBA8)
	atlas_image.fill(Color.TRANSPARENT)
	for definition in definitions:
		var atlas_start: int = int(atlas_by_id[int(definition["id"])])
		for variant in range(maxi(1, int(definition.get("variants", 1)))):
			if EnvironmentObjectSpriteFactory.is_supported(definition):
				EnvironmentObjectSpriteFactory.draw_variant(atlas_image, atlas_start + variant, definition, variant)
			else:
				legacy_draw.call(atlas_image, atlas_start + variant, definition, variant)
	for definition in definitions:
		var object_id: int = int(definition["id"])
		if not unripe_atlas_by_id.has(object_id):
			continue
		var atlas_start: int = int(unripe_atlas_by_id[object_id])
		for variant in range(maxi(1, int(definition.get("variants", 1)))):
			EnvironmentObjectSpriteFactory.draw_variant(atlas_image, atlas_start + variant, definition, variant, false)
	var procedural_texture := ImageTexture.create_from_image(atlas_image)
	var legacy_generation_start_usec: int = Time.get_ticks_usec()
	var legacy_tree_image: Image = atlas_image.duplicate()
	for definition in definitions:
		if String(definition.get("category", "")) != "trees":
			continue
		var atlas_start: int = int(atlas_by_id[int(definition["id"])])
		for variant in range(maxi(1, int(definition.get("variants", 1)))):
			legacy_tree_image.fill_rect(Rect2i(Vector2i((atlas_start + variant) * ENVIRONMENT_CELL_SIZE.x, 0), ENVIRONMENT_CELL_SIZE), Color.TRANSPARENT)
			legacy_draw.call(legacy_tree_image, atlas_start + variant, definition, variant)
	var legacy_texture := ImageTexture.create_from_image(legacy_tree_image)
	var legacy_usec: int = Time.get_ticks_usec() - legacy_generation_start_usec
	return {
		"active_texture": procedural_texture if procedural_vegetation_enabled else legacy_texture,
		"procedural_texture": procedural_texture,
		"legacy_tree_texture": legacy_texture,
		"atlas_by_id": atlas_by_id,
		"unripe_atlas_by_id": unripe_atlas_by_id,
		"variant_count": total_variants,
		"procedural_variant_count": procedural_variants,
		"procedural_tree_variant_count": procedural_tree_variants,
		"dimensions": atlas_image.get_size(),
		"legacy_generation_usec": legacy_usec,
		"generation_usec": Time.get_ticks_usec() - generation_start_usec,
	}

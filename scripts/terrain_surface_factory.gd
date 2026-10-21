extends RefCounted
## Creates the shared terrain TileSet, masked atlases, and shader materials.
## The caller owns every returned resource and all subsequent runtime updates.

const VariationShader = preload("res://shaders/terrain_variation.gdshader")


static func create(material_definitions: Array, tile_size: Vector2i, config: Dictionary) -> Dictionary:
	var tileset := TileSet.new()
	tileset.tile_size = tile_size
	var priorities: Dictionary = {}
	var names: Dictionary = {}
	var liquids: Dictionary = {}
	var materials: Dictionary = {}
	var variant_counts: Dictionary = {}
	for definition in material_definitions:
		var terrain_id: int = int(definition["id"])
		assert(not priorities.has(terrain_id), "Duplicate terrain ID")
		priorities[terrain_id] = int(definition["priority"])
		names[terrain_id] = String(definition["name"])
		liquids[terrain_id] = bool(definition.get("liquid", false))
		var texture: Texture2D = load(definition["texture_path"]) as Texture2D
		assert(texture != null, "Missing material PNG: " + str(definition["texture_path"]))
		var material_result: Dictionary = _create_visual_material(definition, tile_size, config)
		var visual_material: ShaderMaterial = material_result["material"]
		materials[terrain_id] = visual_material
		variant_counts[terrain_id] = int(material_result["variant_count"])
		var source := TileSetAtlasSource.new()
		source.texture_region_size = tile_size
		source.texture = _generate_masked_atlas(texture, tile_size)
		source.use_texture_padding = true
		for mask in range(16):
			var atlas_position: Vector2i = atlas_pos(mask)
			source.create_tile(atlas_position)
			source.get_tile_data(atlas_position, 0).material = visual_material
		var assigned_id: int = tileset.add_source(source, terrain_id)
		assert(assigned_id == terrain_id, "Could not add terrain atlas")
	return {
		"tileset": tileset,
		"priority_by_id": priorities,
		"name_by_id": names,
		"liquid_by_id": liquids,
		"visual_material_by_id": materials,
		"variant_count_by_id": variant_counts,
	}


static func apply_water_enhancement_parameters(material: ShaderMaterial, config: Dictionary) -> void:
	material.set_shader_parameter("experimental_water_enhancement_enabled",
		1.0 if bool(config["enabled"]) else 0.0)
	material.set_shader_parameter("water_ripple_strength", float(config["ripple_strength"]))
	material.set_shader_parameter("water_secondary_ripple_scale", float(config["secondary_scale"]))
	material.set_shader_parameter("water_ripple_drift_speed", float(config["drift_speed"]))
	material.set_shader_parameter("water_glint_density", float(config["glint_density"]))
	material.set_shader_parameter("water_glint_brightness", float(config["glint_brightness"]))


static func apply_clustered_grass_detail_parameters(
		material: ShaderMaterial, config: Dictionary, eligible: bool) -> void:
	## The renderer owns these presentation controls. The factory translates
	## them into one shared grass-material state; non-grass materials remain on
	## the legacy shader path even when the global experiment is enabled.
	material.set_shader_parameter("clustered_grass_detail_enabled",
		1.0 if eligible and bool(config["enabled"]) else 0.0)
	material.set_shader_parameter("grass_clear_area_coverage",
		clampf(float(config["clear_area_coverage"]), 0.0, 1.0))
	material.set_shader_parameter("grass_detail_density",
		clampf(float(config["detail_density"]), 0.0, 1.0))
	material.set_shader_parameter("grass_cluster_scale",
		clampf(float(config["cluster_scale"]), 0.0005, 0.02))
	material.set_shader_parameter("grass_transition_softness",
		clampf(float(config["transition_softness"]), 0.0, 0.4))
	material.set_shader_parameter("grass_clear_area_residual_density",
		clampf(float(config["clear_area_residual_density"]), 0.0, 1.0))
	var world_seed: int = int(config["world_seed"])
	var seed_offset: int = int(config["seed_offset"])
	material.set_shader_parameter("grass_detail_seed_offset", Vector2(
		float(posmod(world_seed * 13 + seed_offset * 17 + 2719, 8192)),
		float(posmod(world_seed * 29 + seed_offset * 31 + 6421, 8192))))


static func atlas_pos(mask: int) -> Vector2i:
	return Vector2i(mask & 3, mask >> 2)


static func coverage(mask: int, x: int, y: int) -> float:
	return smoothstep(0.43, 0.57, mask_field(mask, x, y))


static func mask_field(mask: int, x: int, y: int) -> float:
	var u: float = (float(x) + 0.5) / 32.0
	var v: float = (float(y) + 0.5) / 32.0
	var tl: float = 1.0 if (mask & 8) != 0 else 0.0
	var tr: float = 1.0 if (mask & 4) != 0 else 0.0
	var bl: float = 1.0 if (mask & 2) != 0 else 0.0
	var br: float = 1.0 if (mask & 1) != 0 else 0.0
	var top_value: float = lerpf(tl, tr, u)
	var bottom_value: float = lerpf(bl, br, u)
	var field: float = lerpf(top_value, bottom_value, v)
	return field + 0.07 * sin(u * TAU * 3.0) * sin(v * TAU * 2.0)


static func _create_visual_material(definition: Dictionary, tile_size: Vector2i, config: Dictionary) -> Dictionary:
	var fallback_path: String = String(definition["texture_path"])
	var variant_definitions: Array = definition.get("variants", [])
	if variant_definitions.is_empty():
		variant_definitions = [{"texture_path": fallback_path}]
	var variant_textures: Array[Texture2D] = []
	for variant_definition in variant_definitions:
		variant_textures.append(_generate_visual_variant(variant_definition, fallback_path, tile_size))
	var variant_count: int = variant_textures.size()
	while variant_textures.size() < 4:
		variant_textures.append(variant_textures[variant_textures.size() - 1])
	var material := ShaderMaterial.new()
	material.shader = VariationShader
	material.set_shader_parameter("base_texture", variant_textures[0])
	material.set_shader_parameter("variant_texture_1", variant_textures[mini(1, variant_textures.size() - 1)])
	material.set_shader_parameter("variant_texture_2", variant_textures[mini(2, variant_textures.size() - 1)])
	material.set_shader_parameter("variant_texture_3", variant_textures[mini(3, variant_textures.size() - 1)])
	material.set_shader_parameter("variation_enabled", 1.0 if bool(config["texture_variation_enabled"]) else 0.0)
	var strength: float = float(definition.get("variation_strength", 1.0))
	var frequency_scale: float = float(definition.get("variation_frequency_scale", 1.0))
	material.set_shader_parameter("variation_strength", clampf(float(config["texture_variation_strength"]) * strength, 0.0, 1.0))
	material.set_shader_parameter("variation_frequency", maxf(0.00001, float(config["texture_variation_frequency"]) * frequency_scale))
	var terrain_id: int = int(definition["id"])
	var world_seed: int = int(config["world_seed"])
	material.set_shader_parameter("seed_offset", Vector2(
		float(posmod(world_seed + terrain_id * 1301, 8192)),
		float(posmod(world_seed * 3 + terrain_id * 3253, 8192))))
	material.set_shader_parameter("organic_boundaries_enabled", 1.0 if bool(config["organic_boundaries_enabled"]) else 0.0)
	material.set_shader_parameter("organic_edge_strength", clampf(float(config["organic_edge_strength"]), 0.0, 0.18))
	material.set_shader_parameter("organic_edge_frequency", maxf(0.00001, float(config["organic_edge_frequency"])))
	material.set_shader_parameter("organic_seed_offset", Vector2(
		float(posmod(world_seed * 7 + 1871, 8192)),
		float(posmod(world_seed * 11 + 3917, 8192))))
	var grass_config: Dictionary = config["grass_detail"].duplicate()
	grass_config["world_seed"] = world_seed
	var grass_eligible: bool = bool(definition.get("clustered_grass_detail", false))
	apply_clustered_grass_detail_parameters(material, grass_config, grass_eligible)
	material.set_shader_parameter("grass_detail_luma_threshold", clampf(
		float(definition.get("grass_detail_luma_threshold", 0.5)), 0.0, 1.0))
	material.set_shader_parameter("grass_clear_color", Color(String(
		definition.get("grass_clear_color", "77ae58"))))
	var is_liquid: bool = bool(definition.get("liquid", false))
	material.set_shader_parameter("liquid_enabled", 1.0 if is_liquid else 0.0)
	if is_liquid:
		material.set_shader_parameter("liquid_surface_tint", Color(String(definition.get("liquid_surface_tint", "66aeca"))))
		material.set_shader_parameter("liquid_highlight_tint", Color(String(definition.get("liquid_highlight_tint", "b8edf0"))))
		material.set_shader_parameter("liquid_calmness", clampf(float(definition.get("visual_calmness", 0.8)), 0.0, 1.0))
		material.set_shader_parameter("liquid_pattern_frequency", maxf(0.00001, float(definition.get("liquid_pattern_frequency", 0.01))))
		material.set_shader_parameter("liquid_shimmer_strength", clampf(float(definition.get("liquid_shimmer_strength", 0.06)), 0.0, 0.2))
		material.set_shader_parameter("liquid_motion_enabled", 1.0 if bool(definition.get("liquid_motion_enabled", false)) else 0.0)
		material.set_shader_parameter("liquid_motion_speed", float(definition.get("liquid_motion_speed", 0.0)))
		material.set_shader_parameter("shoreline_width", clampf(float(definition.get("shoreline_width", 0.16)), 0.02, 0.3))
		material.set_shader_parameter("liquid_depth_effect_strength", clampf(float(definition.get("depth_effect_strength", 0.0)), 0.0, 0.35))
		material.set_shader_parameter("liquid_emissive_strength", clampf(float(definition.get("emissive_strength", 0.0)), 0.0, 1.0) if bool(definition.get("emissive", false)) else 0.0)
		apply_water_enhancement_parameters(material, config["water"])
	return {"material": material, "variant_count": variant_count}


static func _generate_visual_variant(definition: Dictionary, fallback_path: String, tile_size: Vector2i) -> ImageTexture:
	var texture_path: String = String(definition.get("texture_path", fallback_path))
	var source_texture: Texture2D = load(texture_path) as Texture2D
	assert(source_texture != null, "Missing variant PNG: " + texture_path)
	var image: Image = source_texture.get_image()
	if image.get_size() != tile_size:
		image.resize(tile_size.x, tile_size.y, Image.INTERPOLATE_NEAREST)
	image.convert(Image.FORMAT_RGBA8)
	var tint := Color(String(definition.get("tint", "ffffff")))
	var brightness: float = float(definition.get("brightness", 1.0))
	var contrast: float = float(definition.get("contrast", 1.0))
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pigment: Color = image.get_pixel(x, y)
			pigment.r = clampf(((pigment.r - 0.5) * contrast + 0.5) * tint.r * brightness, 0.0, 1.0)
			pigment.g = clampf(((pigment.g - 0.5) * contrast + 0.5) * tint.g * brightness, 0.0, 1.0)
			pigment.b = clampf(((pigment.b - 0.5) * contrast + 0.5) * tint.b * brightness, 0.0, 1.0)
			image.set_pixel(x, y, pigment)
	return ImageTexture.create_from_image(image)


static func _generate_masked_atlas(original: Texture2D, tile_size: Vector2i) -> ImageTexture:
	var base: Image = original.get_image()
	if base.get_size() != tile_size:
		base.resize(tile_size.x, tile_size.y, Image.INTERPOLATE_NEAREST)
	base.convert(Image.FORMAT_RGBA8)
	var atlas := Image.create(tile_size.x * 4, tile_size.y * 4, false, Image.FORMAT_RGBA8)
	for mask in range(16):
		var origin: Vector2i = atlas_pos(mask) * tile_size
		for y in range(tile_size.y):
			for x in range(tile_size.x):
				var pigment: Color = base.get_pixel(x, y)
				var field: float = mask_field(mask, x, y)
				pigment.r = clampf(field, 0.0, 1.0)
				pigment.a *= smoothstep(0.43, 0.57, field)
				atlas.set_pixel(origin.x + x, origin.y + y, pigment)
	return ImageTexture.create_from_image(atlas)

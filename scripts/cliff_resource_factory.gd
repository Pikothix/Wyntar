extends RefCounted
## Creates shared legacy and organic cliff resources. The renderer retains
## ownership of the returned resources and controls their runtime parameters.

const TerrainChunkBuildJob = preload("res://scripts/terrain_chunk_build_job.gd")
const CliffProceduralShader = preload("res://shaders/cliff_procedural.gdshader")

const DEFINITIONS := [
	{"id": 0, "texture_path": "res://art/dirt.png", "stone": false, "shoreline": false},
	{"id": 1, "texture_path": "res://art/stone.png", "stone": true, "shoreline": false},
	{"id": 2, "texture_path": "res://art/dirt.png", "stone": false, "shoreline": true},
	{"id": 3, "texture_path": "res://art/stone.png", "stone": true, "shoreline": true},
]


static func create(tile_size: Vector2i, height_step: int, world_seed: int, procedural_enabled: bool) -> Dictionary:
	var cliff_tileset := TileSet.new()
	cliff_tileset.tile_size = Vector2i(tile_size.x, height_step)
	var materials: Dictionary = {}
	var shadow_materials: Dictionary = {}
	for definition in DEFINITIONS:
		var source_id: int = int(definition["id"])
		var texture: Texture2D = load(definition["texture_path"]) as Texture2D
		assert(texture != null, "Missing cliff source texture")
		var material := _create_material(texture, bool(definition["stone"]), bool(definition["shoreline"]), source_id, world_seed, procedural_enabled)
		var shadow_material := _create_material(texture, bool(definition["stone"]), bool(definition["shoreline"]), source_id, world_seed, procedural_enabled, true)
		materials[source_id] = material
		shadow_materials[source_id] = shadow_material
		var source := TileSetAtlasSource.new()
		source.texture_region_size = Vector2i(tile_size.x, height_step)
		source.texture = _generate_cliff_atlas(texture, bool(definition["stone"]), bool(definition["shoreline"]), tile_size, height_step)
		source.use_texture_padding = true
		for variant in range(32):
			source.create_tile(Vector2i(variant, 0))
			source.get_tile_data(Vector2i(variant, 0), 0).material = material
			source.create_tile(Vector2i(variant, 1))
			source.get_tile_data(Vector2i(variant, 1), 0).material = shadow_material
		var assigned_id: int = cliff_tileset.add_source(source, source_id)
		assert(assigned_id == source_id, "Could not add cliff atlas")
	var organic_material: ShaderMaterial = _create_organic_material(
		world_seed, procedural_enabled)
	var edge_tileset := TileSet.new()
	edge_tileset.tile_size = tile_size
	for definition in DEFINITIONS:
		var source_id: int = int(definition["id"])
		var texture: Texture2D = load(definition["texture_path"]) as Texture2D
		assert(texture != null, "Missing cliff edge source texture")
		var source := TileSetAtlasSource.new()
		source.texture_region_size = tile_size
		source.texture = _generate_cliff_edge_atlas(texture, bool(definition["stone"]), bool(definition["shoreline"]), tile_size)
		source.use_texture_padding = true
		for variant in range(9):
			for edge_mask in range(1, 16):
				var atlas_position := Vector2i(edge_mask, variant)
				source.create_tile(atlas_position)
				source.get_tile_data(atlas_position, 0).material = materials[source_id]
		var assigned_id: int = edge_tileset.add_source(source, source_id)
		assert(assigned_id == source_id, "Could not add cliff edge atlas")
	return {
		"cliff_tileset": cliff_tileset,
		"edge_tileset": edge_tileset,
		"materials": materials,
		"shadow_materials": shadow_materials,
		"organic_material": organic_material,
	}


static func _create_organic_material(world_seed: int, procedural_enabled: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CliffProceduralShader
	material.set_shader_parameter("source_texture", load("res://art/dirt.png"))
	material.set_shader_parameter("dirt_texture", load("res://art/dirt.png"))
	material.set_shader_parameter("stone_texture", load("res://art/stone.png"))
	material.set_shader_parameter("procedural_enabled", procedural_enabled)
	material.set_shader_parameter("combined_geometry", true)
	material.set_shader_parameter("seed_offset", Vector2(
		float(posmod(world_seed * 7 + 1871, 8192)),
		float(posmod(world_seed * 11 + 3917, 8192))))
	return material


static func _create_material(texture: Texture2D, stone: bool, shoreline: bool, source_id: int, world_seed: int, procedural_enabled: bool, contact_shadow: bool = false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CliffProceduralShader
	material.set_shader_parameter("source_texture", texture)
	material.set_shader_parameter("procedural_enabled", procedural_enabled)
	material.set_shader_parameter("stone_style", stone)
	material.set_shader_parameter("shoreline", shoreline)
	material.set_shader_parameter("contact_shadow", contact_shadow)
	material.set_shader_parameter("geometry_mesh", false)
	material.set_shader_parameter("seed_offset", Vector2(
		float(posmod(world_seed * 7 + source_id * 1871, 8192)),
		float(posmod(world_seed * 11 + source_id * 3917, 8192))))
	return material


static func _generate_cliff_atlas(original: Texture2D, stone: bool, shoreline: bool, tile_size: Vector2i, height_step: int) -> ImageTexture:
	var base: Image = original.get_image()
	if base.get_size() != tile_size:
		base.resize(tile_size.x, tile_size.y, Image.INTERPOLATE_NEAREST)
	base.convert(Image.FORMAT_RGBA8)
	var atlas := Image.create(tile_size.x * 32, height_step * 2, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	for variant in range(32):
		var cap_mask: int = variant & 3
		var top_step: bool = (variant & 4) != 0
		var style: int = variant >> 3
		for y in range(height_step):
			for x in range(tile_size.x):
				var boundary: int = _boundary_offset(style, x, tile_size.x)
				var inset: int = _side_inset(style, y)
				if ((cap_mask & 1) != 0 and x < inset) or ((cap_mask & 2) != 0 and x >= tile_size.x - inset) or (top_step and y < boundary):
					continue
				var sample_y: int = posmod(y * 2 + floori(float(x + style * 3) / 8.0) * 3 + style * 5, tile_size.y)
				var pigment: Color = base.get_pixel(x, sample_y)
				var shade: float = (0.72 if stone else 0.70) - y * 0.006 + float(style - 1) * 0.012
				if top_step and y <= boundary + 1:
					shade += 0.18 - maxi(0, y - boundary) * 0.07
				if y in [5 + (style & 1), 10 + ((style >> 1) & 1)]:
					shade -= 0.045
				if y >= height_step - 3:
					var contact: int = _boundary_offset(style, x, tile_size.x)
					if y >= height_step - 1 - contact:
						shade -= 0.10 + float(y - (height_step - 1 - contact)) * 0.035
				if shoreline and y >= height_step - 2:
					shade += 0.10
					pigment = pigment.lerp(Color("9ab9b7"), 0.18)
				var crack_hash: int = posmod(x * 11 + y * 23 + style * 37 + (19 if stone else 5), 97)
				if crack_hash <= 1 and y > 2 and y < height_step - 2:
					shade -= 0.14
				if (cap_mask & 1) != 0 and x < 5:
					shade -= 0.16 - float(x) * 0.025
				if (cap_mask & 2) != 0 and x >= tile_size.x - 5:
					shade -= 0.16 - float(tile_size.x - 1 - x) * 0.025
				pigment.r = clampf(pigment.r * shade, 0.0, 1.0)
				pigment.g = clampf(pigment.g * shade, 0.0, 1.0)
				pigment.b = clampf(pigment.b * shade, 0.0, 1.0)
				pigment.a = 0.58 if (((cap_mask & 1) != 0 and x == inset) or ((cap_mask & 2) != 0 and x == tile_size.x - 1 - inset)) else 1.0
				atlas.set_pixel(variant * tile_size.x + x, y, pigment)
		for shadow_y in range(5):
			for x in range(tile_size.x):
				var contact: int = _boundary_offset(style, x, tile_size.x)
				if shadow_y < contact:
					continue
				var fade: float = 1.0
				if (cap_mask & 1) != 0:
					fade *= clampf(float(x + 1) / 5.0, 0.0, 1.0)
				if (cap_mask & 2) != 0:
					fade *= clampf(float(tile_size.x - x) / 5.0, 0.0, 1.0)
				var alpha: float = (0.16 - (shadow_y - contact) * 0.032) * fade
				atlas.set_pixel(variant * tile_size.x + x, height_step + shadow_y, Color(0.055, 0.045, 0.04, alpha))
	return ImageTexture.create_from_image(atlas)


static func _generate_cliff_edge_atlas(original: Texture2D, stone: bool, shoreline: bool, tile_size: Vector2i) -> ImageTexture:
	var base: Image = original.get_image()
	if base.get_size() != tile_size:
		base.resize(tile_size.x, tile_size.y, Image.INTERPOLATE_NEAREST)
	base.convert(Image.FORMAT_RGBA8)
	var atlas := Image.create(tile_size.x * 16, tile_size.y * 9, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	for variant in range(9):
		var style: int = variant / 3
		var drop: int = variant % 3 + 1
		var row_offset: int = variant * tile_size.y
		for edge_mask in range(1, 16):
			var north: bool = (edge_mask & 1) != 0
			var west: bool = (edge_mask & 2) != 0
			var east: bool = (edge_mask & 4) != 0
			var south: bool = (edge_mask & 8) != 0
			var lip_rows: int = 2 if style == TerrainChunkBuildJob.EDGE_STYLE_SIMPLIFIED else 3
			var lip_start: int = 2 if style == TerrainChunkBuildJob.EDGE_STYLE_SIMPLIFIED else 0
			var draw_lip: bool = north and not (style == TerrainChunkBuildJob.EDGE_STYLE_SIMPLIFIED and west and east)
			for y in range(tile_size.y):
				if draw_lip and y >= lip_start and y < lip_start + lip_rows:
					var lip_y: int = y - lip_start
					for x in range(tile_size.x):
						if (west and x < tile_size.x * 3 / 8) or (east and x >= tile_size.x * 5 / 8):
							continue
						var pigment: Color = base.get_pixel(x, posmod(x * 3 + y * 5, tile_size.y))
						var shade: float = ((0.70 if stone else 0.67) if lip_y == 0 else (0.91 if lip_y == 1 else 1.08))
						if shoreline:
							pigment = pigment.lerp(Color("9fc8c5"), 0.18)
						pigment.r *= shade; pigment.g *= shade; pigment.b *= shade
						pigment.a = ([0.44, 0.22][lip_y] if style == TerrainChunkBuildJob.EDGE_STYLE_SIMPLIFIED else [0.58, 0.42, 0.24][lip_y])
						atlas.set_pixel(edge_mask * tile_size.x + x, row_offset + y, pigment)
				for side in range(2):
					var exposed: bool = west if side == 0 else east
					if not exposed:
						continue
					var width: int = _side_return_width(style, drop, side, y, south, north, tile_size.y)
					for inset in range(width):
						var x: int = inset if side == 0 else tile_size.x - 1 - inset
						var pigment: Color = base.get_pixel(posmod(inset * 5 + y + style * 3, tile_size.x), posmod(y * 2 + side * 7 + drop * 5, tile_size.y))
						var shade: float = (0.68 if side == 0 else 0.82) + inset * 0.035
						if posmod(y + style * 2, 7) == 0: shade -= 0.07
						if posmod(y * 13 + inset * 19 + style * 11, 41) == 0: shade -= 0.13
						if not stone: pigment = pigment.lerp(Color("7a4928"), 0.62)
						if shoreline: pigment = pigment.lerp(Color("8fb7b5"), 0.14)
						pigment.r = clampf(pigment.r * shade, 0.0, 1.0); pigment.g = clampf(pigment.g * shade, 0.0, 1.0); pigment.b = clampf(pigment.b * shade, 0.0, 1.0)
						pigment.a = 0.94 - float(inset) * 0.055
						var atlas_x: int = edge_mask * tile_size.x + x
						var atlas_y: int = row_offset + y
						atlas.set_pixel(atlas_x, atlas_y, atlas.get_pixel(atlas_x, atlas_y).blend(pigment))
	return ImageTexture.create_from_image(atlas)


static func _boundary_offset(style: int, x: int, width: int) -> int:
	if x <= 1 or x >= width - 2:
		return 0
	return [1, 0, 2, 1, 2, 0, 1, 0][posmod(floori(float(x) / 4.0) + style * 3, 8)]


static func _side_inset(style: int, y: int) -> int:
	return [2, 3, 1, 2][posmod(floori(float(y) / 3.0) + style, 4)]


static func _side_return_width(style: int, drop: int, side: int, y: int, south: bool, north: bool, tile_height: int) -> int:
	if not south:
		if drop == 1 and y == tile_height / 2 - 1:
			return 0
		var width: int = 2 + clampi(drop, 1, 3) / 2
		if style == TerrainChunkBuildJob.EDGE_STYLE_SIMPLIFIED: width = 2
		if posmod(y + style * 3 + side * 2, 7) == 0: width = maxi(1, width - 1)
		return width
	var depth: int = 5 + clampi(drop, 1, 3) * 2
	if style == TerrainChunkBuildJob.EDGE_STYLE_SIMPLIFIED: depth -= 2
	var start_y: int = tile_height - depth
	if y >= start_y:
		var width: int = 2 + floori(float(y - start_y) / float(maxi(depth - 1, 1)) * float(2 + drop))
		if style == TerrainChunkBuildJob.EDGE_STYLE_SIMPLIFIED: width = mini(width, 4)
		if posmod(y + style * 3 + side * 2, 5) == 0: width = maxi(1, width - 1)
		return width
	if north and y < 3:
		return 2
	return 0

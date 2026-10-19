extends RefCounted
## Adapts Isolony's deterministic procedural canvases to the terrain renderer's
## bounded shared atlas. Presentation is precomputed; gameplay state stays in
## TerrainWorld and the existing placement pipeline.

const ProcTrees = preload("res://scripts/procgen/proc_trees.gd")
const ProcBoulders = preload("res://scripts/procgen/proc_boulders.gd")
const ProcBushes = preload("res://scripts/procgen/proc_bushes.gd")

const ATLAS_CELL_SIZE := Vector2i(96, 96)
const PRESENTATION_SEED_SALT: int = 17622463


static func is_supported(definition: Dictionary) -> bool:
	return String(definition.get("procedural_kind", "")) in ["tree", "boulder", "berry_bush"]


static func draw_variant(
		atlas: Image, atlas_x: int,
		definition: Dictionary, variant: int, ripe: bool = true) -> Dictionary:
	var seed: int = _variant_seed(int(definition["id"]), variant)
	var result: Dictionary = _generate(definition, seed)
	var canvas = result["canvas"]
	var sprite: Image = canvas.to_image()
	if not ripe and String(definition.get("procedural_kind", "")) == "berry_bush":
		_remove_berries(sprite, result.get("berry_points", []))
	var scale: float = float(definition.get("procedural_scale", 1.0))
	if not is_equal_approx(scale, 1.0):
		var scaled_size := Vector2i(
			maxi(1, roundi(float(sprite.get_width()) * scale)),
			maxi(1, roundi(float(sprite.get_height()) * scale)))
		sprite.resize(scaled_size.x, scaled_size.y, Image.INTERPOLATE_NEAREST)
	var root_anchor: Vector2i = definition.get("root_anchor", Vector2i(48, 89))
	var destination := Vector2i(
		atlas_x * ATLAS_CELL_SIZE.x + root_anchor.x - sprite.get_width() / 2,
		root_anchor.y - sprite.get_height() + 1)
	if String(definition.get("procedural_kind", "")) == "tree":
		_draw_tree_shadow(atlas, atlas_x, root_anchor, sprite.get_width())
	atlas.blend_rect(sprite, Rect2i(Vector2i.ZERO, sprite.get_size()), destination)
	result["seed"] = seed
	result["atlas_size"] = sprite.get_size()
	return result


static func _draw_tree_shadow(
		atlas: Image, atlas_x: int, root_anchor: Vector2i, sprite_width: int) -> void:
	## Quantised north-west light produces a restrained south-east ground shadow.
	var center := Vector2i(atlas_x * ATLAS_CELL_SIZE.x + root_anchor.x + 4, root_anchor.y - 1)
	var radius_x: int = clampi(sprite_width / 3, 6, 18)
	var radius_y: int = clampi(radius_x / 3, 2, 5)
	for y in range(-radius_y, radius_y + 1):
		for x in range(-radius_x, radius_x + 1):
			var distance: float = (
				float(x * x) / float(radius_x * radius_x)
				+ float(y * y) / float(radius_y * radius_y))
			if distance > 1.0:
				continue
			var alpha: int = 62 if distance < 0.55 else 38
			atlas.set_pixel(center.x + x, center.y + y, Color8(20, 27, 19, alpha))


static func _remove_berries(sprite: Image, berry_points: Array) -> void:
	## The source generator returns cosmetic berry locations. Removing those
	## pixels creates a cached unripe presentation without changing food yield.
	var foliage := Color8(55, 104, 54, 245)
	for point_value in berry_points:
		var point := Vector2(point_value)
		for y in range(floori(point.y) - 2, ceili(point.y) + 3):
			for x in range(floori(point.x) - 2, ceili(point.x) + 3):
				if x < 0 or y < 0 or x >= sprite.get_width() or y >= sprite.get_height():
					continue
				if Vector2(x, y).distance_squared_to(point) > 4.5:
					continue
				if sprite.get_pixel(x, y).a > 0.0:
					sprite.set_pixel(x, y, foliage)


static func _generate(definition: Dictionary, seed: int) -> Dictionary:
	var kind: String = String(definition["procedural_kind"])
	var size: int = int(definition.get("procedural_size", 24))
	var archetype: String = String(definition.get("procedural_archetype", ""))
	var terrain_tag: String = String(definition.get("procedural_terrain_tag", "default"))
	match kind:
		"tree":
			return ProcTrees.generate_tree(
				seed, size, archetype, terrain_tag,
				String(definition.get("procedural_size_tier", "medium")),
				String(definition.get("procedural_presentation_profile", "mature")))
		"boulder":
			return ProcBoulders.generate_boulder(
				seed, size, archetype, terrain_tag,
				String(definition.get("procedural_size_tier", "medium")))
		"berry_bush":
			return ProcBushes.generate_bush(seed, size, archetype, terrain_tag)
	assert(false, "Unsupported environmental-object procedural kind")
	return {}


static func _variant_seed(definition_id: int, variant: int) -> int:
	return PRESENTATION_SEED_SALT + (definition_id + 1) * 100003 + (variant + 1) * 7919

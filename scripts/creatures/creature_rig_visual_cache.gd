extends RefCounted
## Bounded cache for immutable per-part artwork and native textures. Images are
## retained for CPU reference rendering; Sprite2D presenters share the textures.

const AppearanceCache = preload("res://scripts/creatures/creature_appearance_cache.gd")
const Renderer = preload("res://scripts/creatures/creature_renderer.gd")
const Rig = preload("res://scripts/creatures/creature_rig.gd")

const MAX_ENTRIES := 128
var _entries: Dictionary = {}
var _order: Array[String] = []
var generation_count := 0
var cache_hit_count := 0
var texture_creation_count := 0

func get_or_generate(anatomy: Dictionary, rig: Dictionary, direction: String = "south") -> Dictionary:
	var key := cache_key(anatomy, direction)
	if _entries.has(key):
		cache_hit_count += 1
		return _entries[key]
	var rendered := Renderer.render_rig_parts(anatomy, direction)
	var packed_layers: Dictionary = {}
	for layer_name in rendered.layers:
		var image: Image = rendered.layers[layer_name]
		var texture := ImageTexture.create_from_image(image)
		packed_layers[layer_name] = {"image": image, "texture": texture, "bounds": _opaque_bounds(image)}
		texture_creation_count += 1
	var entry := {"key": key, "rig": rig, "layers": packed_layers, "direction": direction}
	_entries[key] = entry
	_order.append(key)
	generation_count += 1
	if _order.size() > MAX_ENTRIES:
		_entries.erase(_order.pop_front())
	return entry

func clear() -> void:
	_entries.clear()
	_order.clear()

func entry_count() -> int:
	return _entries.size()

func approximate_memory_bytes() -> int:
	var total := 0
	for entry: Dictionary in _entries.values():
		for packed: Dictionary in entry.layers.values():
			var image: Image = packed.image
			# One CPU RGBA image plus one approximate RGBA GPU texture allocation.
			total += image.get_width() * image.get_height() * 8
	return total

static func cache_key(anatomy: Dictionary, direction: String) -> String:
	return "%s|%s|%s" % [Rig.RIG_VERSION, AppearanceCache.cache_key(anatomy, direction), direction]

static func _opaque_bounds(image: Image) -> Rect2i:
	var minimum := Vector2i(image.get_width(), image.get_height())
	var maximum := Vector2i(-1, -1)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.0:
				continue
			minimum = Vector2i(mini(minimum.x, x), mini(minimum.y, y))
			maximum = Vector2i(maxi(maximum.x, x), maxi(maximum.y, y))
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE) if maximum.x >= 0 else Rect2i()

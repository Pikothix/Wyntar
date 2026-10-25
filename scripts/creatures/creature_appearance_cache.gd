extends RefCounted
## Bounded workshop appearance cache. Cached data is presentation-only and can
## be discarded without affecting generated anatomy or future simulation state.

const Generator = preload("res://scripts/creatures/creature_generator.gd")
const Renderer = preload("res://scripts/creatures/creature_renderer.gd")

const MAX_ENTRIES := 192
var _entries: Dictionary = {}
var _order: Array[String] = []

func get_or_generate(anatomy: Dictionary, direction: String = "south") -> Dictionary:
	var key := cache_key(anatomy, direction)
	if _entries.has(key):
		var cached: Dictionary = (_entries[key] as Dictionary).duplicate()
		cached["cache_hit"] = true
		return cached
	var result := Renderer.render_creature(anatomy, direction)
	result["cache_hit"] = false
	_entries[key] = result.duplicate()
	_order.append(key)
	if _order.size() > MAX_ENTRIES:
		_entries.erase(_order.pop_front())
	return result

func clear() -> void:
	_entries.clear()
	_order.clear()

func entry_count() -> int:
	return _entries.size()

func approximate_memory_bytes() -> int:
	return _entries.size() * Renderer.CANVAS_SIZE * Renderer.CANVAS_SIZE * 4

static func cache_key(anatomy: Dictionary, direction: String) -> String:
	return "%s|%s|%d|%s|%.3f|%s|%s" % [
		Generator.GENERATOR_VERSION, anatomy.species_id, int(anatomy.individual_seed),
		anatomy.archetype, float(anatomy.variation_strength),
		str(bool(anatomy.markings.enabled)), direction]

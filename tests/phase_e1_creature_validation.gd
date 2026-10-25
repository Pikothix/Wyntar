extends SceneTree
## Focused E1/E1B contract validation; no terrain or world systems are loaded.

const Species = preload("res://scripts/creatures/creature_species.gd")
const Generator = preload("res://scripts/creatures/creature_generator.gd")
const Renderer = preload("res://scripts/creatures/creature_renderer.gd")
const AppearanceCache = preload("res://scripts/creatures/creature_appearance_cache.gd")

var failures: Array[String] = []

func _initialize() -> void:
	_run()

func _run() -> void:
	_test_deterministic_contract()
	_test_independent_streams()
	_test_balanced_distribution()
	_test_archetype_silhouette_differentiation()
	_test_marking_families()
	_test_seed_range()
	_test_cache_contract()
	if failures.is_empty():
		print("PHASE_E1B_VALIDATION: PASS (128 seeds, 48 workshop entries)")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("PHASE_E1B_VALIDATION: FAIL (%d failures)" % failures.size())
		quit(1)

func _test_deterministic_contract() -> void:
	var first := Generator.generate_creature(Species.SPECIES_ID, 84521, 0.6, "compact", true)
	var second := Generator.generate_creature(Species.SPECIES_ID, 84521, 0.6, "compact", true)
	_expect(first == second, "identical generation inputs must reproduce anatomy")
	var first_render := Renderer.render_creature(first, "south")
	var second_render := Renderer.render_creature(second, "south")
	_expect(first_render.image.get_data() == second_render.image.get_data(), "identical anatomy and direction must reproduce pixels")
	_expect(first.generator_version == Generator.GENERATOR_VERSION, "anatomy must record generator version")

func _test_independent_streams() -> void:
	for seed in [1, 84521, 998244353]:
		var enabled := Generator.generate_creature(Species.SPECIES_ID, seed, 0.6, "elongated", true)
		var disabled := Generator.generate_creature(Species.SPECIES_ID, seed, 0.6, "elongated", false)
		_expect(Generator.anatomy_signature(enabled) == Generator.anatomy_signature(disabled), "marking toggle must not alter anatomy for seed %d" % seed)
		_expect(enabled.palette == disabled.palette, "marking toggle must not alter palette for seed %d" % seed)

func _test_balanced_distribution() -> void:
	var counts := {"compact": 0, "elongated": 0, "stocky": 0}
	for index in range(48):
		counts[Generator.mixed_archetype(84521, index)] += 1
	for archetype in ["compact", "elongated", "stocky"]:
		_expect(int(counts[archetype]) == 16, "mixed workshop must contain 16 %s creatures" % archetype)

func _test_archetype_silhouette_differentiation() -> void:
	var aspect_totals := {"compact": 0.0, "elongated": 0.0, "stocky": 0.0}
	var mass_totals := {"compact": 0.0, "elongated": 0.0, "stocky": 0.0}
	for index in range(24):
		var seed := Generator.individual_seed(84521, index)
		var hashes: Dictionary = {}
		for archetype in ["compact", "elongated", "stocky"]:
			var anatomy := Generator.generate_creature(Species.SPECIES_ID, seed, 0.6, archetype, false)
			var result := Renderer.render_creature(anatomy)
			hashes[hash(_alpha_bytes(result.image))] = true
			aspect_totals[archetype] += float(result.opaque_bounds.size.x) / float(result.opaque_bounds.size.y)
			mass_totals[archetype] += float(_opaque_pixel_count(result.image))
		_expect(hashes.size() == 3, "seed index %d must produce three distinct archetype silhouettes" % index)
	var compact_aspect: float = float(aspect_totals.compact) / 24.0
	var elongated_aspect: float = float(aspect_totals.elongated) / 24.0
	_expect(elongated_aspect + 0.12 < compact_aspect, "elongated silhouettes must be materially narrower than compact silhouettes")
	_expect(float(mass_totals.stocky) > float(mass_totals.compact) * 1.08, "stocky silhouettes must carry materially more visual mass than compact silhouettes")

func _test_marking_families() -> void:
	var found: Dictionary = {}
	for seed in range(1, 300):
		var anatomy := Generator.generate_creature(Species.SPECIES_ID, seed, 0.6, "compact", true)
		var style: String = anatomy.markings.style
		if found.has(style):
			continue
		var result := Renderer.render_creature(anatomy)
		if style == "none":
			_expect(int(result.marking_pixels) == 0, "unmarked family must not paint marking pixels")
		else:
			_expect(int(result.marking_pixels) > 0, "%s family must paint visible pixels" % style)
			_expect(int(result.marking_pixels_outside_anatomy) == 0, "%s family must remain on anatomy" % style)
		found[style] = true
		if found.size() == 5:
			break
	for style in ["none", "spots", "stripes", "patches", "socks"]:
		_expect(found.has(style), "marking family %s must be reachable" % style)

func _test_seed_range() -> void:
	var distinct_anatomies: Dictionary = {}
	var distinct_pixels: Dictionary = {}
	for index in range(128):
		var seed := Generator.individual_seed(84521, index)
		var archetype: String = ["compact", "elongated", "stocky"][index % 3]
		var anatomy := Generator.generate_creature(Species.SPECIES_ID, seed, 0.6, archetype, true)
		var result := Renderer.render_creature(anatomy)
		_validate_bounds(anatomy, index)
		_validate_attachments(anatomy, index)
		_expect(not result.image.is_empty(), "seed index %d must render an image" % index)
		_expect(result.opaque_bounds.has_area(), "seed index %d must contain opaque pixels" % index)
		_expect(not result.clipped, "seed index %d must not clip the canvas" % index)
		_expect(_opaque_components(result.image) == 1, "seed index %d must form one connected silhouette" % index)
		_validate_rendered_anatomy(result, index)
		if anatomy.markings.enabled and anatomy.markings.style != "none":
			_expect(int(result.marking_pixels) > 0, "seed index %d marking must land on anatomy" % index)
		distinct_anatomies[Generator.anatomy_signature(anatomy)] = true
		distinct_pixels[hash(result.image.get_data())] = true
	_expect(distinct_anatomies.size() >= 120, "128 seeds should produce at least 120 distinct anatomies")
	_expect(distinct_pixels.size() >= 112, "128 seeds should produce at least 112 distinct rendered appearances")

func _validate_bounds(anatomy: Dictionary, index: int) -> void:
	var profile := Species.profile(anatomy.archetype)
	for property_name in profile:
		var value: float = float(anatomy.dimensions[property_name])
		var limits: Array = profile[property_name]
		_expect(value >= float(limits[1]) - 0.01 and value <= float(limits[2]) + 0.01, "seed index %d %s must remain within profile bounds" % [index, property_name])
	var d: Dictionary = anatomy.dimensions
	_expect(float(d.head_width) <= float(d.torso_width) * 0.92 + 0.01, "head width constraint failed at index %d" % index)
	_expect(float(d.snout_length) <= float(d.head_size) * 0.72 + 0.01, "snout constraint failed at index %d" % index)

func _validate_attachments(anatomy: Dictionary, index: int) -> void:
	var a: Dictionary = anatomy.attachments
	var d: Dictionary = anatomy.dimensions
	for key in ["head_root", "tail_root", "ear_left", "ear_right", "leg_front_left", "leg_front_right", "leg_back_left", "leg_back_right"]:
		_expect(a.has(key) and a[key] is Vector2, "seed index %d must expose %s" % [index, key])
	var half_length: float = float(d.torso_length) * 0.5
	var half_width: float = float(d.torso_width) * 0.5
	for key in ["leg_front_left", "leg_front_right", "leg_back_left", "leg_back_right"]:
		var point: Vector2 = a[key]
		_expect(absf(point.x) <= half_width and absf(point.y) <= half_length, "seed index %d leg root must attach inside torso" % index)
	_expect(absf(a.head_root.y) <= half_length and absf(a.tail_root.y) <= half_length, "seed index %d head/tail roots must attach to torso" % index)
	_expect(a.head_root.y > 0.0 and a.tail_root.y < 0.0, "seed index %d head and tail must attach to opposing body ends" % index)

func _validate_rendered_anatomy(result: Dictionary, index: int) -> void:
	_expect(result.limb_endpoints.size() == 4, "seed index %d must render four limb endpoints" % index)
	var unique_endpoints: Dictionary = {}
	for endpoint: Vector2i in result.limb_endpoints:
		unique_endpoints[endpoint] = true
		_expect(result.image.get_pixelv(endpoint).a > 0.0, "seed index %d limb endpoint must remain visible" % index)
	_expect(unique_endpoints.size() == 4, "seed index %d limbs must retain four distinct endpoints" % index)
	_expect(result.image.get_pixelv(result.head_root_pixel).a > 0.0, "seed index %d head root must remain attached" % index)
	_expect(result.image.get_pixelv(result.head_center_pixel).a > 0.0, "seed index %d head centre must remain rendered" % index)
	_expect(result.head_root_pixel.distance_to(result.head_center_pixel) >= 3.0, "seed index %d head must remain visually distinct from torso" % index)

func _test_cache_contract() -> void:
	var cache := AppearanceCache.new()
	var anatomy := Generator.generate_creature(Species.SPECIES_ID, 7123, 0.6, "stocky", true)
	var first := cache.get_or_generate(anatomy)
	var second := cache.get_or_generate(anatomy)
	_expect(not first.cache_hit and second.cache_hit, "second identical appearance request must hit cache")
	_expect(cache.entry_count() == 1, "identical appearance requests must occupy one cache entry")
	var changed := Generator.generate_creature(Species.SPECIES_ID, 7123, 0.6, "stocky", false)
	cache.get_or_generate(changed)
	_expect(cache.entry_count() == 2, "marking setting must participate in cache key")
	_expect(AppearanceCache.cache_key(anatomy, "south").begins_with(Generator.GENERATOR_VERSION), "cache key must include current generator version")

func _alpha_bytes(image: Image) -> PackedByteArray:
	var alpha := PackedByteArray()
	alpha.resize(image.get_width() * image.get_height())
	var index := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			alpha[index] = image.get_pixel(x, y).a8
			index += 1
	return alpha

func _opaque_pixel_count(image: Image) -> int:
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.0:
				count += 1
	return count

func _opaque_components(image: Image) -> int:
	var visited: Dictionary = {}
	var components := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var start := Vector2i(x, y)
			if image.get_pixel(x, y).a <= 0.0 or visited.has(start):
				continue
			components += 1
			var pending: Array[Vector2i] = [start]
			visited[start] = true
			while not pending.is_empty():
				var point: Vector2i = pending.pop_back()
				for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var neighbor: Vector2i = point + offset
					if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= image.get_width() or neighbor.y >= image.get_height() or visited.has(neighbor):
						continue
					if image.get_pixelv(neighbor).a > 0.0:
						visited[neighbor] = true
						pending.append(neighbor)
	return components

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

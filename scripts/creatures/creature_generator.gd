extends RefCounted
## Deterministic E1 anatomy author. It owns no runtime simulation state and
## returns plain inspectable data for renderers, future rigs, and validation.

const ProcRng = preload("res://scripts/procgen/proc_rng.gd")
const Species = preload("res://scripts/creatures/creature_species.gd")

const GENERATOR_VERSION := "e1b-v2"
const ANATOMY_SALT := 0x13579bdf
const PALETTE_SALT := 0x2468ace1
const MARKING_SALT := 0x51c3d12d

static func generate_creature(
		species_id: String, individual_seed: int, variation_strength: float = 0.6,
		archetype: String = "compact", markings_enabled: bool = true) -> Dictionary:
	assert(Species.is_valid_species(species_id), "Unsupported creature species")
	var resolved_archetype := Species.resolve_archetype(archetype)
	var strength := clampf(variation_strength, 0.0, 1.0)
	var anatomy_rng := ProcRng.new(_stream_seed(individual_seed, ANATOMY_SALT))
	var palette_rng := ProcRng.new(_stream_seed(individual_seed, PALETTE_SALT))
	var marking_rng := ProcRng.new(_stream_seed(individual_seed, MARKING_SALT))
	var profile := Species.profile(resolved_archetype)
	var dimensions: Dictionary = {}
	for property_name in profile:
		var values: Array = profile[property_name]
		var base: float = float(values[0])
		var sampled: float = anatomy_rng.next_range(float(values[1]), float(values[2]))
		dimensions[property_name] = clampf(snappedf(base + strength * (sampled - base), 0.1), float(values[1]), float(values[2]))
	_apply_constraints(dimensions)

	var available_heads: Array = Species.head_shapes(resolved_archetype)
	var available_ears: Array = Species.ear_shapes(resolved_archetype)
	var tail_curve: float = anatomy_rng.next_range(-0.78, 0.78) * strength
	if resolved_archetype == "elongated" and absf(tail_curve) < 0.28:
		tail_curve = 0.28 if tail_curve >= 0.0 else -0.28
	var traits := {
		"head_shape": available_heads[anatomy_rng.next_int(0, available_heads.size() - 1)],
		"ear_shape": available_ears[anatomy_rng.next_int(0, available_ears.size() - 1)],
		"ear_orientation": ["upright", "outward"][anatomy_rng.next_int(0, 1)],
		"tail_curve": tail_curve,
		"tail_shape": {"compact": "rounded", "elongated": "curved", "stocky": "club"}[resolved_archetype],
		"eye_spacing": anatomy_rng.next_range(0.34, 0.48),
	}
	var attachments := _build_attachments(dimensions)
	var palette := _build_palette(palette_rng)
	var markings := _build_markings(marking_rng, markings_enabled)
	return {
		"generator_version": GENERATOR_VERSION,
		"species_id": species_id,
		"individual_seed": individual_seed,
		"archetype": resolved_archetype,
		"variation_strength": strength,
		"dimensions": dimensions,
		"traits": traits,
		"attachments": attachments,
		"pivots": {"anatomy": Vector2(0.0, 0.0), "ground_contact": Vector2(0.0, 1.0)},
		"palette": palette,
		"markings": markings,
	}

static func anatomy_signature(creature: Dictionary) -> int:
	return hash([creature.archetype, creature.dimensions, creature.traits, creature.attachments])

static func mixed_archetype(reference_seed: int, index: int) -> String:
	## Rotation keeps every contiguous 48-creature workshop batch at 16 each.
	var offset: int = abs(reference_seed) % Species.ARCHETYPES.size()
	return Species.ARCHETYPES[(index + offset) % Species.ARCHETYPES.size()]

static func individual_seed(reference_seed: int, index: int) -> int:
	return int(ProcRng.derive_spatial_seed(index, index * 17 + 3, reference_seed, 0x2f6e2b1))

static func _stream_seed(seed: int, salt: int) -> int:
	return int(ProcRng.derive_spatial_seed(seed, seed ^ 0x1f123bb5, 0x6a09e667, salt))

static func _apply_constraints(dimensions: Dictionary) -> void:
	dimensions.head_width = minf(float(dimensions.head_width), float(dimensions.torso_width) * 0.92)
	dimensions.head_size = minf(float(dimensions.head_size), float(dimensions.torso_length) * 0.72)
	dimensions.snout_length = minf(float(dimensions.snout_length), float(dimensions.head_size) * 0.72)
	dimensions.leg_thickness = minf(float(dimensions.leg_thickness), float(dimensions.torso_width) * 0.3)
	dimensions.tail_thickness = minf(float(dimensions.tail_thickness), float(dimensions.torso_width) * 0.3)
	dimensions.ear_size = minf(float(dimensions.ear_size), float(dimensions.head_size) * 0.66)
	dimensions.snout_width = clampf(float(dimensions.snout_width), 0.3, 0.96)

static func _build_attachments(dimensions: Dictionary) -> Dictionary:
	var torso_half_length: float = float(dimensions.torso_length) * 0.5
	var torso_half_width: float = float(dimensions.torso_width) * 0.5
	var pair_separation: float = torso_half_length * float(dimensions.leg_pair_separation)
	var normalized_separation: float = pair_separation / torso_half_length
	var body_exponent: float = lerpf(0.72, 0.38, float(dimensions.torso_roundness))
	var body_curve: float = pow(maxf(0.0, 1.0 - normalized_separation * normalized_separation), body_exponent)
	var front_profile: float = lerpf(float(dimensions.hip_scale), float(dimensions.shoulder_scale), (normalized_separation + 1.0) * 0.5)
	var back_profile: float = lerpf(float(dimensions.hip_scale), float(dimensions.shoulder_scale), (-normalized_separation + 1.0) * 0.5)
	var end_taper: float = 1.0 - float(dimensions.torso_taper) * normalized_separation
	var lateral_root: float = maxf(1.0, torso_half_width * body_curve * minf(front_profile, back_profile) * end_taper * 0.7)
	return {
		"head_root": Vector2(0.0, torso_half_length * 0.9),
		"tail_root": Vector2(0.0, -torso_half_length * 0.9),
		"ear_left": Vector2(-float(dimensions.head_width) * 0.36, torso_half_length + float(dimensions.neck_length) + float(dimensions.head_size) * 0.36),
		"ear_right": Vector2(float(dimensions.head_width) * 0.36, torso_half_length + float(dimensions.neck_length) + float(dimensions.head_size) * 0.36),
		"leg_front_left": Vector2(-lateral_root, pair_separation),
		"leg_front_right": Vector2(lateral_root, pair_separation),
		"leg_back_left": Vector2(-lateral_root, -pair_separation),
		"leg_back_right": Vector2(lateral_root, -pair_separation),
	}

static func _build_palette(rng: ProcRng) -> Dictionary:
	var family: Array = Species.COAT_FAMILIES[rng.next_int(0, Species.COAT_FAMILIES.size() - 1)]
	var jitter: int = rng.next_int(-8, 8)
	var colors: Array = []
	for source: Array in family:
		colors.append(Color8(clampi(source[0] + jitter, 0, 255), clampi(source[1] + jitter, 0, 255), clampi(source[2] + jitter, 0, 255), 255))
	return {"shadow": colors[0], "base": colors[1], "highlight": colors[2], "detail": Color8(35, 29, 27, 255)}

static func _build_markings(rng: ProcRng, enabled: bool) -> Dictionary:
	var style: String = ["none", "socks", "spots", "stripes", "patches"][rng.next_int(0, 4)] if enabled else "none"
	var spots: Array[Dictionary] = []
	if style == "spots":
		for _i in range(rng.next_int(2, 5)):
			spots.append({"u": rng.next_range(-0.62, 0.62), "v": rng.next_range(-0.58, 0.48), "radius": rng.next_range(1.1, 2.3)})
	var stripes: Array[float] = []
	if style == "stripes":
		var stripe_count := rng.next_int(2, 4)
		for stripe_index in range(stripe_count):
			stripes.append(-0.48 + float(stripe_index) * 0.78 / maxf(1.0, float(stripe_count - 1)) + rng.next_range(-0.05, 0.05))
	var patches: Array[Dictionary] = []
	if style == "patches":
		for _i in range(rng.next_int(1, 3)):
			patches.append({"u": rng.next_range(-0.45, 0.45), "v": rng.next_range(-0.46, 0.38), "rx": rng.next_range(2.4, 4.2), "ry": rng.next_range(2.0, 4.6)})
	return {"enabled": enabled, "style": style, "spots": spots, "stripes": stripes, "patches": patches, "tone": rng.next_range(0.68, 0.86)}

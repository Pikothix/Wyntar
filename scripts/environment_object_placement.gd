extends RefCounted
## Pure, order-independent placement for large presentation objects. Every
## decision is derived from an absolute anchor, world seed and authoritative
## terrain samples; chunk load order never participates.

const EMPTY := Vector2i(-1, -1)
const ANCHOR_FRACTION: float = 0.03125
const MAX_EXCLUSION_RADIUS: int = 3
const GROUND_DECORATION_MARGIN: int = 1


static func choose(
        world_pos: Vector2i,
        context: Dictionary,
        material_lookup: Callable,
        ground_height_lookup: Callable,
        surface_height_lookup: Callable,
        candidate_cache: Dictionary = {}) -> Vector2i:
    var candidate: Vector2i = _cached_candidate(
        world_pos, context, material_lookup,
        ground_height_lookup, surface_height_lookup,
        candidate_cache, false)
    if candidate.x < 0:
        return EMPTY
    var definitions_by_id: Dictionary = context["definitions_by_id"]
    var definition: Dictionary = definitions_by_id[candidate.x]
    var exclusion_radius: int = int(definition["exclusion_radius"])
    var candidate_priority: int = _priority_hash(
        world_pos, int(context["seed"]), candidate.x)
    for y in range(world_pos.y - MAX_EXCLUSION_RADIUS, world_pos.y + MAX_EXCLUSION_RADIUS + 1):
        for x in range(world_pos.x - MAX_EXCLUSION_RADIUS, world_pos.x + MAX_EXCLUSION_RADIUS + 1):
            var neighbor_pos := Vector2i(x, y)
            if neighbor_pos == world_pos or not is_candidate_anchor(neighbor_pos, int(context["seed"])):
                continue
            var neighbor: Vector2i = _cached_candidate(
                neighbor_pos, context, material_lookup,
                ground_height_lookup, surface_height_lookup,
                candidate_cache, true)
            if neighbor.x < 0:
                continue
            var neighbor_definition: Dictionary = definitions_by_id[neighbor.x]
            var conflict_radius: int = maxi(
                exclusion_radius, int(neighbor_definition["exclusion_radius"]))
            if maxi(abs(x - world_pos.x), abs(y - world_pos.y)) > conflict_radius:
                continue
            var neighbor_priority: int = _priority_hash(
                neighbor_pos, int(context["seed"]), neighbor.x)
            if neighbor_priority < candidate_priority:
                return EMPTY
            if neighbor_priority == candidate_priority and _coordinate_precedes(neighbor_pos, world_pos):
                return EMPTY
    return candidate


static func _cached_candidate(
        world_pos: Vector2i,
        context: Dictionary,
        material_lookup: Callable,
        ground_height_lookup: Callable,
        surface_height_lookup: Callable,
        candidate_cache: Dictionary,
        anchor_already_checked: bool) -> Vector2i:
    if candidate_cache.has(world_pos):
        return candidate_cache[world_pos]
    var candidate: Vector2i = _choose_candidate(
        world_pos, context, material_lookup,
        ground_height_lookup, surface_height_lookup,
        anchor_already_checked)
    candidate_cache[world_pos] = candidate
    return candidate


static func _choose_candidate(
        world_pos: Vector2i,
        context: Dictionary,
        material_lookup: Callable,
        ground_height_lookup: Callable,
        surface_height_lookup: Callable,
        anchor_already_checked: bool = false) -> Vector2i:
    var seed: int = int(context["seed"])
    if not anchor_already_checked and not is_candidate_anchor(world_pos, seed):
        return EMPTY
    var terrain_id: int = int(material_lookup.call(world_pos))
    var liquid_by_id: Dictionary = context["liquid_by_id"]
    if bool(liquid_by_id.get(terrain_id, false)):
        return EMPTY
    var indices_by_material: Dictionary = context["indices_by_material"]
    if not indices_by_material.has(terrain_id):
        return EMPTY
    var global_density: float = float(context["density"])
    if global_density <= 0.0:
        return EMPTY
    var maximum_probability: float = minf(
        0.92,
        float(context["max_density_by_material"].get(terrain_id, 0.0))
            * global_density * 1.6 / ANCHOR_FRACTION)
    var placement_roll: float = _hash_unit(world_pos.x, world_pos.y, seed, 17011)
    if placement_roll >= maximum_probability:
        return EMPTY

    var surface_height: int = int(surface_height_lookup.call(world_pos))
    var ground_height: int = int(ground_height_lookup.call(world_pos))
    var near_water: bool = false
    for offset in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
        if bool(liquid_by_id.get(int(material_lookup.call(world_pos + offset)), false)):
            near_water = true
            break

    var definitions: Array = context["definitions"]
    var total_density: float = 0.0
    for definition_index in indices_by_material[terrain_id]:
        var definition: Dictionary = definitions[int(definition_index)]
        total_density += _eligible_density(
            world_pos, definition, ground_height, near_water,
            seed, global_density)
    total_density = minf(total_density, 0.92)
    if placement_roll >= total_density:
        return EMPTY

    var selection_roll: float = _hash_unit(
        world_pos.x, world_pos.y, seed, 19001) * total_density
    var accumulated: float = 0.0
    for definition_index in indices_by_material[terrain_id]:
        var definition: Dictionary = definitions[int(definition_index)]
        accumulated += _eligible_density(
            world_pos, definition, ground_height, near_water,
            seed, global_density)
        if selection_roll >= accumulated:
            continue
        if not _footprint_is_valid(
                world_pos, surface_height, definition, material_lookup,
                ground_height_lookup, surface_height_lookup, liquid_by_id):
            return EMPTY
        var object_id: int = int(definition["id"])
        var variant: int = posmod(
            _hash_int(world_pos.x, world_pos.y, seed, object_id * 431 + 97),
            maxi(1, int(definition.get("variants", 1))))
        return Vector2i(object_id, variant)
    return EMPTY


static func _eligible_density(
        world_pos: Vector2i,
        definition: Dictionary,
        ground_height: int,
        near_water: bool,
        seed: int,
        global_density: float) -> float:
    if ground_height < int(definition.get("min_elevation", 0)):
        return 0.0
    if ground_height > int(definition.get("max_elevation", 3)):
        return 0.0
    var water_rule: Variant = definition.get("water_proximity", "any")
    if water_rule == "required" and not near_water:
        return 0.0
    if water_rule == "forbidden" and near_water:
        return 0.0
    var regional_value: float = _regional_value(
        world_pos, seed, _regional_salt(String(definition["category"])))
    var threshold: float = float(definition.get("cluster_threshold", 0.0))
    if regional_value < threshold:
        return 0.0
    var cluster_strength: float = float(definition.get("cluster_strength", 0.0))
    var cluster_multiplier: float = lerpf(
        1.0,
        clampf((regional_value - threshold) / maxf(0.05, 1.0 - threshold) * 1.8, 0.0, 1.8),
        clampf(cluster_strength, 0.0, 1.5) / 1.5)
    return minf(
        float(definition["density"]) * global_density
            * cluster_multiplier / ANCHOR_FRACTION,
        0.72)


static func _footprint_is_valid(
        world_pos: Vector2i,
        root_surface_height: int,
        definition: Dictionary,
        material_lookup: Callable,
        ground_height_lookup: Callable,
        surface_height_lookup: Callable,
        liquid_by_id: Dictionary) -> bool:
    var allowed_materials: Array = definition["materials"]
    for offset in definition["footprint"]:
        var footprint_pos: Vector2i = world_pos + Vector2i(offset)
        var terrain_id: int = int(material_lookup.call(footprint_pos))
        if bool(liquid_by_id.get(terrain_id, false)) or terrain_id not in allowed_materials:
            return false
        if int(surface_height_lookup.call(footprint_pos)) != root_surface_height:
            return false
        var ground_height: int = int(ground_height_lookup.call(footprint_pos))
        if ground_height < int(definition.get("min_elevation", 0)):
            return false
        if ground_height > int(definition.get("max_elevation", 3)):
            return false
    if bool(definition.get("avoid_dropoffs", true)):
        for offset in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
            var neighbor_pos: Vector2i = world_pos + offset
            var neighbor_id: int = int(material_lookup.call(neighbor_pos))
            if bool(liquid_by_id.get(neighbor_id, false)):
                if definition.get("water_proximity", "any") != "required":
                    return false
                continue
            if abs(int(surface_height_lookup.call(neighbor_pos)) - root_surface_height) > 0:
                return false
    return true


static func is_candidate_anchor(world_pos: Vector2i, seed: int) -> bool:
    return (_hash_int(world_pos.x, world_pos.y, seed, 15013) & 31) == 0


static func _regional_value(world_pos: Vector2i, seed: int, salt: int) -> float:
    const REGION_SIZE: int = 19
    var cell_x: int = floori(float(world_pos.x) / REGION_SIZE)
    var cell_y: int = floori(float(world_pos.y) / REGION_SIZE)
    var local_x: float = posmod(world_pos.x, REGION_SIZE) / float(REGION_SIZE)
    var local_y: float = posmod(world_pos.y, REGION_SIZE) / float(REGION_SIZE)
    var smooth_x: float = local_x * local_x * (3.0 - 2.0 * local_x)
    var smooth_y: float = local_y * local_y * (3.0 - 2.0 * local_y)
    var top: float = lerpf(
        _hash_unit(cell_x, cell_y, seed, salt),
        _hash_unit(cell_x + 1, cell_y, seed, salt), smooth_x)
    var bottom: float = lerpf(
        _hash_unit(cell_x, cell_y + 1, seed, salt),
        _hash_unit(cell_x + 1, cell_y + 1, seed, salt), smooth_x)
    return lerpf(top, bottom, smooth_y)


static func _regional_salt(category: String) -> int:
    match category:
        "trees":
            return 3109
        "bushes":
            return 5209
        "rocks":
            return 7307
        _:
            return 9103


static func _priority_hash(world_pos: Vector2i, seed: int, object_id: int) -> int:
    return _hash_int(world_pos.x, world_pos.y, seed, object_id * 733 + 23003) & 0x7fffffff


static func _coordinate_precedes(a: Vector2i, b: Vector2i) -> bool:
    return a.y < b.y or (a.y == b.y and a.x < b.x)


static func _hash_unit(x: int, y: int, seed: int, salt: int) -> float:
    return float(_hash_int(x, y, seed, salt) & 0x00ffffff) / 16777216.0


static func _hash_int(x: int, y: int, seed: int, salt: int) -> int:
    var value: int = x * 0x1f123bb5 ^ y * 0x5f356495 ^ seed * 0x2c1b3c6d ^ salt
    value = (value ^ (value >> 16)) * 0x45d9f3b
    value = (value ^ (value >> 16)) * 0x45d9f3b
    return value ^ (value >> 16)

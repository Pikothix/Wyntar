extends RefCounted
## Pure deterministic decoration selection. It consumes authoritative samples
## supplied by chunk preparation or live paint refresh and returns one atlas
## anchor at most; it owns no runtime or saved state.

const EMPTY := Vector2i(-1, -1)
const ANCHOR_FRACTION: float = 0.125
const CLUSTER_SIZE: int = 9


static func choose(
        world_pos: Vector2i,
        terrain_id: int,
        ground_elevation: int,
        surface_elevation: int,
        north_id: int,
        east_id: int,
        south_id: int,
        west_id: int,
        north_height: int,
        east_height: int,
        south_height: int,
        west_height: int,
        definitions: Array,
        indices_by_material: Dictionary,
        max_density_by_material: Dictionary,
        liquid_by_id: Dictionary,
        seed: int,
        global_density: float,
        clustering_strength: float,
        anchor_already_checked: bool = false,
        cluster_value_override: float = -1.0) -> Vector2i:
    if bool(liquid_by_id.get(terrain_id, false)):
        return EMPTY
    if not indices_by_material.has(terrain_id) or global_density <= 0.0:
        return EMPTY
    if not anchor_already_checked and not is_candidate_anchor(world_pos, seed):
        return EMPTY
    var maximum_probability: float = minf(
        0.95,
        float(max_density_by_material.get(terrain_id, 0.0))
            * maxf(0.0, global_density) * 1.75 / ANCHOR_FRACTION)
    var placement_roll: float = _hash_unit(world_pos.x, world_pos.y, seed, 9013)
    if placement_roll >= maximum_probability:
        return EMPTY

    var near_water: bool = (
        bool(liquid_by_id.get(north_id, false))
        or bool(liquid_by_id.get(east_id, false))
        or bool(liquid_by_id.get(south_id, false))
        or bool(liquid_by_id.get(west_id, false)))
    var near_cliff: bool = (
        north_height != surface_elevation
        or east_height != surface_elevation
        or south_height != surface_elevation
        or west_height != surface_elevation)
    var south_drop: bool = surface_elevation > south_height
    var cluster_value: float = (
        cluster_value_override if cluster_value_override >= 0.0
        else _cluster_value(world_pos, seed))
    var cluster_multiplier: float = lerpf(
        1.0, clampf((cluster_value - 0.24) * 2.55, 0.0, 1.75),
        clampf(clustering_strength, 0.0, 1.0))

    var total_density: float = 0.0
    for definition_index in indices_by_material[terrain_id]:
        var definition: Dictionary = definitions[int(definition_index)]
        total_density += _eligible_density(
            definition, ground_elevation, near_water, near_cliff, south_drop,
            global_density, cluster_multiplier)
    total_density = minf(total_density, 0.95)
    if placement_roll >= total_density:
        return EMPTY

    var selection_roll: float = _hash_unit(
        world_pos.x, world_pos.y, seed, 12011) * total_density
    var accumulated: float = 0.0
    for definition_index in indices_by_material[terrain_id]:
        var definition: Dictionary = definitions[int(definition_index)]
        accumulated += _eligible_density(
            definition, ground_elevation, near_water, near_cliff, south_drop,
            global_density, cluster_multiplier)
        if selection_roll < accumulated:
            var decoration_id: int = int(definition["id"])
            var variant: int = posmod(
                _hash_int(world_pos.x, world_pos.y, seed, decoration_id * 313 + 71),
                maxi(1, int(definition.get("variants", 1))))
            return Vector2i(decoration_id, variant)
    return EMPTY


static func _eligible_density(
        definition: Dictionary,
        ground_elevation: int,
        near_water: bool,
        near_cliff: bool,
        south_drop: bool,
        global_density: float,
        cluster_multiplier: float) -> float:
    if ground_elevation < int(definition.get("min_elevation", 0)):
        return 0.0
    if ground_elevation > int(definition.get("max_elevation", 3)):
        return 0.0
    var water_proximity: Variant = definition.get("water_proximity", "any")
    if water_proximity == "required" and not near_water:
        return 0.0
    if water_proximity == "forbidden" and near_water:
        return 0.0
    var cliff_proximity: Variant = definition.get("cliff_proximity", "any")
    if cliff_proximity == "required" and not near_cliff:
        return 0.0
    if bool(definition.get("avoid_cliff_edge", false)) and near_cliff:
        return 0.0
    if bool(definition.get("avoid_south_drop", false)) and south_drop:
        return 0.0
    var elevation_falloff: float = float(definition.get("elevation_falloff", 0.0))
    return minf(
        float(definition["density"]) * maxf(0.0, global_density)
            * cluster_multiplier / ANCHOR_FRACTION
            * maxf(0.0, 1.0 - elevation_falloff * ground_elevation),
        0.80)


static func is_candidate_anchor(world_pos: Vector2i, seed: int) -> bool:
    return (_hash_int(world_pos.x, world_pos.y, seed, 7919) & 7) == 0


static func build_cluster_cache(
        world_origin: Vector2i, side_length: int, seed: int) -> Dictionary:
    var coarse_origin := Vector2i(
        floori(float(world_origin.x) / CLUSTER_SIZE),
        floori(float(world_origin.y) / CLUSTER_SIZE))
    var coarse_end := Vector2i(
        floori(float(world_origin.x + side_length - 1) / CLUSTER_SIZE) + 1,
        floori(float(world_origin.y + side_length - 1) / CLUSTER_SIZE) + 1)
    var width: int = coarse_end.x - coarse_origin.x + 1
    var height: int = coarse_end.y - coarse_origin.y + 1
    var values := PackedFloat64Array()
    values.resize(width * height)
    for y in range(height):
        for x in range(width):
            values[y * width + x] = _hash_unit(
                coarse_origin.x + x, coarse_origin.y + y, seed, 4049)
    return {"origin": coarse_origin, "width": width, "values": values}


static func cluster_value_from_cache(
        world_pos: Vector2i, cache: Dictionary) -> float:
    var coarse_origin: Vector2i = cache["origin"]
    var width: int = int(cache["width"])
    var values: PackedFloat64Array = cache["values"]
    var cell_x: int = floori(float(world_pos.x) / CLUSTER_SIZE)
    var cell_y: int = floori(float(world_pos.y) / CLUSTER_SIZE)
    var cache_x: int = cell_x - coarse_origin.x
    var cache_y: int = cell_y - coarse_origin.y
    var local_x: float = posmod(world_pos.x, CLUSTER_SIZE) / float(CLUSTER_SIZE)
    var local_y: float = posmod(world_pos.y, CLUSTER_SIZE) / float(CLUSTER_SIZE)
    var smooth_x: float = local_x * local_x * (3.0 - 2.0 * local_x)
    var smooth_y: float = local_y * local_y * (3.0 - 2.0 * local_y)
    var top: float = lerpf(
        values[cache_y * width + cache_x],
        values[cache_y * width + cache_x + 1], smooth_x)
    var bottom: float = lerpf(
        values[(cache_y + 1) * width + cache_x],
        values[(cache_y + 1) * width + cache_x + 1], smooth_x)
    return lerpf(top, bottom, smooth_y)


static func _cluster_value(world_pos: Vector2i, seed: int) -> float:
    var cell_x: int = floori(float(world_pos.x) / CLUSTER_SIZE)
    var cell_y: int = floori(float(world_pos.y) / CLUSTER_SIZE)
    var local_x: float = posmod(world_pos.x, CLUSTER_SIZE) / float(CLUSTER_SIZE)
    var local_y: float = posmod(world_pos.y, CLUSTER_SIZE) / float(CLUSTER_SIZE)
    var smooth_x: float = local_x * local_x * (3.0 - 2.0 * local_x)
    var smooth_y: float = local_y * local_y * (3.0 - 2.0 * local_y)
    var top: float = lerpf(
        _hash_unit(cell_x, cell_y, seed, 4049),
        _hash_unit(cell_x + 1, cell_y, seed, 4049), smooth_x)
    var bottom: float = lerpf(
        _hash_unit(cell_x, cell_y + 1, seed, 4049),
        _hash_unit(cell_x + 1, cell_y + 1, seed, 4049), smooth_x)
    return lerpf(top, bottom, smooth_y)


static func _hash_unit(x: int, y: int, seed: int, salt: int) -> float:
    return float(_hash_int(x, y, seed, salt) & 0x00ffffff) / 16777216.0


static func _hash_int(x: int, y: int, seed: int, salt: int) -> int:
    var value: int = x * 0x1f123bb5 ^ y * 0x5f356495 ^ seed * 0x2c1b3c6d ^ salt
    value = (value ^ (value >> 16)) * 0x45d9f3b
    value = (value ^ (value >> 16)) * 0x45d9f3b
    return value ^ (value >> 16)

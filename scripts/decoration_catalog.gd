extends RefCounted
## Data-only registry for presentation decorations. IDs are stable atlas keys;
## placement is derived from authoritative terrain and never stored in the
## mutable TerrainWorld override dictionaries.

const DEFINITIONS = [
    {
        "id": 0, "name": "Grass Tuft", "kind": "tuft", "materials": [3],
        "min_elevation": 0, "max_elevation": 3, "density": 0.105,
        "variants": 4, "scale": 1.0, "visual_offset": Vector2i(0, 7),
        "avoid_south_drop": true, "elevation_falloff": 0.16,
    },
    {
        "id": 1, "name": "Tiny Wildflowers", "kind": "flower", "materials": [3],
        "min_elevation": 0, "max_elevation": 2, "density": 0.036,
        "variants": 4, "scale": 1.0, "visual_offset": Vector2i(0, 7),
        "avoid_south_drop": true, "elevation_falloff": 0.22,
    },
    {
        "id": 2, "name": "Low Shrub", "kind": "shrub", "materials": [3],
        "min_elevation": 0, "max_elevation": 2, "density": 0.014,
        "variants": 3, "scale": 0.9, "visual_offset": Vector2i(0, 6),
        "avoid_cliff_edge": true, "elevation_falloff": 0.28,
    },
    {
        "id": 3, "name": "Dirt Stones", "kind": "pebbles", "materials": [2],
        "min_elevation": 0, "max_elevation": 3, "density": 0.070,
        "variants": 4, "scale": 1.0, "visual_offset": Vector2i(0, 8),
    },
    {
        "id": 4, "name": "Dry Sprig", "kind": "dry_grass", "materials": [1, 2],
        "min_elevation": 0, "max_elevation": 2, "density": 0.024,
        "variants": 3, "scale": 0.9, "visual_offset": Vector2i(0, 7),
        "avoid_south_drop": true,
    },
    {
        "id": 5, "name": "Sand Pebbles", "kind": "sand_pebbles", "materials": [1],
        "min_elevation": 0, "max_elevation": 1, "density": 0.050,
        "variants": 4, "scale": 1.0, "visual_offset": Vector2i(0, 8),
    },
    {
        "id": 6, "name": "Rock Fragments", "kind": "rock", "materials": [4],
        "min_elevation": 0, "max_elevation": 3, "density": 0.095,
        "variants": 4, "scale": 1.0, "visual_offset": Vector2i(0, 7),
    },
    {
        "id": 7, "name": "Stone Flecks", "kind": "stone_detail", "materials": [4],
        "min_elevation": 0, "max_elevation": 3, "density": 0.045,
        "variants": 4, "scale": 0.85, "visual_offset": Vector2i(0, 8),
    },
    {
        "id": 8, "name": "Snow Drift", "kind": "drift", "materials": [5],
        "min_elevation": 1, "max_elevation": 3, "density": 0.055,
        "variants": 4, "scale": 1.0, "visual_offset": Vector2i(0, 8),
    },
    {
        "id": 9, "name": "Exposed Snow Stone", "kind": "snow_stone", "materials": [5],
        "min_elevation": 1, "max_elevation": 3, "density": 0.025,
        "variants": 3, "scale": 0.9, "visual_offset": Vector2i(0, 7),
    },
    {
        "id": 10, "name": "Wet Vegetation", "kind": "wet_grass", "materials": [6],
        "min_elevation": 0, "max_elevation": 1, "density": 0.055,
        "variants": 4, "scale": 1.0, "visual_offset": Vector2i(0, 7),
        "avoid_south_drop": true,
    },
    {
        "id": 11, "name": "Shore Reeds", "kind": "reeds", "materials": [3, 6],
        "min_elevation": 0, "max_elevation": 1, "density": 0.120,
        "variants": 4, "scale": 1.0, "visual_offset": Vector2i(0, 5),
        "water_proximity": "required", "avoid_south_drop": true,
    },
    {
        "id": 12, "name": "Gravel Pebbles", "kind": "gravel", "materials": [7],
        "min_elevation": 0, "max_elevation": 3, "density": 0.100,
        "variants": 4, "scale": 1.0, "visual_offset": Vector2i(0, 8),
    },
    {
        "id": 13, "name": "Gravel Debris", "kind": "debris", "materials": [7],
        "min_elevation": 0, "max_elevation": 3, "density": 0.032,
        "variants": 4, "scale": 0.9, "visual_offset": Vector2i(0, 7),
    },
    {
        "id": 14, "name": "Cliff-top Tuft", "kind": "cliff_tuft", "materials": [2, 3],
        "min_elevation": 1, "max_elevation": 3, "density": 0.050,
        "variants": 4, "scale": 0.9, "visual_offset": Vector2i(0, 6),
        "cliff_proximity": "required", "avoid_south_drop": true,
        "elevation_falloff": 0.12,
    },
]


static func build_indices_by_material() -> Dictionary:
    var result: Dictionary = {}
    for definition_index in range(DEFINITIONS.size()):
        var definition: Dictionary = DEFINITIONS[definition_index]
        for terrain_id in definition["materials"]:
            if not result.has(int(terrain_id)):
                result[int(terrain_id)] = []
            result[int(terrain_id)].append(definition_index)
    return result


static func build_max_density_by_material() -> Dictionary:
    var result: Dictionary = {}
    for definition in DEFINITIONS:
        for terrain_id in definition["materials"]:
            var material_id: int = int(terrain_id)
            result[material_id] = (
                float(result.get(material_id, 0.0))
                + float(definition["density"]))
    return result

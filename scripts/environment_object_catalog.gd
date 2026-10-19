extends RefCounted
## Data-only registry for large presentation objects. Stable IDs are atlas
## keys; mutable terrain and persistence remain owned by TerrainWorld.

const DEFINITIONS = [
    {
        "id": 0, "name": "Small Deciduous Tree", "category": "trees", "kind": "deciduous_small",
        "materials": [3], "min_elevation": 0, "max_elevation": 2, "density": 0.018,
        "variants": 4, "visual_size": Vector2i(56, 70), "root_anchor": Vector2i(48, 88),
        "procedural_kind": "tree", "procedural_archetype": "deciduous",
        "procedural_terrain_tag": "GRASS", "procedural_size": 30,
        "procedural_size_tier": "small", "procedural_scale": 2.0,
        "resource_category": "wood", "future_yield": 5, "harvestable": true,
        "collectable": false, "supports_depletion": true,
        "resource_id_strategy": "world_seed_anchor_definition",
        "footprint": [Vector2i.ZERO], "exclusion_radius": 2, "render_sort_bias": 0,
        "cluster_threshold": 0.42, "cluster_strength": 1.25, "avoid_dropoffs": true,
        "future_collision_footprint": [Vector2i.ZERO],
    },
    {
        "id": 1, "name": "Large Deciduous Tree", "category": "trees", "kind": "deciduous_large",
        "materials": [3], "min_elevation": 0, "max_elevation": 2, "density": 0.008,
        "variants": 3, "visual_size": Vector2i(76, 90), "root_anchor": Vector2i(48, 90),
        "procedural_kind": "tree", "procedural_archetype": "deciduous",
        "procedural_terrain_tag": "GRASS", "procedural_size": 36,
        "procedural_size_tier": "large", "procedural_scale": 2.0,
        "resource_category": "wood", "future_yield": 10, "harvestable": true,
        "collectable": false, "supports_depletion": true,
        "resource_id_strategy": "world_seed_anchor_definition",
        "footprint": [Vector2i.ZERO, Vector2i.LEFT], "exclusion_radius": 3, "render_sort_bias": 1,
        "cluster_threshold": 0.50, "cluster_strength": 1.4, "avoid_dropoffs": true,
        "future_collision_footprint": [Vector2i.ZERO, Vector2i.LEFT],
    },
    {
        "id": 2, "name": "Coniferous Tree", "category": "trees", "kind": "conifer",
        "materials": [3, 5], "min_elevation": 1, "max_elevation": 3, "density": 0.020,
        "variants": 4, "visual_size": Vector2i(52, 86), "root_anchor": Vector2i(48, 90),
        "procedural_kind": "tree", "procedural_archetype": "conifer",
        "procedural_terrain_tag": "DARK_DIRT", "procedural_size": 34,
        "procedural_size_tier": "large", "procedural_scale": 2.0,
        "resource_category": "wood", "future_yield": 9, "harvestable": true,
        "collectable": false, "supports_depletion": true,
        "resource_id_strategy": "world_seed_anchor_definition",
        "footprint": [Vector2i.ZERO], "exclusion_radius": 2, "render_sort_bias": 0,
        "cluster_threshold": 0.38, "cluster_strength": 1.35, "avoid_dropoffs": true,
        "future_collision_footprint": [Vector2i.ZERO],
    },
    {
        "id": 3, "name": "Dead Tree", "category": "trees", "kind": "dead_tree",
        "materials": [2, 3, 7], "min_elevation": 0, "max_elevation": 3, "density": 0.004,
        "variants": 3, "visual_size": Vector2i(48, 76), "root_anchor": Vector2i(48, 89),
        "procedural_kind": "tree", "procedural_archetype": "dead",
        "procedural_terrain_tag": "DARK_DIRT", "procedural_size": 34,
        "procedural_size_tier": "large", "procedural_scale": 2.0,
        "resource_category": "wood", "future_yield": 6, "harvestable": true,
        "collectable": false, "supports_depletion": true,
        "resource_id_strategy": "world_seed_anchor_definition",
        "footprint": [Vector2i.ZERO], "exclusion_radius": 2, "render_sort_bias": 0,
        "cluster_threshold": 0.20, "cluster_strength": 0.35, "avoid_dropoffs": true,
        "future_collision_footprint": [Vector2i.ZERO],
    },
    {
        "id": 4, "name": "Small Shrub", "category": "bushes", "kind": "shrub_small",
        "materials": [3], "min_elevation": 0, "max_elevation": 2, "density": 0.018,
        "variants": 4, "visual_size": Vector2i(36, 30), "root_anchor": Vector2i(48, 88),
        "procedural_kind": "berry_bush", "procedural_archetype": "rounded",
        "procedural_terrain_tag": "GRASS", "procedural_size": 24, "procedural_scale": 1.5,
        "resource_category": "food", "future_yield": 3, "harvestable": true,
        "collectable": false, "supports_depletion": true,
        "resource_id_strategy": "world_seed_anchor_definition",
        "supports_regrowth": true,
        "footprint": [Vector2i.ZERO], "exclusion_radius": 1, "render_sort_bias": -1,
        "cluster_threshold": 0.30, "cluster_strength": 0.85, "avoid_dropoffs": true,
        "future_collision_footprint": [],
    },
    {
        "id": 5, "name": "Leafy Bush", "category": "bushes", "kind": "bush_large",
        "materials": [3], "min_elevation": 0, "max_elevation": 2, "density": 0.010,
        "variants": 4, "visual_size": Vector2i(50, 38), "root_anchor": Vector2i(48, 89),
        "procedural_kind": "berry_bush", "procedural_archetype": "wide",
        "procedural_terrain_tag": "GRASS", "procedural_size": 28, "procedural_scale": 1.5,
        "resource_category": "food", "future_yield": 5, "harvestable": true,
        "collectable": false, "supports_depletion": true,
        "resource_id_strategy": "world_seed_anchor_definition",
        "supports_regrowth": true,
        "footprint": [Vector2i.ZERO], "exclusion_radius": 2, "render_sort_bias": 0,
        "cluster_threshold": 0.42, "cluster_strength": 1.0, "avoid_dropoffs": true,
        "future_collision_footprint": [Vector2i.ZERO],
    },
    {
        "id": 6, "name": "Dry Shrub", "category": "bushes", "kind": "shrub_dry",
        "materials": [1, 2, 7], "min_elevation": 0, "max_elevation": 2, "density": 0.010,
        "variants": 3, "visual_size": Vector2i(42, 34), "root_anchor": Vector2i(48, 89),
        "footprint": [Vector2i.ZERO], "exclusion_radius": 1, "render_sort_bias": 0,
        "cluster_threshold": 0.18, "cluster_strength": 0.45, "avoid_dropoffs": true,
        "future_collision_footprint": [],
    },
    {
        "id": 7, "name": "Shoreline Vegetation", "category": "bushes", "kind": "shore_bush",
        "materials": [3, 6], "min_elevation": 0, "max_elevation": 1, "density": 0.022,
        "variants": 4, "visual_size": Vector2i(48, 40), "root_anchor": Vector2i(48, 89),
        "procedural_kind": "berry_bush", "procedural_archetype": "upright",
        "procedural_terrain_tag": "MUD", "procedural_size": 26, "procedural_scale": 1.5,
        "resource_category": "food", "future_yield": 4, "harvestable": true,
        "collectable": false, "supports_depletion": true,
        "resource_id_strategy": "world_seed_anchor_definition",
        "supports_regrowth": true,
        "footprint": [Vector2i.ZERO], "exclusion_radius": 1, "render_sort_bias": 0,
        "water_proximity": "required", "cluster_threshold": 0.24, "cluster_strength": 0.8,
        "avoid_dropoffs": true, "future_collision_footprint": [],
    },
    {
        "id": 8, "name": "Small Boulder", "category": "rocks", "kind": "boulder_small",
        "materials": [2, 4, 7], "min_elevation": 0, "max_elevation": 3, "density": 0.016,
        "variants": 4, "visual_size": Vector2i(38, 30), "root_anchor": Vector2i(48, 88),
        "procedural_kind": "boulder", "procedural_archetype": "rounded",
        "procedural_terrain_tag": "STONE", "procedural_size": 18,
        "procedural_size_tier": "medium", "procedural_scale": 1.75,
        "resource_category": "stone", "future_yield": 4, "harvestable": false,
        "collectable": true, "supports_depletion": true,
        "resource_id_strategy": "world_seed_anchor_definition",
        "footprint": [Vector2i.ZERO], "exclusion_radius": 1, "render_sort_bias": 0,
        "cluster_threshold": 0.20, "cluster_strength": 0.65, "avoid_dropoffs": true,
        "future_collision_footprint": [Vector2i.ZERO],
    },
    {
        "id": 9, "name": "Large Boulder", "category": "rocks", "kind": "boulder_large",
        "materials": [4, 7], "min_elevation": 0, "max_elevation": 3, "density": 0.008,
        "variants": 4, "visual_size": Vector2i(60, 44), "root_anchor": Vector2i(48, 89),
        "procedural_kind": "boulder", "procedural_archetype": "tall",
        "procedural_terrain_tag": "STONE", "procedural_size": 24,
        "procedural_size_tier": "large", "procedural_scale": 1.75,
        "resource_category": "stone", "future_yield": 8, "harvestable": false,
        "collectable": true, "supports_depletion": true,
        "resource_id_strategy": "world_seed_anchor_definition",
        "footprint": [Vector2i.ZERO, Vector2i.LEFT], "exclusion_radius": 2, "render_sort_bias": 1,
        "cluster_threshold": 0.30, "cluster_strength": 0.85, "avoid_dropoffs": true,
        "future_collision_footprint": [Vector2i.ZERO, Vector2i.LEFT],
    },
    {
        "id": 10, "name": "Rocky Outcrop", "category": "rocks", "kind": "outcrop",
        "materials": [4, 7], "min_elevation": 1, "max_elevation": 3, "density": 0.006,
        "variants": 3, "visual_size": Vector2i(72, 54), "root_anchor": Vector2i(48, 90),
        "procedural_kind": "boulder", "procedural_archetype": "blocky",
        "procedural_terrain_tag": "STONE", "procedural_size": 27,
        "procedural_size_tier": "large", "procedural_scale": 1.75,
        "resource_category": "stone", "future_yield": 12, "harvestable": false,
        "collectable": true, "supports_depletion": true,
        "resource_id_strategy": "world_seed_anchor_definition",
        "footprint": [Vector2i.ZERO, Vector2i.LEFT, Vector2i.UP, Vector2i(-1, -1)],
        "exclusion_radius": 3, "render_sort_bias": 1, "cluster_threshold": 0.44,
        "cluster_strength": 1.0, "avoid_dropoffs": true,
        "future_collision_footprint": [Vector2i.ZERO, Vector2i.LEFT, Vector2i.UP, Vector2i(-1, -1)],
    },
    {
        "id": 11, "name": "Exposed Stone Group", "category": "rocks", "kind": "stone_group",
        "materials": [2, 4, 7], "min_elevation": 0, "max_elevation": 3, "density": 0.012,
        "variants": 4, "visual_size": Vector2i(48, 30), "root_anchor": Vector2i(48, 88),
        "procedural_kind": "boulder", "procedural_archetype": "flat",
        "procedural_terrain_tag": "GRAVEL", "procedural_size": 20,
        "procedural_size_tier": "medium", "procedural_scale": 1.75,
        "resource_category": "stone", "future_yield": 5, "harvestable": false,
        "collectable": true, "supports_depletion": true,
        "resource_id_strategy": "world_seed_anchor_definition",
        "footprint": [Vector2i.ZERO], "exclusion_radius": 1, "render_sort_bias": 0,
        "cluster_threshold": 0.20, "cluster_strength": 0.65, "avoid_dropoffs": true,
        "future_collision_footprint": [],
    },
    {
        "id": 12, "name": "Fallen Log", "category": "debris", "kind": "fallen_log",
        "materials": [2, 3], "min_elevation": 0, "max_elevation": 2, "density": 0.006,
        "variants": 4, "visual_size": Vector2i(62, 30), "root_anchor": Vector2i(48, 89),
        "footprint": [Vector2i.ZERO, Vector2i.LEFT], "exclusion_radius": 2, "render_sort_bias": 0,
        "cluster_threshold": 0.24, "cluster_strength": 0.5, "avoid_dropoffs": true,
        "future_collision_footprint": [Vector2i.ZERO, Vector2i.LEFT],
    },
    {
        "id": 13, "name": "Tree Stump", "category": "debris", "kind": "stump",
        "materials": [2, 3], "min_elevation": 0, "max_elevation": 2, "density": 0.007,
        "variants": 3, "visual_size": Vector2i(30, 30), "root_anchor": Vector2i(48, 88),
        "footprint": [Vector2i.ZERO], "exclusion_radius": 1, "render_sort_bias": 0,
        "cluster_threshold": 0.18, "cluster_strength": 0.4, "avoid_dropoffs": true,
        "future_collision_footprint": [Vector2i.ZERO],
    },
    {
        "id": 14, "name": "Deadwood", "category": "debris", "kind": "deadwood",
        "materials": [1, 2, 7], "min_elevation": 0, "max_elevation": 2, "density": 0.005,
        "variants": 3, "visual_size": Vector2i(52, 34), "root_anchor": Vector2i(48, 89),
        "footprint": [Vector2i.ZERO], "exclusion_radius": 2, "render_sort_bias": 0,
        "cluster_threshold": 0.16, "cluster_strength": 0.35, "avoid_dropoffs": true,
        "future_collision_footprint": [],
    },
]


static func build_indices_by_material() -> Dictionary:
    var result: Dictionary = {}
    for definition_index in range(DEFINITIONS.size()):
        for terrain_id in DEFINITIONS[definition_index]["materials"]:
            if not result.has(int(terrain_id)):
                result[int(terrain_id)] = []
            result[int(terrain_id)].append(definition_index)
    return result


static func build_max_density_by_material() -> Dictionary:
    var result: Dictionary = {}
    for definition in DEFINITIONS:
        for terrain_id in definition["materials"]:
            var material_id: int = int(terrain_id)
            result[material_id] = float(result.get(material_id, 0.0)) + float(definition["density"])
    return result


static func build_by_id() -> Dictionary:
    var result: Dictionary = {}
    for definition in DEFINITIONS:
        result[int(definition["id"])] = definition
    return result

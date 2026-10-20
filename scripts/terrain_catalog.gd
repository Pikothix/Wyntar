extends RefCounted
## Material IDs, priorities, physical rendering metadata, source art, and
## optional visual variants. TerrainWorld owns mutable cell data; this catalog
## only describes how a material participates in shared terrain rendering.
## Liquid entries additionally own their presentation profile; the renderer
## consumes it without making liquid classification or simulation decisions.
## A material without `variants` falls back to its single `texture_path`.

const MATERIALS = [
    {
        "id": 0, "name": "Water", "priority": 0, "texture_path": "res://art/water.png",
        "liquid": true,
        # The current single-material cell model has no separate seabed slot.
        # When edited ground rises above the liquid plane, presentation exposes
        # this compatible substrate without mutating the authoritative material.
        "exposed_ground_material_id": 1,
        "surface_style": "calm_water", "shoreline_style": "bright_ripple",
        "visual_calmness": 0.86, "variation_strength": 0.24,
        "variation_frequency_scale": 0.34,
        "liquid_surface_tint": "66aeca", "liquid_highlight_tint": "b8edf0",
        "liquid_pattern_frequency": 0.010, "liquid_shimmer_strength": 0.065,
        "liquid_motion_enabled": true, "liquid_motion_speed": 0.18,
        "water_ripple_strength": 0.32, "water_secondary_ripple_scale": 2.4,
        "water_ripple_drift_speed": 0.55, "water_glint_density": 0.14,
        "water_glint_brightness": 0.38,
        "shoreline_width": 0.16, "depth_effect_strength": 0.10,
        "emissive": false, "emissive_strength": 0.0,
        "variants": [
            {"texture_path": "res://art/water.png", "tint": "ffffff", "brightness": 1.00, "contrast": 1.00},
            {"texture_path": "res://art/water.png", "tint": "d8f2ff", "brightness": 1.04, "contrast": 0.98},
            {"texture_path": "res://art/water.png", "tint": "c7e4ff", "brightness": 0.94, "contrast": 1.04},
            {"texture_path": "res://art/water.png", "tint": "d4ffff", "brightness": 1.00, "contrast": 1.02},
        ],
    },
    {
        "id": 1, "name": "Sand", "priority": 10, "texture_path": "res://art/sand.png",
        "variation_strength": 0.28, "variation_frequency_scale": 0.44,
        "variants": [
            {"texture_path": "res://art/sand.png", "tint": "ffffff", "brightness": 1.00, "contrast": 1.00},
            {"texture_path": "res://art/sand.png", "tint": "fff3cf", "brightness": 1.03, "contrast": 0.97},
            {"texture_path": "res://art/sand.png", "tint": "f3dfbd", "brightness": 0.96, "contrast": 1.04},
            {"texture_path": "res://art/sand.png", "tint": "ffe8b5", "brightness": 1.00, "contrast": 1.02},
        ],
    },
    {
        "id": 2, "name": "Dirt", "priority": 20, "texture_path": "res://art/dirt.png",
        "variation_strength": 0.52, "variation_frequency_scale": 0.72,
        "variants": [
            {"texture_path": "res://art/dirt.png", "tint": "ffffff", "brightness": 1.00, "contrast": 1.00},
            {"texture_path": "res://art/dirt.png", "tint": "efd8c2", "brightness": 1.03, "contrast": 0.98},
            {"texture_path": "res://art/dirt.png", "tint": "d8c1b2", "brightness": 0.91, "contrast": 1.06},
            {"texture_path": "res://art/dirt.png", "tint": "f2ccb0", "brightness": 0.98, "contrast": 1.03},
        ],
    },
    {
        "id": 3, "name": "Grass", "priority": 30, "texture_path": "res://art/grass.png",
        "variation_strength": 0.64, "variation_frequency_scale": 0.58,
        "variants": [
            {"texture_path": "res://art/grass.png", "tint": "ffffff", "brightness": 1.00, "contrast": 1.00},
            {"texture_path": "res://art/grass.png", "tint": "e8f2c9", "brightness": 1.05, "contrast": 0.98},
            {"texture_path": "res://art/grass.png", "tint": "cce8d0", "brightness": 0.94, "contrast": 1.05},
            {"texture_path": "res://art/grass.png", "tint": "f0e7bd", "brightness": 1.00, "contrast": 1.02},
        ],
    },
    {
        "id": 4, "name": "Stone", "priority": 40, "texture_path": "res://art/stone.png",
        "variation_strength": 0.66, "variation_frequency_scale": 1.05,
        "variants": [
            {"texture_path": "res://art/stone.png", "tint": "ffffff", "brightness": 1.00, "contrast": 1.00},
            {"texture_path": "res://art/stone.png", "tint": "e3edf2", "brightness": 1.02, "contrast": 0.98},
            {"texture_path": "res://art/stone.png", "tint": "eadfd6", "brightness": 0.96, "contrast": 1.05},
            {"texture_path": "res://art/stone.png", "tint": "d7dce5", "brightness": 0.91, "contrast": 1.08},
        ],
    },
    {
        "id": 5, "name": "Snow", "priority": 50, "texture_path": "res://art/snow.png",
        "variation_strength": 0.18, "variation_frequency_scale": 0.30,
        "variants": [
            {"texture_path": "res://art/snow.png", "tint": "ffffff", "brightness": 1.00, "contrast": 1.00},
            {"texture_path": "res://art/snow.png", "tint": "eaf7ff", "brightness": 1.02, "contrast": 0.97},
            {"texture_path": "res://art/snow.png", "tint": "dcecff", "brightness": 0.96, "contrast": 1.03},
            {"texture_path": "res://art/snow.png", "tint": "f3f5ff", "brightness": 1.00, "contrast": 1.01},
        ],
    },
    {
        "id": 6, "name": "Mud", "priority": 25, "texture_path": "res://art/mud.png",
        "variation_strength": 0.48, "variation_frequency_scale": 0.78,
        "variants": [
            {"texture_path": "res://art/mud.png", "tint": "ffffff", "brightness": 1.00, "contrast": 1.00},
            {"texture_path": "res://art/mud.png", "tint": "e5d2b8", "brightness": 1.00, "contrast": 0.98},
            {"texture_path": "res://art/mud.png", "tint": "c9c5a8", "brightness": 0.91, "contrast": 1.06},
            {"texture_path": "res://art/mud.png", "tint": "e3bfa8", "brightness": 0.96, "contrast": 1.03},
        ],
    },
    {
        "id": 7, "name": "Gravel", "priority": 35, "texture_path": "res://art/gravel.png",
        "variation_strength": 0.70, "variation_frequency_scale": 1.18,
        "variants": [
            {"texture_path": "res://art/gravel.png", "tint": "ffffff", "brightness": 1.00, "contrast": 1.00},
            {"texture_path": "res://art/gravel.png", "tint": "e8e1d6", "brightness": 1.02, "contrast": 0.98},
            {"texture_path": "res://art/gravel.png", "tint": "d6e0e5", "brightness": 0.95, "contrast": 1.05},
            {"texture_path": "res://art/gravel.png", "tint": "dfcfbf", "brightness": 0.92, "contrast": 1.08},
        ],
    },
]

const DEFAULT_MATERIAL_ID: int = 3 # Grass


static func is_liquid(terrain_id: int) -> bool:
    for material in MATERIALS:
        if int(material["id"]) == terrain_id:
            return bool(material.get("liquid", false))
    return false


static func material_name(terrain_id: int) -> String:
    for material in MATERIALS:
        if int(material["id"]) == terrain_id:
            return String(material["name"])
    return "Unknown"

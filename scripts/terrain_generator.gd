extends RefCounted
## Deterministically generates terrain IDs and base elevations from absolute
## world-cell coordinates. Player edits are owned by TerrainWorld.

const Catalog = preload("res://scripts/terrain_catalog.gd")

var world_seed: int = 84521
var biome_frequency: float = 0.012
var detail_frequency: float = 0.055
var include_origin_demo: bool = true
var procedural_elevation_enabled: bool = true
var max_generated_elevation: int = 3
var elevation_frequency: float = 0.006
var elevation_detail_frequency: float = 0.021
var elevation_detail_strength: float = 0.14
var elevation_threshold_1: float = -0.12
var elevation_threshold_2: float = 0.16
var elevation_threshold_3: float = 0.43
var elevation_flatness_bias: float = 0.02

var _material_elevation := FastNoiseLite.new()
var _moisture := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _demo_noise := FastNoiseLite.new()
var _height_region := FastNoiseLite.new()
var _height_detail := FastNoiseLite.new()


func configure(seed_value: int, biome_frequency_value: float, detail_frequency_value: float, include_demo: bool) -> void:
    world_seed = seed_value
    biome_frequency = biome_frequency_value
    detail_frequency = detail_frequency_value
    include_origin_demo = include_demo

    _configure_noise(_material_elevation, world_seed, biome_frequency, 4)
    _configure_noise(_moisture, world_seed + 1013, biome_frequency * 0.73, 3)
    _configure_noise(_detail, world_seed + 2029, detail_frequency, 2)
    _demo_noise.seed = 3451
    _demo_noise.frequency = 0.12


func configure_elevation(
        enabled: bool, maximum_elevation: int, regional_frequency: float,
        local_detail_frequency: float, local_detail_strength: float,
        threshold_1: float, threshold_2: float, threshold_3: float,
        flatness_bias: float) -> void:
    procedural_elevation_enabled = enabled
    max_generated_elevation = clampi(maximum_elevation, 0, 3)
    elevation_frequency = maxf(regional_frequency, 0.00001)
    elevation_detail_frequency = maxf(local_detail_frequency, 0.00001)
    elevation_detail_strength = clampf(local_detail_strength, 0.0, 1.0)
    elevation_threshold_1 = threshold_1
    elevation_threshold_2 = maxf(threshold_2, threshold_1 + 0.001)
    elevation_threshold_3 = maxf(threshold_3, elevation_threshold_2 + 0.001)
    elevation_flatness_bias = flatness_bias

    _configure_noise(_height_region, world_seed + 19992, elevation_frequency, 3)
    _configure_noise(_height_detail, world_seed + 39989, elevation_detail_frequency, 2)


func get_cell(world_pos: Vector2i) -> int:
    if include_origin_demo and world_pos.x >= -22 and world_pos.x <= 22 and world_pos.y >= -12 and world_pos.y <= 12:
        return _get_demo_cell(world_pos.x, world_pos.y)

    var x: float = float(world_pos.x)
    var y: float = float(world_pos.y)
    var elevation: float = _material_elevation.get_noise_2d(x, y)
    var moisture: float = _moisture.get_noise_2d(x, y)
    var detail: float = _detail.get_noise_2d(x, y)

    if elevation < -0.42:
        return 0 # Water
    if elevation < -0.27:
        return 1 # Sand
    if elevation > 0.58:
        return 5 # Snow
    if elevation > 0.38:
        return 4 # Stone
    if moisture > 0.46 and elevation < 0.12:
        return 6 # Mud
    if detail > 0.48:
        return 7 # Gravel
    if moisture < -0.28:
        return 2 # Dirt
    return Catalog.DEFAULT_MATERIAL_ID # Grass


func get_elevation(world_pos: Vector2i) -> int:
    if not procedural_elevation_enabled or max_generated_elevation <= 0:
        return 0

    # Low-frequency regional noise defines broad landforms. A deliberately
    # small detail contribution softens regular contours without producing
    # isolated one-cell columns or holes. Integer thresholds form plateaus.
    var x: float = float(world_pos.x)
    var y: float = float(world_pos.y)
    var height_signal: float = (
        _height_region.get_noise_2d(x, y)
        + _height_detail.get_noise_2d(x, y) * elevation_detail_strength
        - elevation_flatness_bias)
    var generated_height: int = 0
    if height_signal >= elevation_threshold_1:
        generated_height = 1
    if height_signal >= elevation_threshold_2:
        generated_height = 2
    if height_signal >= elevation_threshold_3:
        generated_height = 3
    return mini(generated_height, max_generated_elevation)


func _configure_noise(noise: FastNoiseLite, seed_value: int, frequency: float, octaves: int) -> void:
    noise.seed = seed_value
    noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
    noise.frequency = frequency
    noise.fractal_type = FastNoiseLite.FRACTAL_FBM
    noise.fractal_octaves = octaves
    noise.fractal_gain = 0.5
    noise.fractal_lacunarity = 2.0


func _get_demo_cell(x: int, y: int) -> int:
    var warp: float = _demo_noise.get_noise_2d(float(x), float(y)) * 3.8
    var lake: float = Vector2(float(x + 11), float(y + 2)).length() + warp
    if lake < 4.8:
        return 0
    if lake < 7.5:
        return 1

    var hill: float = Vector2(float(x - 7), float(y + 3)).length() + warp * 0.65
    if hill < 3.2:
        return 5
    if hill < 5.8:
        return 4
    if hill < 8.3:
        return 2

    var mud: float = Vector2(float(x - 12), float(y - 8)).length() + warp
    if mud < 5.4:
        return 6
    if mud < 7.3:
        return 7
    return Catalog.DEFAULT_MATERIAL_ID

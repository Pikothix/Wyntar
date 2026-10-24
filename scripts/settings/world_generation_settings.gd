extends RefCounted
## Typed pre-ready snapshot of procedural world and elevation configuration.
## Main's legacy exports remain the serialized compatibility source.

var world_seed: int
var biome_frequency: float
var detail_frequency: float
var include_origin_demo: bool
var procedural_elevation_enabled: bool
var max_generated_elevation: int
var elevation_frequency: float
var elevation_detail_frequency: float
var elevation_detail_strength: float
var elevation_threshold_1: float
var elevation_threshold_2: float
var elevation_threshold_3: float
var elevation_flatness_bias: float
var sea_level: int


static func capture(source):
	var settings = new()
	settings.world_seed = source.world_seed
	settings.biome_frequency = source.biome_frequency
	settings.detail_frequency = source.detail_frequency
	settings.include_origin_demo = source.include_origin_demo
	settings.procedural_elevation_enabled = source.procedural_elevation_enabled
	settings.max_generated_elevation = source.max_generated_elevation
	settings.elevation_frequency = source.elevation_frequency
	settings.elevation_detail_frequency = source.elevation_detail_frequency
	settings.elevation_detail_strength = source.elevation_detail_strength
	settings.elevation_threshold_1 = source.elevation_threshold_1
	settings.elevation_threshold_2 = source.elevation_threshold_2
	settings.elevation_threshold_3 = source.elevation_threshold_3
	settings.elevation_flatness_bias = source.elevation_flatness_bias
	settings.sea_level = source.sea_level
	return settings


func apply_to(renderer) -> void:
	renderer.world_seed = world_seed
	renderer.biome_frequency = biome_frequency
	renderer.detail_frequency = detail_frequency
	renderer.include_origin_demo = include_origin_demo
	renderer.procedural_elevation_enabled = procedural_elevation_enabled
	renderer.max_generated_elevation = max_generated_elevation
	renderer.elevation_frequency = elevation_frequency
	renderer.elevation_detail_frequency = elevation_detail_frequency
	renderer.elevation_detail_strength = elevation_detail_strength
	renderer.elevation_threshold_1 = elevation_threshold_1
	renderer.elevation_threshold_2 = elevation_threshold_2
	renderer.elevation_threshold_3 = elevation_threshold_3
	renderer.elevation_flatness_bias = elevation_flatness_bias
	renderer.sea_level = sea_level

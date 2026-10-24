extends RefCounted
## Complete typed pre-ready renderer configuration assembled from Main's
## compatibility exports. Startup and replacement both use this single path.

const WorldGenerationSettings = preload("res://scripts/settings/world_generation_settings.gd")
const ChunkStreamingSettings = preload("res://scripts/settings/chunk_streaming_settings.gd")
const TerrainRenderingSettings = preload("res://scripts/settings/terrain_rendering_settings.gd")
const WaterRenderingSettings = preload("res://scripts/settings/water_rendering_settings.gd")
const CliffRenderingSettings = preload("res://scripts/settings/cliff_rendering_settings.gd")
const EnvironmentRenderingSettings = preload("res://scripts/settings/environment_rendering_settings.gd")

var world_generation: WorldGenerationSettings
var chunk_streaming: ChunkStreamingSettings
var terrain_rendering: TerrainRenderingSettings
var water_rendering: WaterRenderingSettings
var cliff_rendering: CliffRenderingSettings
var environment_rendering: EnvironmentRenderingSettings


static func capture(source):
	var configuration = new()
	configuration.world_generation = WorldGenerationSettings.capture(source)
	configuration.chunk_streaming = ChunkStreamingSettings.capture(source)
	configuration.terrain_rendering = TerrainRenderingSettings.capture(source)
	configuration.water_rendering = WaterRenderingSettings.capture(source)
	configuration.cliff_rendering = CliffRenderingSettings.capture(source)
	configuration.environment_rendering = EnvironmentRenderingSettings.capture(source)
	return configuration


func apply_to(renderer) -> void:
	world_generation.apply_to(renderer)
	chunk_streaming.apply_to(renderer)
	terrain_rendering.apply_to(renderer)
	water_rendering.apply_to(renderer)
	cliff_rendering.apply_to(renderer)
	environment_rendering.apply_to(renderer)

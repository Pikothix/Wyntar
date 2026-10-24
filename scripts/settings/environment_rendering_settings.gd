extends RefCounted
## Typed pre-ready snapshot of decoration, environment-object and resource timing settings.

var decorations_enabled: bool
var decoration_density: float
var decoration_clustering_strength: float
var decoration_seed_offset: int
var environment_objects_enabled: bool
var procedural_vegetation_enabled: bool
var environment_object_density: float
var environment_object_seed_offset: int
var berry_regrowth_seconds: float


static func capture(source):
	var settings = new()
	settings.decorations_enabled = source.decorations_enabled
	settings.decoration_density = source.decoration_density
	settings.decoration_clustering_strength = source.decoration_clustering_strength
	settings.decoration_seed_offset = source.decoration_seed_offset
	settings.environment_objects_enabled = source.environment_objects_enabled
	settings.procedural_vegetation_enabled = source.procedural_vegetation_enabled
	settings.environment_object_density = source.environment_object_density
	settings.environment_object_seed_offset = source.environment_object_seed_offset
	settings.berry_regrowth_seconds = source.berry_regrowth_seconds
	return settings


func apply_to(renderer) -> void:
	renderer.decorations_enabled = decorations_enabled
	renderer.decoration_density = decoration_density
	renderer.decoration_clustering_strength = decoration_clustering_strength
	renderer.decoration_seed_offset = decoration_seed_offset
	renderer.environment_objects_enabled = environment_objects_enabled
	renderer.procedural_vegetation_enabled = procedural_vegetation_enabled
	renderer.environment_object_density = environment_object_density
	renderer.environment_object_seed_offset = environment_object_seed_offset
	renderer.berry_regrowth_seconds = berry_regrowth_seconds

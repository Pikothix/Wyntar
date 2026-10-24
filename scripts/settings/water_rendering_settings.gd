extends RefCounted
## Typed pre-ready snapshot of water repetition and experimental enhancement settings.

var repetition_correction_enabled: bool
var repetition_correction_strength: float
var enhancement_enabled: bool
var ripple_strength: float
var secondary_ripple_scale: float
var ripple_drift_speed: float
var glint_density: float
var glint_brightness: float


static func capture(source):
	var settings = new()
	settings.repetition_correction_enabled = source.water_repetition_correction_enabled
	settings.repetition_correction_strength = clampf(
		source.water_repetition_correction_strength, 0.0, 1.0)
	settings.enhancement_enabled = source.experimental_water_enhancement_enabled
	settings.ripple_strength = clampf(source.water_ripple_strength, 0.0, 1.0)
	settings.secondary_ripple_scale = clampf(source.water_secondary_ripple_scale, 0.5, 6.0)
	settings.ripple_drift_speed = clampf(source.water_ripple_drift_speed, 0.0, 2.0)
	settings.glint_density = clampf(source.water_glint_density, 0.0, 1.0)
	settings.glint_brightness = clampf(source.water_glint_brightness, 0.0, 1.0)
	return settings


func apply_to(renderer) -> void:
	renderer.water_repetition_correction_enabled = repetition_correction_enabled
	renderer.water_repetition_correction_strength = repetition_correction_strength
	renderer.experimental_water_enhancement_enabled = enhancement_enabled
	renderer.water_ripple_strength = ripple_strength
	renderer.water_secondary_ripple_scale = secondary_ripple_scale
	renderer.water_ripple_drift_speed = ripple_drift_speed
	renderer.water_glint_density = glint_density
	renderer.water_glint_brightness = glint_brightness

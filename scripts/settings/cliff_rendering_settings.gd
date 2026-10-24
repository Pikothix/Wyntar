extends RefCounted
## Typed pre-ready snapshot of cliff rendering and experimental geometry switches.

var repetition_correction_enabled: bool
var repetition_correction_strength: float
var procedural_materials_enabled: bool
var shader_lod_enabled: bool
var shader_lod_min_zoom: float
var shader_lod_full_detail_zoom: float
var shader_lod_min_detail: float
var organic_geometry_enabled: bool
var unified_components_enabled: bool
var refined_silhouettes_enabled: bool
var connected_contours_enabled: bool
var unified_contours_enabled: bool
var grid_aligned_rim_enabled: bool
var legacy_coverage_repair_enabled: bool
var legacy_sidewall_occlusion_repair_enabled: bool
var rendering_mode: int
var directional_projection_enabled: bool
var height_profile: int
var edge_overlays_visible: bool
var shadows_visible: bool


static func capture(source):
	var settings = new()
	settings.repetition_correction_enabled = source.cliff_repetition_correction_enabled
	settings.repetition_correction_strength = clampf(
		source.cliff_repetition_correction_strength, 0.0, 1.0)
	settings.procedural_materials_enabled = source.procedural_cliff_materials_enabled
	settings.shader_lod_enabled = source.cliff_shader_lod_enabled
	settings.shader_lod_min_zoom = maxf(source.cliff_shader_lod_min_zoom, 0.001)
	settings.shader_lod_full_detail_zoom = maxf(
		source.cliff_shader_lod_full_detail_zoom,
		settings.shader_lod_min_zoom + 0.001)
	settings.shader_lod_min_detail = clampf(source.cliff_shader_lod_min_detail, 0.0, 1.0)
	settings.organic_geometry_enabled = source.organic_cliff_geometry_enabled
	settings.unified_components_enabled = source.unified_cliff_components_enabled
	settings.refined_silhouettes_enabled = source.refined_cliff_silhouettes_enabled
	settings.connected_contours_enabled = source.connected_cliff_contours_enabled
	settings.unified_contours_enabled = source.unified_cliff_contours_enabled
	settings.grid_aligned_rim_enabled = source.grid_aligned_cliff_rim_enabled
	settings.legacy_coverage_repair_enabled = source.legacy_cliff_coverage_repair_enabled
	settings.legacy_sidewall_occlusion_repair_enabled = \
		source.legacy_cliff_sidewall_occlusion_repair_enabled
	settings.rendering_mode = source.cliff_rendering_mode
	settings.directional_projection_enabled = source.directional_cliff_projection_enabled
	settings.height_profile = source.cliff_height_profile
	settings.edge_overlays_visible = source.cliff_edge_overlays_visible
	settings.shadows_visible = source.cliff_shadows_visible
	return settings


func apply_to(renderer) -> void:
	renderer.cliff_repetition_correction_enabled = repetition_correction_enabled
	renderer.cliff_repetition_correction_strength = repetition_correction_strength
	renderer.procedural_cliff_materials_enabled = procedural_materials_enabled
	renderer.cliff_shader_lod_enabled = shader_lod_enabled
	renderer.cliff_shader_lod_min_zoom = shader_lod_min_zoom
	renderer.cliff_shader_lod_full_detail_zoom = shader_lod_full_detail_zoom
	renderer.cliff_shader_lod_min_detail = shader_lod_min_detail
	renderer.organic_cliff_geometry_enabled = organic_geometry_enabled
	renderer.unified_cliff_components_enabled = unified_components_enabled
	renderer.refined_cliff_silhouettes_enabled = refined_silhouettes_enabled
	renderer.connected_cliff_contours_enabled = connected_contours_enabled
	renderer.unified_cliff_contours_enabled = unified_contours_enabled
	renderer.grid_aligned_cliff_rim_enabled = grid_aligned_rim_enabled
	renderer.legacy_cliff_coverage_repair_enabled = legacy_coverage_repair_enabled
	renderer.legacy_cliff_sidewall_occlusion_repair_enabled = \
		legacy_sidewall_occlusion_repair_enabled
	renderer.cliff_rendering_mode = rendering_mode
	renderer.directional_cliff_projection_enabled = directional_projection_enabled
	renderer.cliff_height_profile = height_profile
	renderer.cliff_edge_overlays_visible = edge_overlays_visible
	renderer.cliff_shadows_visible = shadows_visible

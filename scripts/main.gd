extends Node2D
## Coordinates demo input, camera navigation, painting requests, and the screen-space HUD.
## TerrainRenderer streams visuals; its TerrainWorld remains gameplay authority.

const Catalog = preload("res://scripts/terrain_catalog.gd")
const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")
const CursorOverlay = preload("res://scripts/cursor_overlay.gd")
const WorldEditorController = preload("res://scripts/world_editor_controller.gd")
const ResourceInteractionController = preload("res://scripts/resource_interaction_controller.gd")
const WorldSaveService = preload("res://scripts/world_save_service.gd")
const CameraController = preload("res://scripts/camera_controller.gd")
const TerrainRendererConfiguration = preload(
	"res://scripts/settings/terrain_renderer_configuration.gd")

@export_group("World Generation")
@export var world_seed: int = 84521
@export_range(0.002, 0.1, 0.001) var biome_frequency: float = 0.012
@export_range(0.005, 0.2, 0.001) var detail_frequency: float = 0.055
@export var include_origin_demo: bool = true
@export var include_elevation_demo: bool = false

@export_group("Procedural Elevation")
@export var procedural_elevation_enabled: bool = true
@export_range(0, 3, 1) var max_generated_elevation: int = 3
@export_range(0.001, 0.03, 0.001) var elevation_frequency: float = 0.006
@export_range(0.002, 0.08, 0.001) var elevation_detail_frequency: float = 0.021
@export_range(0.0, 0.5, 0.01) var elevation_detail_strength: float = 0.14
@export_range(-1.0, 1.0, 0.01) var elevation_threshold_1: float = -0.12
@export_range(-1.0, 1.0, 0.01) var elevation_threshold_2: float = 0.16
@export_range(-1.0, 1.0, 0.01) var elevation_threshold_3: float = 0.43
@export_range(-0.25, 0.25, 0.01) var elevation_flatness_bias: float = 0.02
@export_range(0, 3, 1) var sea_level: int = 0

@export_group("Chunk Streaming")
@export_range(0, 4, 1) var load_margin_chunks: int = 1
@export_range(1, 6, 1) var unload_margin_chunks: int = 2
@export_range(1, 8, 1) var chunks_created_per_frame: int = 2
@export var chunk_profiling_enabled: bool = false
@export_range(0.25, 10.0, 0.25) var max_chunk_processing_ms: float = 2.5
@export_range(8, 256, 8) var chunk_work_quantum_cells: int = 24
@export_range(32, 1024, 32) var max_tile_cells_per_frame: int = 256

@export_group("Texture Variation")
@export var texture_variation_enabled: bool = true
@export_range(0.0, 1.0, 0.05) var texture_variation_strength: float = 0.65
@export_range(0.0002, 0.02, 0.0001) var texture_variation_frequency: float = 0.0025

@export_group("Clustered Grass Detail")
@export var clustered_grass_detail_enabled: bool = true
@export_range(0.0, 1.0, 0.01) var grass_clear_area_coverage: float = 0.70
@export_range(0.0, 1.0, 0.01) var grass_detail_density: float = 0.35
@export_range(0.0005, 0.02, 0.0005) var grass_cluster_scale: float = 0.004
@export_range(0.0, 0.4, 0.01) var grass_transition_softness: float = 0.12
@export_range(0.0, 1.0, 0.01) var grass_clear_area_residual_density: float = 0.04
@export var grass_detail_seed_offset: int = 48131

@export_group("Organic Grass Colour Variation")
@export var organic_grass_color_variation_enabled: bool = true
@export_range(0.0005, 0.01, 0.0005) var grass_broad_variation_scale: float = 0.0015
@export_range(0.0, 0.15, 0.005) var grass_color_variation_strength: float = 0.055
@export_range(0.0, 0.08, 0.002) var grass_fine_variation_strength: float = 0.018

@export_group("Grass Texture Repetition")
@export var grass_texture_repetition_correction_enabled: bool = true

@export_group("Terrain Texture Repetition")
@export var terrain_texture_repetition_correction_enabled: bool = true
@export var sand_texture_repetition_correction_enabled: bool = true
@export_range(0.0, 1.0, 0.05) var sand_texture_repetition_correction_strength: float = 0.55
@export var dirt_texture_repetition_correction_enabled: bool = true
@export_range(0.0, 1.0, 0.05) var dirt_texture_repetition_correction_strength: float = 0.65
@export var stone_texture_repetition_correction_enabled: bool = true
@export_range(0.0, 1.0, 0.05) var stone_texture_repetition_correction_strength: float = 0.55
@export var snow_texture_repetition_correction_enabled: bool = false
@export_range(0.0, 1.0, 0.05) var snow_texture_repetition_correction_strength: float = 0.35
@export var mud_texture_repetition_correction_enabled: bool = true
@export_range(0.0, 1.0, 0.05) var mud_texture_repetition_correction_strength: float = 0.65
@export var gravel_texture_repetition_correction_enabled: bool = false
@export_range(0.0, 1.0, 0.05) var gravel_texture_repetition_correction_strength: float = 0.35

@export_group("Stochastic Terrain Detail")
@export var stochastic_terrain_detail_enabled: bool = true
@export var sand_stochastic_detail_enabled: bool = true
@export_range(0.0, 1.0, 0.05) var sand_stochastic_detail_intensity: float = 0.95
@export var dirt_stochastic_detail_enabled: bool = true
@export_range(0.0, 1.0, 0.05) var dirt_stochastic_detail_intensity: float = 1.0
@export var stone_stochastic_detail_enabled: bool = true
@export_range(0.0, 1.0, 0.05) var stone_stochastic_detail_intensity: float = 1.0
@export var mud_stochastic_detail_enabled: bool = true
@export_range(0.0, 1.0, 0.05) var mud_stochastic_detail_intensity: float = 1.0

@export_group("Remaining Terrain Repetition")
@export var remaining_terrain_detail_enabled: bool = true
@export var snow_remaining_detail_enabled: bool = true
@export_range(0.0, 1.0, 0.05) var snow_remaining_detail_strength: float = 0.90
@export var gravel_remaining_detail_enabled: bool = true
@export_range(0.0, 1.0, 0.05) var gravel_remaining_detail_strength: float = 1.0
@export var water_repetition_correction_enabled: bool = true
@export_range(0.0, 1.0, 0.05) var water_repetition_correction_strength: float = 1.0
@export var cliff_repetition_correction_enabled: bool = true
@export_range(0.0, 1.0, 0.05) var cliff_repetition_correction_strength: float = 0.95

@export_group("Terrain Noise Refinement")
@export var terrain_noise_refinement_enabled: bool = true
@export_subgroup("Dirt")
@export_range(0.0, 1.0, 0.05) var dirt_detail_density: float = 0.70
@export_range(0.0, 1.0, 0.05) var dirt_detail_contrast: float = 0.68
@export_range(0.0, 1.0, 0.05) var dirt_clear_area_coverage: float = 0.55
@export_range(0.001, 0.02, 0.001) var dirt_detail_cluster_scale: float = 0.006
@export_subgroup("Stone")
@export_range(0.0, 1.0, 0.05) var stone_detail_density: float = 0.85
@export_range(0.0, 1.0, 0.05) var stone_detail_contrast: float = 0.72
@export_range(0.0, 1.0, 0.05) var stone_clear_area_coverage: float = 0.45
@export_range(0.001, 0.02, 0.001) var stone_detail_cluster_scale: float = 0.005
@export_subgroup("Mud")
@export_range(0.0, 1.0, 0.05) var mud_detail_density: float = 0.65
@export_range(0.0, 1.0, 0.05) var mud_detail_contrast: float = 0.55
@export_range(0.0, 1.0, 0.05) var mud_clear_area_coverage: float = 0.60
@export_range(0.001, 0.02, 0.001) var mud_detail_cluster_scale: float = 0.004
@export_subgroup("Gravel")
@export_range(0.0, 1.0, 0.05) var gravel_detail_density: float = 0.85
@export_range(0.0, 1.0, 0.05) var gravel_detail_contrast: float = 0.72
@export_range(0.0, 1.0, 0.05) var gravel_clear_area_coverage: float = 0.35
@export_range(0.001, 0.02, 0.001) var gravel_detail_cluster_scale: float = 0.008

@export_group("Organic Boundaries")
@export var organic_boundaries_enabled: bool = true
@export_range(0.0, 0.18, 0.005) var organic_edge_strength: float = 0.08
@export_range(0.005, 0.1, 0.001) var organic_edge_frequency: float = 0.035

@export_group("Experimental Water Enhancement")
@export var experimental_water_enhancement_enabled: bool = false
@export_range(0.0, 1.0, 0.01) var water_ripple_strength: float = 0.32
@export_range(0.5, 6.0, 0.1) var water_secondary_ripple_scale: float = 2.4
@export_range(0.0, 2.0, 0.05) var water_ripple_drift_speed: float = 0.55
@export_range(0.0, 1.0, 0.01) var water_glint_density: float = 0.14
@export_range(0.0, 1.0, 0.01) var water_glint_brightness: float = 0.38

@export_group("Cliff Materials")
@export var procedural_cliff_materials_enabled: bool = true
## L2 presentation-only shader LOD. One camera signal updates the shared cliff
## materials; cliff geometry and authoritative terrain remain unchanged.
@export var cliff_shader_lod_enabled: bool = true
@export_range(0.001, 4.0, 0.001) var cliff_shader_lod_min_zoom: float = 0.125
@export_range(0.001, 4.0, 0.001) var cliff_shader_lod_full_detail_zoom: float = 1.0
@export_range(0.0, 1.0, 0.01) var cliff_shader_lod_min_detail: float = 0.20
## Reversible F5 readout for the camera-to-shader LOD pipeline.
@export var cliff_shader_lod_diagnostic_visible: bool = false
@export var organic_cliff_geometry_enabled: bool = true
@export var unified_cliff_components_enabled: bool = true
@export var refined_cliff_silhouettes_enabled: bool = true
@export var connected_cliff_contours_enabled: bool = true
@export var unified_cliff_contours_enabled: bool = false
## C4F comparison switch; disabled restores the C4E.1 contour path exactly.
@export var grid_aligned_cliff_rim_enabled: bool = false
## C4I coverage underlay; presentation-only and applied only in LEGACY mode.
@export var legacy_cliff_coverage_repair_enabled: bool = true
## C4K fills only the high-side alpha disagreement beside LEGACY lateral walls.
@export var legacy_cliff_sidewall_occlusion_repair_enabled: bool = true
## C4G comparison selector. LEGACY preserves the Boolean configuration exactly.
@export_enum("LEGACY:0", "GRID:1", "UNIFIED:2", "STYLISED:3") var cliff_rendering_mode: int = 0:
	set(value):
		cliff_rendering_mode = clampi(value, 0, 3)
		if terrain != null and is_instance_valid(terrain):
			terrain.set_cliff_rendering_mode(cliff_rendering_mode)
## Phase 3G comparison; keep disabled until visual acceptance.
@export var directional_cliff_projection_enabled: bool = false
@export_enum("Baseline:0", "Moderate:1", "Prominent:2") var cliff_height_profile: int = 0

@export var cliff_edge_overlays_visible: bool = true
@export var cliff_shadows_visible: bool = true

@export_group("Ground Decorations")
@export var decorations_enabled: bool = true
@export_range(0.0, 2.0, 0.05) var decoration_density: float = 1.0
@export_range(0.0, 1.0, 0.05) var decoration_clustering_strength: float = 0.72
@export var decoration_seed_offset: int = 63017
@export_group("Environmental Objects")
@export var environment_objects_enabled: bool = true
@export var procedural_vegetation_enabled: bool = true
@export_range(0.0, 2.0, 0.05) var environment_object_density: float = 1.0
@export var environment_object_seed_offset: int = 91423
@export_range(1.0, 3600.0, 1.0) var berry_regrowth_seconds: float = 120.0
@export var world_identifier: String = "development-world"
@export var world_display_name: String = "Development World"

var terrain # TerrainRenderer script instance; intentionally dynamically typed.
var cursor # CursorOverlay script instance; intentionally dynamically typed.
var editor # WorldEditorController instance; intentionally dynamically typed.
var resource_interaction # ResourceInteractionController; transient UI state only.
var save_service
var camera: CameraController
var hud: PanelContainer
var selected_label: Label
var zoom_label: Label
var variation_label: Label
var organic_label: Label
var decoration_label: Label
var environment_objects_label: Label
var procedural_label: Label
var elevation_overlay_label: Label
var mode_label: Label
var height_label: Label
var debug_label: Label
var cliff_lod_diagnostic_label: Label
var resource_mode_label: Label
var resource_inventory_label: Label
var resource_inspection_label: Label
var save_status_label: Label
var editor_panel: PanelContainer
var editor_content: VBoxContainer
var editor_summary_label: Label
var undo_button: Button
var redo_button: Button
var reset_confirmation: ConfirmationDialog
var editor_material_picker: OptionButton
var editor_mode_picker: OptionButton
var editor_shape_picker: OptionButton
var editor_size_picker: OptionButton
var editor_elevation_picker: OptionButton
var editor_target_picker: OptionButton
var editor_restore_material_toggle: CheckButton
var expanded_hud_box: VBoxContainer
var compact_hud_box: VBoxContainer
var compact_hud_label: Label
var compact_hud_enabled: bool = true
var _worst_frame_time_ms: float = 0.0
var _resource_inspection_refresh_accumulator: float = 0.0
var _world_dirty: bool = false


func _ready() -> void:
	terrain = TerrainRenderer.new()
	_configure_terrain_renderer(terrain)
	add_child(terrain)
	terrain.authoritative_state_changed.connect(_mark_world_dirty)
	if include_elevation_demo:
		terrain.apply_phase5a_demo()

	cursor = CursorOverlay.new()
	cursor.z_index = 100
	cursor.height_step = terrain.get_cliff_height_step()
	cursor.height_lookup = terrain.get_world_surface_elevation
	cursor.cell_polygon_lookup = terrain.get_projected_cell_polygon
	terrain.add_child(cursor)
	terrain.cliff_height_profile_changed.connect(_on_cliff_height_profile_changed)

	editor = WorldEditorController.new()
	editor.configure(terrain)
	editor.state_changed.connect(_on_editor_state_changed)
	resource_interaction = ResourceInteractionController.new()
	resource_interaction.configure(terrain)
	resource_interaction.selection_changed.connect(_on_resource_selection_changed)
	terrain.resource_state_manager.inventory_changed.connect(_on_resource_inventory_changed)
	terrain.resource_state_manager.resource_changed.connect(_on_resource_state_changed)
	save_service = WorldSaveService.new()

	camera = CameraController.new()
	camera.name = "MapCamera"
	add_child(camera)
	camera.make_current()
	camera.zoom_changed.connect(_on_camera_zoom_changed)

	_create_hud()
	_create_editor_panel()
	_update_selected_label()
	camera.reset_view()
	_update_visible_world_region()


func _configure_terrain_renderer(renderer: TerrainRenderer) -> void:
	## Complete configuration before add_child() initializes renderer-owned
	## materials, procedural contexts, terrain authority, and resource state.
	TerrainRendererConfiguration.capture(self).apply_to(renderer)


func _process(delta: float) -> void:
	_worst_frame_time_ms = maxf(_worst_frame_time_ms, delta * 1000.0)
	var selected_resource: Dictionary = resource_interaction.get_selected()
	if (not selected_resource.is_empty()
			and String(selected_resource.get("category", "")) == "food"
			and not bool(selected_resource.get("ripe", true))):
		_resource_inspection_refresh_accumulator += delta
		if _resource_inspection_refresh_accumulator >= 0.25:
			_resource_inspection_refresh_accumulator = 0.0
			resource_interaction.refresh_selected()
	else:
		_resource_inspection_refresh_accumulator = 0.0
	camera.update_keyboard_movement(delta)
	camera.release_middle_pan_if_needed()
	_update_visible_world_region()

	var pick: Dictionary = _screen_to_world_pick(get_viewport().get_mouse_position())
	var world_cell: Vector2i = pick.cell
	var over_ui: bool = _mouse_over_ui()
	var hover_changed: bool = (
		cursor.selected_cell != world_cell
		or cursor.selected_height != int(pick.elevation)
		or cursor.selected_is_cliff != bool(pick.is_cliff)
		or cursor.selected_cliff_drop != int(pick.cliff_drop))
	if hover_changed:
		cursor.selected_cell = world_cell
		cursor.selected_height = int(pick.elevation)
		cursor.selected_is_cliff = bool(pick.is_cliff)
		cursor.selected_cliff_drop = int(pick.cliff_drop)
		cursor.brush_cells = editor.get_brush_cells(world_cell)
		cursor.queue_redraw()
		_update_height_label(pick)
	cursor.enabled = not resource_interaction.resource_mode and not over_ui and not camera.is_middle_panning()
	if over_ui:
		cursor.queue_redraw()
	_update_debug_label(pick, delta)
	_update_cliff_lod_diagnostic()

	var can_paint: bool = _can_editor_paint(over_ui)
	editor.update_pointer_stroke(
		world_cell, can_paint,
		Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),
		Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))


func _unhandled_input(event: InputEvent) -> void:
	# Controls receive input before _unhandled_input. Remaining pointer priority is
	# resource selection first, then camera navigation; editor drags are polled in
	# _process only while neither of those systems nor the UI owns the pointer.
	var mouse_button := event as InputEventMouseButton
	if mouse_button != null:
		if (resource_interaction.resource_mode
				and mouse_button.button_index == MOUSE_BUTTON_LEFT
				and mouse_button.pressed and not _mouse_over_ui()):
			var pick: Dictionary = _screen_to_world_pick(mouse_button.position)
			resource_interaction.select_at(pick.cell)
			get_viewport().set_input_as_handled()
		elif camera.handle_pointer_input(mouse_button):
			get_viewport().set_input_as_handled()
		return

	if camera.handle_pointer_input(event):
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	var key: int = key_event.keycode
	if key_event.ctrl_pressed and key == KEY_S:
		_save_quicksave()
	elif key_event.ctrl_pressed and key == KEY_L:
		_load_quicksave()
	elif editor.handle_shortcut(key_event):
		pass
	elif key == KEY_R:
		reset_confirmation.popup_centered()
	elif key == KEY_G:
		cursor.show_grid = not cursor.show_grid
		cursor.queue_redraw()
	elif camera.handle_navigation_shortcut(key_event):
		pass
	elif key == KEY_F2:
		compact_hud_enabled = not compact_hud_enabled
		_apply_hud_mode()
	elif key == KEY_F3:
		debug_label.visible = not debug_label.visible
	elif key == KEY_F4:
		cursor.show_affected_dual_cells = not cursor.show_affected_dual_cells
		cursor.queue_redraw()
	elif key == KEY_F5:
		cliff_shader_lod_diagnostic_visible = not cliff_shader_lod_diagnostic_visible
		cliff_lod_diagnostic_label.visible = cliff_shader_lod_diagnostic_visible
		_update_cliff_lod_diagnostic()
	elif key == KEY_F6:
		cursor.show_elevation_overlay = not cursor.show_elevation_overlay
		cursor.queue_redraw()
		_update_elevation_overlay_label()
	elif key == KEY_V:
		texture_variation_enabled = not texture_variation_enabled
		terrain.set_texture_variation_enabled(texture_variation_enabled)
		_update_variation_label()
	elif key == KEY_O:
		organic_boundaries_enabled = not organic_boundaries_enabled
		terrain.set_organic_boundaries_enabled(organic_boundaries_enabled)
		_update_organic_label()
	elif key == KEY_D:
		decorations_enabled = not decorations_enabled
		terrain.set_decorations_enabled(decorations_enabled)
		_update_decoration_label()
	elif key == KEY_T:
		environment_objects_enabled = not environment_objects_enabled
		terrain.set_environment_objects_enabled(environment_objects_enabled)
		_update_environment_objects_label()
	elif key == KEY_Q:
		resource_interaction.set_resource_mode(not resource_interaction.resource_mode)
		_update_resource_mode_label()
		_update_compact_hud()
	elif key == KEY_E and resource_interaction.resource_mode:
		resource_interaction.designate_selected()
	elif key == KEY_C and resource_interaction.resource_mode:
		resource_interaction.cancel_selected_designation()
	elif key == KEY_F8 and resource_interaction.resource_mode:
		resource_interaction.debug_complete_selected()
	elif key == KEY_ESCAPE and resource_interaction.resource_mode:
		resource_interaction.clear_selection()
	elif key == KEY_P:
		procedural_elevation_enabled = not procedural_elevation_enabled
		terrain.set_procedural_elevation_enabled(procedural_elevation_enabled)
		_update_procedural_label()


func _update_visible_world_region() -> void:
	var visible_rect: Rect2 = camera.get_visible_world_rect(terrain, get_viewport_rect().size)
	cursor.set_visible_world_rect(visible_rect)
	terrain.update_visible_world_rect(visible_rect)


func _screen_to_world_pick(screen_position: Vector2) -> Dictionary:
	var terrain_local: Vector2 = terrain.get_global_transform_with_canvas().affine_inverse() * screen_position
	var target_ground: bool = (
		editor.edit_mode == WorldEditorController.EditMode.ELEVATION
		and Input.is_key_pressed(KEY_ALT))
	return terrain.pick_world_position(terrain_local, target_ground)


func _mouse_over_ui() -> bool:
	return _screen_position_over_ui(get_viewport().get_mouse_position())


func _screen_position_over_ui(mouse_position: Vector2) -> bool:
	return (
		(hud != null and hud.visible and hud.get_global_rect().has_point(mouse_position))
		or (editor_panel != null and editor_panel.visible
			and editor_panel.get_global_rect().has_point(mouse_position))
		or (reset_confirmation != null and reset_confirmation.visible))


func _can_editor_paint(over_ui: bool) -> bool:
	return (
		not over_ui
		and not resource_interaction.resource_mode
		and not camera.is_middle_panning()
		and not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE))


func _update_selected_label() -> void:
	if editor == null:
		return
	var state: Dictionary = editor.get_state_snapshot()
	var selected_material: int = int(state["selected_material"])
	for material in Catalog.MATERIALS:
		if int(material["id"]) == selected_material:
			selected_label.text = "Selected: %s (key %d)" % [
				material["name"], selected_material + 1]
			_update_compact_hud()
			return


func _on_editor_state_changed() -> void:
	_update_selected_label()
	_update_mode_label()
	_refresh_brush_preview()
	_update_editor_summary()


func _update_zoom_label() -> void:
	if zoom_label != null and camera != null:
		zoom_label.text = "Zoom: %d%%" % roundi(camera.zoom.x * 100.0)
		_update_compact_hud()


func _on_camera_zoom_changed(_zoom_value: float) -> void:
	if terrain != null and is_instance_valid(terrain):
		terrain.set_cliff_shader_lod_zoom(_zoom_value)
	_update_zoom_label()
	_update_cliff_lod_diagnostic()


func _update_cliff_lod_diagnostic() -> void:
	if (cliff_lod_diagnostic_label == null
			or not cliff_lod_diagnostic_label.visible
			or terrain == null or camera == null):
		return
	var diagnostic: Dictionary = terrain.get_cliff_shader_lod_diagnostics()
	cliff_lod_diagnostic_label.text = (
		"Cliff shader LOD (F5)\n"
		+ "Camera zoom: %.3f (%d%%)\n"
		+ "Calculated: %.3f   Applied: %.3f\n"
		+ "Shader actual: %.3f   Shared: %d/%s") % [
		camera.zoom.x, roundi(camera.zoom.x * 100.0),
		float(diagnostic.calculated_detail), float(diagnostic.applied_detail),
		float(diagnostic.actual_material_detail), int(diagnostic.material_count),
		"match" if bool(diagnostic.all_materials_match) else "MISMATCH"]


func _update_variation_label() -> void:
	if variation_label != null:
		variation_label.text = "Variation: %s (V)" % ("On" if texture_variation_enabled else "Off")


func _update_organic_label() -> void:
	if organic_label != null:
		organic_label.text = "Organic boundaries: %s (O)" % ("On" if organic_boundaries_enabled else "Off")


func _update_decoration_label() -> void:
	if decoration_label != null:
		decoration_label.text = "Ground details: %s (D)" % (
			"On" if decorations_enabled else "Off")
		_update_compact_hud()


func _update_environment_objects_label() -> void:
	if environment_objects_label != null:
		environment_objects_label.text = "Trees / objects: %s (T)" % (
			"On" if environment_objects_enabled else "Off")
		_update_compact_hud()


func _update_resource_mode_label() -> void:
	if resource_mode_label != null:
		resource_mode_label.text = "Interaction: %s (Q)" % (
			"RESOURCE" if resource_interaction.resource_mode else "TERRAIN")


func _on_resource_inventory_changed(_totals: Dictionary = {}) -> void:
	_update_resource_inventory_label()
	_update_compact_hud()


func _update_resource_inventory_label() -> void:
	if resource_inventory_label == null:
		return
	var totals: Dictionary = terrain.get_resource_inventory()
	resource_inventory_label.text = "Inventory — Wood %d   Stone %d   Food %d" % [
		int(totals.get("wood", 0)), int(totals.get("stone", 0)), int(totals.get("food", 0))]


func _on_resource_selection_changed(snapshot: Dictionary) -> void:
	if resource_inspection_label == null:
		return
	if snapshot.is_empty():
		resource_inspection_label.text = "Resource: none selected"
		return
	var availability: String = "Ripe" if bool(snapshot.get("ripe", true)) else "Unripe"
	if String(snapshot["category"]) != "food":
		availability = "Available" if bool(snapshot["available"]) else "Depleted"
	var designation: String = "Designated" if bool(snapshot["designated"]) else "Not designated"
	var regrowth: String = ""
	if String(snapshot["category"]) == "food" and not bool(snapshot.get("ripe", true)):
		regrowth = "   Regrowth %.1fs" % float(snapshot.get("regrowth_remaining", 0.0))
	resource_inspection_label.text = "%s — %s, %s, yield %d %s%s" % [
		String(snapshot["name"]), String(snapshot["category"]).capitalize(),
		availability, int(snapshot["expected_yield"]), designation, regrowth]


func _on_resource_state_changed(
		resource_id: String, _anchor: Vector2i,
		_definition_id: int, _change_kind: String) -> void:
	var selected: Dictionary = resource_interaction.get_selected()
	if not selected.is_empty() and String(selected["resource_id"]) == resource_id:
		resource_interaction.refresh_selected()


func _mark_world_dirty() -> void:
	_world_dirty = true
	_update_save_status("Unsaved changes")


func _on_cliff_height_profile_changed(height_step: int) -> void:
	if cursor == null:
		return
	cliff_height_profile = terrain.get_cliff_height_profile()
	cursor.height_step = float(height_step)
	cursor.queue_redraw()


func _update_save_status(status: String = "") -> void:
	if save_status_label == null:
		return
	if not status.is_empty():
		save_status_label.text = "Save: %s" % status
	elif _world_dirty:
		save_status_label.text = "Save: Unsaved changes"
	else:
		save_status_label.text = "Save: Up to date"


func _save_quicksave() -> Dictionary:
	var snapshot_start: int = Time.get_ticks_usec()
	var snapshot: Dictionary = save_service.capture_snapshot(
		terrain, camera, world_identifier, world_display_name)
	var snapshot_usec: int = Time.get_ticks_usec() - snapshot_start
	var result: Dictionary = save_service.save_snapshot(snapshot)
	result["snapshot_usec"] = snapshot_usec
	if bool(result.get("ok", false)):
		_world_dirty = false
		_update_save_status("Saved quicksave.json")
	else:
		_update_save_status("ERROR — %s" % result.get("error", "Unknown save error"))
	return result


func _load_quicksave() -> Dictionary:
	var result: Dictionary = save_service.load_snapshot()
	if not bool(result.get("ok", false)):
		_update_save_status("ERROR — %s" % result.get("error", "Unknown load error"))
		return result
	var restoration_start: int = Time.get_ticks_usec()
	var restore_result: Dictionary = _replace_world_from_snapshot(result["snapshot"])
	restore_result["load_usec"] = int(result.get("load_usec", 0))
	restore_result["validation_usec"] = int(result.get("validation_usec", 0))
	restore_result["restore_usec"] = Time.get_ticks_usec() - restoration_start
	if bool(restore_result.get("ok", false)):
		_world_dirty = false
		_update_save_status("Loaded quicksave.json")
	else:
		_update_save_status("ERROR — %s" % restore_result.get("error", "Unknown restore error"))
	return restore_result


func _replace_world_from_snapshot(snapshot: Dictionary) -> Dictionary:
	var saved_world: Dictionary = snapshot["world"]
	var generation: Dictionary = saved_world["generation"]
	var old_terrain = terrain
	var replacement = TerrainRenderer.new()
	_configure_terrain_renderer(replacement)
	# Saved authority overrides matching scene exports before _ready() builds its
	# generator, placement contexts, and resource-state manager.
	replacement.apply_generation_config(generation)
	replacement.berry_regrowth_seconds = float(snapshot["resources"]["berry_regrowth_seconds"])
	add_child(replacement)
	var import_result: Dictionary = replacement.import_authoritative_snapshot({
		"terrain": snapshot["terrain"], "resources": snapshot["resources"],
	})
	if not bool(import_result["ok"]):
		replacement.queue_free()
		return import_result

	resource_interaction.clear_selection()
	old_terrain.remove_child(cursor)
	replacement.add_child(cursor)
	cursor.height_lookup = replacement.get_world_surface_elevation
	cursor.cell_polygon_lookup = replacement.get_projected_cell_polygon
	cursor.height_step = replacement.get_cliff_height_step()
	terrain = replacement
	editor.configure(terrain)
	editor.reset_runtime_state()
	resource_interaction.configure(terrain)
	terrain.authoritative_state_changed.connect(_mark_world_dirty)
	terrain.cliff_height_profile_changed.connect(_on_cliff_height_profile_changed)
	terrain.resource_state_manager.inventory_changed.connect(_on_resource_inventory_changed)
	terrain.resource_state_manager.resource_changed.connect(_on_resource_state_changed)
	old_terrain.visible = false
	old_terrain.queue_free()

	world_identifier = String(saved_world["id"])
	world_display_name = String(saved_world["display_name"])
	_sync_configuration_from_terrain()
	var camera_state: Dictionary = saved_world.get("camera", {})
	if not camera_state.is_empty():
		camera.apply_state(
			Vector2(float(camera_state["x"]), float(camera_state["y"])),
			float(camera_state["zoom"]))
	_update_visible_world_region()
	_update_selected_label()
	_update_mode_label()
	_update_environment_objects_label()
	_update_resource_inventory_label()
	_update_editor_summary()
	return {"ok": true, "error": ""}


func _sync_configuration_from_terrain() -> void:
	var config: Dictionary = terrain.export_generation_config()
	world_seed = int(config["world_seed"])
	biome_frequency = float(config["biome_frequency"])
	detail_frequency = float(config["detail_frequency"])
	include_origin_demo = bool(config["include_origin_demo"])
	procedural_elevation_enabled = bool(config["procedural_elevation_enabled"])
	max_generated_elevation = int(config["max_generated_elevation"])
	elevation_frequency = float(config["elevation_frequency"])
	elevation_detail_frequency = float(config["elevation_detail_frequency"])
	elevation_detail_strength = float(config["elevation_detail_strength"])
	elevation_threshold_1 = float(config["elevation_threshold_1"])
	elevation_threshold_2 = float(config["elevation_threshold_2"])
	elevation_threshold_3 = float(config["elevation_threshold_3"])
	elevation_flatness_bias = float(config["elevation_flatness_bias"])
	sea_level = int(config["sea_level"])
	decoration_density = float(config["decoration_density"])
	decoration_clustering_strength = float(config["decoration_clustering_strength"])
	decoration_seed_offset = int(config["decoration_seed_offset"])
	environment_object_density = float(config["environment_object_density"])
	environment_object_seed_offset = int(config["environment_object_seed_offset"])
	berry_regrowth_seconds = terrain.resource_state_manager.berry_regrowth_seconds


func _update_procedural_label() -> void:
	if procedural_label != null:
		procedural_label.text = "Procedural elevation: %s (P)" % (
			"On" if procedural_elevation_enabled else "Off")


func _update_elevation_overlay_label() -> void:
	if elevation_overlay_label != null:
		elevation_overlay_label.text = (
            "Height overlay: %s (F6)   0 blue  1 green  2 amber  3 magenta"
			% ("On" if cursor.show_elevation_overlay else "Off"))


func _update_mode_label() -> void:
	if mode_label != null and editor != null:
		var state: Dictionary = editor.get_state_snapshot()
		mode_label.text = "Editing: %s (H)" % (
			"Elevation" if int(state["edit_mode"]) == WorldEditorController.EditMode.ELEVATION
			else "Material")
		_update_compact_hud()


func _update_height_label(pick: Dictionary = {}) -> void:
	if height_label == null:
		return
	var elevation: int = cursor.selected_height if pick.is_empty() else int(pick.elevation)
	var is_cliff: bool = cursor.selected_is_cliff if pick.is_empty() else bool(pick.is_cliff)
	var targets_ground: bool = false if pick.is_empty() else bool(pick.get("targets_ground", false))
	var target: String = (
		"ground coordinate" if targets_ground else ("cliff face" if is_cliff else "surface"))
	var world_cell: Vector2i = cursor.selected_cell if pick.is_empty() else pick.cell
	var material_name: String = Catalog.material_name(terrain.get_world_cell(world_cell))
	var liquid_elevation: int = terrain.get_world_visible_liquid_elevation(world_cell)
	height_label.text = "Cell: %s   Ground: %d   Liquid: %s   Target: %s" % [
		material_name, terrain.get_world_elevation(world_cell),
		str(liquid_elevation) if liquid_elevation >= 0 else "none", target]
	_update_compact_hud()


func _update_compact_hud() -> void:
	if compact_hud_label == null or camera == null or cursor == null:
		return
	var editor_state: Dictionary = editor.get_state_snapshot()
	var material_name: String = "Unknown"
	for material in Catalog.MATERIALS:
		if int(material["id"]) == int(editor_state["selected_material"]):
			material_name = String(material["name"])
			break
	var totals: Dictionary = terrain.get_resource_inventory()
	var selected_cell: Vector2i = cursor.selected_cell
	var cell_material: String = Catalog.material_name(terrain.get_world_cell(selected_cell))
	var ground_height: int = terrain.get_world_elevation(selected_cell)
	var liquid_height: int = terrain.get_world_visible_liquid_elevation(selected_cell)
	compact_hud_label.text = (
        "%s  |  %s  |  Brush %d  |  %s\nCell %s  |  Ground %d  |  Liquid %s\nWood %d  Stone %d  Food %d  |  Zoom %d%%  |  F2: expand"
		% [
			material_name,
			"Elevation" if int(editor_state["edit_mode"]) == WorldEditorController.EditMode.ELEVATION else "Material",
			int(editor_state["brush_size"]),
			"RESOURCE" if resource_interaction != null and resource_interaction.resource_mode else "TERRAIN",
			cell_material, ground_height, str(liquid_height) if liquid_height >= 0 else "none",
			int(totals.get("wood", 0)), int(totals.get("stone", 0)), int(totals.get("food", 0)),
			roundi(camera.zoom.x * 100.0),
		])


func _apply_hud_mode() -> void:
	if compact_hud_box == null or expanded_hud_box == null:
		return
	compact_hud_box.visible = compact_hud_enabled
	expanded_hud_box.visible = not compact_hud_enabled
	_update_compact_hud()


func _update_debug_label(pick: Dictionary, delta: float) -> void:
	if debug_label == null or not debug_label.visible:
		return
	var world_cell: Vector2i = pick.cell
	var chunk_coord: Vector2i = terrain.world_cell_to_chunk(world_cell)
	var object_categories: Dictionary = terrain.get_environment_object_category_counts()
	debug_label.text = "FPS: %d   Frame: %.2f ms   Worst: %.2f ms\nCamera: (%.1f, %.1f)\nCell: (%d, %d)   Height: %d   Target: %s   Chunk: (%d, %d)\nLoaded: %d   Pending: %d   Finalised: %d   Details: %d   Objects: %d\nObject categories: trees %d   bushes %d   rocks %d   debris %d\nChunk work: %.2f / %.2f ms   Overruns: %d   Last chunk: %.2f ms\nCliff prep: %.2f ms   Decoration prep / submit: %.2f / %.2f ms\nObject prep / submit: %.2f / %.2f ms\nOrganic: %s   Decorations: %s   Objects: %s   Procedural elevation: %s   Material edits: %d   Height edits: %d   Seed: %d" % [
		Engine.get_frames_per_second(), delta * 1000.0, _worst_frame_time_ms,
		camera.position.x, camera.position.y,
		world_cell.x, world_cell.y, int(pick.elevation), "Cliff" if bool(pick.is_cliff) else "Surface",
		chunk_coord.x, chunk_coord.y,
		terrain.get_loaded_chunk_count(), terrain.get_pending_chunk_count(), terrain.chunks_finalised_this_frame,
		terrain.get_visible_decoration_count(),
		terrain.get_visible_environment_object_count(),
		int(object_categories.get("trees", 0)), int(object_categories.get("bushes", 0)),
		int(object_categories.get("rocks", 0)), int(object_categories.get("debris", 0)),
		float(terrain.chunk_processing_usec_this_frame) / 1000.0, terrain.max_chunk_processing_ms,
		terrain.chunk_processing_overrun_frames,
		float(terrain.last_chunk_total_usec) / 1000.0,
		float(terrain.last_chunk_cliff_usec) / 1000.0,
		float(terrain.last_chunk_decoration_usec) / 1000.0,
		float(terrain.last_chunk_decoration_submission_usec) / 1000.0,
		float(terrain.last_chunk_environment_usec) / 1000.0,
		float(terrain.last_chunk_environment_submission_usec) / 1000.0,
		"On" if organic_boundaries_enabled else "Off",
		"On" if decorations_enabled else "Off",
		"On" if environment_objects_enabled else "Off",
		"On" if procedural_elevation_enabled else "Off",
		terrain.get_override_count(), terrain.get_height_override_count(), world_seed
	]


func _create_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = PanelContainer.new()
	hud.position = Vector2(18, 18)
	canvas.add_child(hud)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("14212d")
	style.border_color = Color("5b7981")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14)
	hud.add_theme_stylebox_override("panel", style)
	var hud_content := VBoxContainer.new()
	hud.add_child(hud_content)
	compact_hud_box = VBoxContainer.new()
	hud_content.add_child(compact_hud_box)
	compact_hud_label = Label.new()
	compact_hud_label.add_theme_color_override("font_color", Color("ffde99"))
	compact_hud_box.add_child(compact_hud_label)
	expanded_hud_box = VBoxContainer.new()
	expanded_hud_box.add_theme_constant_override("separation", 5)
	hud_content.add_child(expanded_hud_box)
	var box: VBoxContainer = expanded_hud_box
	var title := Label.new()
	title.text = "WYNTAR"
	title.add_theme_color_override("font_color", Color("f2f4f0"))
	title.add_theme_font_size_override("font_size", 17)
	box.add_child(title)
	var instructions := Label.new()
	instructions.text = "1 Water   2 Sand   3 Dirt   4 Grass\n5 Stone   6 Snow   7 Mud   8 Gravel\n\nH: material / elevation mode   [ / ]: brush size\nLeft-drag: selected tool   Right-drag: restore / lower\nAlt + elevation edit: target logical ground cell\nQ: terrain/resource mode   Resource click: inspect\nE: designate   C: cancel   Esc: clear   F8: DEBUG complete\nCtrl+S: quicksave   Ctrl+L: quickload\nCtrl+Z: undo   Ctrl+Y or Ctrl+Shift+Z: redo\nWASD / arrows: move   Middle-drag: pan\nWheel: zoom   Home: camera reset\nR: confirm reset edits   G: grid   V: variation\nO: organic edges   D: ground details\nT: trees / objects   P: procedural elevation\nF2: compact HUD   F3: diagnostics\nF4: cell debug   F5: cliff LOD   F6: heights"
	instructions.add_theme_color_override("font_color", Color("c2d4dc"))
	box.add_child(instructions)
	selected_label = Label.new()
	selected_label.add_theme_color_override("font_color", Color("ffde99"))
	box.add_child(selected_label)
	zoom_label = Label.new()
	zoom_label.add_theme_color_override("font_color", Color("9fc3ce"))
	box.add_child(zoom_label)
	variation_label = Label.new()
	variation_label.add_theme_color_override("font_color", Color("9fc3ce"))
	box.add_child(variation_label)
	_update_variation_label()
	organic_label = Label.new()
	organic_label.add_theme_color_override("font_color", Color("9fc3ce"))
	box.add_child(organic_label)
	_update_organic_label()
	decoration_label = Label.new()
	decoration_label.add_theme_color_override("font_color", Color("9fc3ce"))
	box.add_child(decoration_label)
	_update_decoration_label()
	environment_objects_label = Label.new()
	environment_objects_label.add_theme_color_override("font_color", Color("9fc3ce"))
	box.add_child(environment_objects_label)
	_update_environment_objects_label()
	resource_mode_label = Label.new()
	resource_mode_label.add_theme_color_override("font_color", Color("ffde99"))
	box.add_child(resource_mode_label)
	_update_resource_mode_label()
	resource_inventory_label = Label.new()
	resource_inventory_label.add_theme_color_override("font_color", Color("a8e6cf"))
	box.add_child(resource_inventory_label)
	_update_resource_inventory_label()
	save_status_label = Label.new()
	save_status_label.add_theme_color_override("font_color", Color("9fc3ce"))
	box.add_child(save_status_label)
	_update_save_status()
	resource_inspection_label = Label.new()
	resource_inspection_label.add_theme_color_override("font_color", Color("ffcf70"))
	resource_inspection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	resource_inspection_label.custom_minimum_size.x = 520.0
	box.add_child(resource_inspection_label)
	_on_resource_selection_changed({})
	procedural_label = Label.new()
	procedural_label.add_theme_color_override("font_color", Color("9fc3ce"))
	box.add_child(procedural_label)
	_update_procedural_label()
	elevation_overlay_label = Label.new()
	elevation_overlay_label.add_theme_color_override("font_color", Color("9fc3ce"))
	box.add_child(elevation_overlay_label)
	_update_elevation_overlay_label()
	mode_label = Label.new()
	mode_label.add_theme_color_override("font_color", Color("ffde99"))
	box.add_child(mode_label)
	_update_mode_label()
	height_label = Label.new()
	height_label.add_theme_color_override("font_color", Color("9fc3ce"))
	box.add_child(height_label)
	_update_height_label()
	debug_label = Label.new()
	debug_label.visible = false
	debug_label.add_theme_color_override("font_color", Color("a8e6cf"))
	box.add_child(debug_label)
	cliff_lod_diagnostic_label = Label.new()
	cliff_lod_diagnostic_label.visible = cliff_shader_lod_diagnostic_visible
	cliff_lod_diagnostic_label.add_theme_color_override("font_color", Color("ffcf70"))
	hud_content.add_child(cliff_lod_diagnostic_label)
	_update_cliff_lod_diagnostic()
	_apply_hud_mode()


func _create_editor_panel() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 2
	add_child(canvas)
	editor_panel = PanelContainer.new()
	editor_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	editor_panel.position = Vector2(-310.0, 18.0)
	editor_panel.size = Vector2(292.0, 0.0)
	canvas.add_child(editor_panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("14212dee")
	style.border_color = Color("5b7981")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(12)
	editor_panel.add_theme_stylebox_override("panel", style)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	editor_panel.add_child(root)
	var collapse := Button.new()
	collapse.text = "WORLD EDITOR  ▾"
	root.add_child(collapse)
	editor_content = VBoxContainer.new()
	editor_content.add_theme_constant_override("separation", 5)
	root.add_child(editor_content)
	collapse.pressed.connect(func() -> void:
		editor_content.visible = not editor_content.visible
		collapse.text = "WORLD EDITOR  %s" % ("▾" if editor_content.visible else "▸")
	)

	editor_material_picker = OptionButton.new()
	for material in Catalog.MATERIALS:
		editor_material_picker.add_item(String(material.name), int(material.id))
	editor_material_picker.select(int(editor.get_state_snapshot()["selected_material"]))
	_add_editor_row("Material", editor_material_picker)
	editor_material_picker.item_selected.connect(func(index: int) -> void:
		editor.set_selected_material(editor_material_picker.get_item_id(index))
	)

	editor_mode_picker = OptionButton.new()
	editor_mode_picker.add_item("Material", WorldEditorController.EditMode.MATERIAL)
	editor_mode_picker.add_item("Elevation", WorldEditorController.EditMode.ELEVATION)
	_add_editor_row("Mode", editor_mode_picker)
	editor_mode_picker.item_selected.connect(func(index: int) -> void:
		editor.set_edit_mode(editor_mode_picker.get_item_id(index))
	)

	editor_shape_picker = OptionButton.new()
	editor_shape_picker.add_item("Circle", WorldEditorController.BrushShape.CIRCLE)
	editor_shape_picker.add_item("Square", WorldEditorController.BrushShape.SQUARE)
	_add_editor_row("Shape", editor_shape_picker)
	editor_shape_picker.item_selected.connect(func(index: int) -> void:
		editor.set_brush_shape(editor_shape_picker.get_item_id(index))
	)

	editor_size_picker = OptionButton.new()
	for size in WorldEditorController.BRUSH_SIZES:
		editor_size_picker.add_item("%d cells" % size, size)
	_add_editor_row("Size", editor_size_picker)
	editor_size_picker.item_selected.connect(func(index: int) -> void:
		editor.set_brush_size(editor_size_picker.get_item_id(index))
	)

	editor_restore_material_toggle = CheckButton.new()
	editor_restore_material_toggle.text = "Restore generated material"
	editor_content.add_child(editor_restore_material_toggle)
	editor_restore_material_toggle.toggled.connect(func(enabled: bool) -> void:
		editor.set_restore_material(enabled)
	)

	editor_elevation_picker = OptionButton.new()
	editor_elevation_picker.add_item("Raise", WorldEditorController.ElevationTool.RAISE)
	editor_elevation_picker.add_item("Lower", WorldEditorController.ElevationTool.LOWER)
	editor_elevation_picker.add_item("Set height", WorldEditorController.ElevationTool.SET_HEIGHT)
	editor_elevation_picker.add_item("Flatten (sample)", WorldEditorController.ElevationTool.FLATTEN)
	editor_elevation_picker.add_item("Restore generated", WorldEditorController.ElevationTool.RESTORE)
	_add_editor_row("Elevation", editor_elevation_picker)
	editor_elevation_picker.item_selected.connect(func(index: int) -> void:
		editor.set_elevation_tool(editor_elevation_picker.get_item_id(index))
	)

	editor_target_picker = OptionButton.new()
	for elevation in range(4):
		editor_target_picker.add_item("Level %d" % elevation, elevation)
	_add_editor_row("Target", editor_target_picker)
	editor_target_picker.item_selected.connect(func(index: int) -> void:
		editor.set_target_elevation(editor_target_picker.get_item_id(index))
	)

	var history_row := HBoxContainer.new()
	undo_button = Button.new()
	undo_button.text = "Undo"
	history_row.add_child(undo_button)
	redo_button = Button.new()
	redo_button.text = "Redo"
	history_row.add_child(redo_button)
	var reset_button := Button.new()
	reset_button.text = "Reset edits…"
	history_row.add_child(reset_button)
	editor_content.add_child(history_row)
	undo_button.pressed.connect(func() -> void:
		editor.undo()
	)
	redo_button.pressed.connect(func() -> void:
		editor.redo()
	)
	reset_button.pressed.connect(func() -> void: reset_confirmation.popup_centered())

	editor_summary_label = Label.new()
	editor_summary_label.add_theme_color_override("font_color", Color("9fc3ce"))
	editor_content.add_child(editor_summary_label)
	var help := Label.new()
	help.text = "Drag: apply   Right-drag: restore/lower\n[ / ]: brush size   Ctrl+Z / Ctrl+Y: history"
	help.add_theme_color_override("font_color", Color("a8b8bf"))
	editor_content.add_child(help)

	reset_confirmation = ConfirmationDialog.new()
	reset_confirmation.title = "Reset all terrain edits?"
	reset_confirmation.dialog_text = "This creates one undoable transaction. Procedural terrain will be restored."
	add_child(reset_confirmation)
	reset_confirmation.confirmed.connect(func() -> void:
		editor.reset_all_edits()
	)
	_update_editor_summary()


func _add_editor_row(label_text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 82.0
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	editor_content.add_child(row)


func _refresh_brush_preview() -> void:
	if editor == null or cursor == null:
		return
	cursor.brush_cells = editor.get_brush_cells(cursor.selected_cell)
	cursor.queue_redraw()
	_update_compact_hud()


func _update_editor_summary() -> void:
	if editor_summary_label == null:
		return
	var state: Dictionary = editor.get_state_snapshot()
	var shape_name: String = (
		"Circle" if int(state["brush_shape"]) == WorldEditorController.BrushShape.CIRCLE
		else "Square")
	editor_summary_label.text = "%s %d  •  Undo %d  •  Redo %d" % [
		shape_name, int(state["brush_size"]), int(state["undo_count"]), int(state["redo_count"])]
	undo_button.disabled = not bool(state["can_undo"])
	redo_button.disabled = not bool(state["can_redo"])
	_select_option_id(editor_material_picker, int(state["selected_material"]))
	_select_option_id(editor_mode_picker, int(state["edit_mode"]))
	_select_option_id(editor_shape_picker, int(state["brush_shape"]))
	_select_option_id(editor_size_picker, int(state["brush_size"]))
	_select_option_id(editor_elevation_picker, int(state["elevation_tool"]))
	_select_option_id(editor_target_picker, int(state["target_elevation"]))
	editor_restore_material_toggle.set_pressed_no_signal(bool(state["restore_material"]))
	_update_compact_hud()


func _select_option_id(option: OptionButton, item_id: int) -> void:
	if option == null:
		return
	var index: int = option.get_item_index(item_id)
	if index >= 0:
		option.select(index)

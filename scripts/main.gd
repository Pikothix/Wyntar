extends Node2D
## Owns demo input, camera navigation, painting requests, and the screen-space HUD.
## TerrainRenderer streams visuals; its TerrainWorld remains gameplay authority.

const Catalog = preload("res://scripts/terrain_catalog.gd")
const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")
const CursorOverlay = preload("res://scripts/cursor_overlay.gd")
const WorldEditorController = preload("res://scripts/world_editor_controller.gd")
const ResourceInteractionController = preload("res://scripts/resource_interaction_controller.gd")
const WorldSaveService = preload("res://scripts/world_save_service.gd")

const CAMERA_PAN_SPEED: float = 700.0
const CAMERA_MIN_ZOOM: float = 0.001
const CAMERA_MAX_ZOOM: float = 166.0
const CAMERA_ZOOM_FACTOR: float = 1.15
const DEMO_CENTER: Vector2 = Vector2(16.0, 16.0)

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

@export_group("Organic Boundaries")
@export var organic_boundaries_enabled: bool = true
@export_range(0.0, 0.18, 0.005) var organic_edge_strength: float = 0.08
@export_range(0.005, 0.1, 0.001) var organic_edge_frequency: float = 0.035

@export_group("Cliff Materials")
@export var procedural_cliff_materials_enabled: bool = true
@export var organic_cliff_geometry_enabled: bool = true
@export var unified_cliff_components_enabled: bool = true
@export var refined_cliff_silhouettes_enabled: bool = true
@export var connected_cliff_contours_enabled: bool = true

@export_group("Experimental 2.5D Presentation")
@export var oblique_presentation_enabled: bool = false
@export var organic_oblique_refinement_enabled: bool = false
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
var camera: Camera2D
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
var selected_id: int = 3
var height_edit_mode: bool = false
var _middle_panning: bool = false
var _worst_frame_time_ms: float = 0.0
var _last_height_paint_cell: Variant = null
var _stroke_button: int = 0
var _resource_inspection_refresh_accumulator: float = 0.0
var _world_dirty: bool = false


func _ready() -> void:
	terrain = TerrainRenderer.new()
	terrain.world_seed = world_seed
	terrain.biome_frequency = biome_frequency
	terrain.detail_frequency = detail_frequency
	terrain.include_origin_demo = include_origin_demo
	terrain.procedural_elevation_enabled = procedural_elevation_enabled
	terrain.max_generated_elevation = max_generated_elevation
	terrain.elevation_frequency = elevation_frequency
	terrain.elevation_detail_frequency = elevation_detail_frequency
	terrain.elevation_detail_strength = elevation_detail_strength
	terrain.elevation_threshold_1 = elevation_threshold_1
	terrain.elevation_threshold_2 = elevation_threshold_2
	terrain.elevation_threshold_3 = elevation_threshold_3
	terrain.elevation_flatness_bias = elevation_flatness_bias
	terrain.sea_level = sea_level
	terrain.load_margin_chunks = load_margin_chunks
	terrain.unload_margin_chunks = unload_margin_chunks
	terrain.chunks_created_per_frame = chunks_created_per_frame
	terrain.profiling_enabled = chunk_profiling_enabled
	terrain.max_chunk_processing_ms = max_chunk_processing_ms
	terrain.chunk_work_quantum_cells = chunk_work_quantum_cells
	terrain.max_tile_cells_per_frame = max_tile_cells_per_frame
	terrain.texture_variation_enabled = texture_variation_enabled
	terrain.texture_variation_strength = texture_variation_strength
	terrain.texture_variation_frequency = texture_variation_frequency
	terrain.organic_boundaries_enabled = organic_boundaries_enabled
	terrain.organic_edge_strength = organic_edge_strength
	terrain.organic_edge_frequency = organic_edge_frequency
	terrain.procedural_cliff_materials_enabled = procedural_cliff_materials_enabled
	terrain.organic_cliff_geometry_enabled = organic_cliff_geometry_enabled
	terrain.unified_cliff_components_enabled = unified_cliff_components_enabled
	terrain.refined_cliff_silhouettes_enabled = refined_cliff_silhouettes_enabled
	terrain.connected_cliff_contours_enabled = connected_cliff_contours_enabled
	terrain.oblique_presentation_enabled = oblique_presentation_enabled
	terrain.organic_oblique_refinement_enabled = organic_oblique_refinement_enabled
	terrain.cliff_edge_overlays_visible = cliff_edge_overlays_visible
	terrain.cliff_shadows_visible = cliff_shadows_visible
	terrain.decorations_enabled = decorations_enabled
	terrain.decoration_density = decoration_density
	terrain.decoration_clustering_strength = decoration_clustering_strength
	terrain.decoration_seed_offset = decoration_seed_offset
	terrain.environment_objects_enabled = environment_objects_enabled
	terrain.procedural_vegetation_enabled = procedural_vegetation_enabled
	terrain.environment_object_density = environment_object_density
	terrain.environment_object_seed_offset = environment_object_seed_offset
	terrain.berry_regrowth_seconds = berry_regrowth_seconds
	add_child(terrain)
	terrain.authoritative_state_changed.connect(_mark_world_dirty)
	if include_elevation_demo:
		terrain.apply_phase5a_demo()

	cursor = CursorOverlay.new()
	cursor.z_index = 100
	cursor.height_step = TerrainRenderer.HEIGHT_STEP
	cursor.height_lookup = terrain.get_world_surface_elevation
	cursor.cell_polygon_lookup = terrain.get_projected_cell_polygon
	terrain.add_child(cursor)

	editor = WorldEditorController.new()
	editor.configure(terrain)
	editor.selected_material = selected_id
	resource_interaction = ResourceInteractionController.new()
	resource_interaction.configure(terrain)
	resource_interaction.selection_changed.connect(_on_resource_selection_changed)
	terrain.resource_state_manager.inventory_changed.connect(_on_resource_inventory_changed)
	terrain.resource_state_manager.resource_changed.connect(_on_resource_state_changed)
	save_service = WorldSaveService.new()

	camera = Camera2D.new()
	camera.name = "MapCamera"
	add_child(camera)
	camera.make_current()

	_create_hud()
	_create_editor_panel()
	_update_selected_label()
	_reset_camera()
	_update_visible_world_region()


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
	_update_keyboard_camera(delta)
	if _middle_panning and not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_middle_panning = false
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
	cursor.enabled = not resource_interaction.resource_mode and not over_ui and not _middle_panning
	if over_ui:
		cursor.queue_redraw()
	_update_debug_label(pick, delta)

	var can_paint: bool = (
		not resource_interaction.resource_mode
		and not _middle_panning
		and not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
		and not over_ui)
	var pressed_button: int = (
		MOUSE_BUTTON_LEFT if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		else (MOUSE_BUTTON_RIGHT if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) else 0))
	if _stroke_button == 0 and pressed_button != 0 and can_paint:
		_stroke_button = pressed_button
		editor.begin_stroke(world_cell, pressed_button == MOUSE_BUTTON_RIGHT)
		_update_editor_summary()
	elif _stroke_button != 0:
		if Input.is_mouse_button_pressed(_stroke_button):
			if can_paint:
				editor.continue_stroke(world_cell)
		else:
			editor.end_stroke()
			_stroke_button = 0
			_update_editor_summary()


func _unhandled_input(event: InputEvent) -> void:
	var mouse_button := event as InputEventMouseButton
	if mouse_button != null:
		if (resource_interaction.resource_mode
				and mouse_button.button_index == MOUSE_BUTTON_LEFT
				and mouse_button.pressed and not _mouse_over_ui()):
			var pick: Dictionary = _screen_to_world_pick(mouse_button.position)
			resource_interaction.select_at(pick.cell)
			get_viewport().set_input_as_handled()
		elif mouse_button.button_index == MOUSE_BUTTON_MIDDLE:
			_middle_panning = mouse_button.pressed
			get_viewport().set_input_as_handled()
		elif mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_toward_cursor(CAMERA_ZOOM_FACTOR)
			get_viewport().set_input_as_handled()
		elif mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_toward_cursor(1.0 / CAMERA_ZOOM_FACTOR)
			get_viewport().set_input_as_handled()
		return

	var mouse_motion := event as InputEventMouseMotion
	if mouse_motion != null and _middle_panning:
		camera.position -= mouse_motion.relative / camera.zoom.x
		camera.force_update_scroll()
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
	elif key_event.ctrl_pressed and key == KEY_Z:
		if key_event.shift_pressed:
			editor.redo()
		else:
			editor.undo()
		_update_editor_summary()
	elif key_event.ctrl_pressed and key == KEY_Y:
		editor.redo()
		_update_editor_summary()
	elif key == KEY_BRACKETLEFT:
		editor.change_brush_size(-1)
		_refresh_brush_preview()
		_update_editor_summary()
	elif key == KEY_BRACKETRIGHT:
		editor.change_brush_size(1)
		_refresh_brush_preview()
		_update_editor_summary()
	elif key >= KEY_1 and key <= KEY_8:
		selected_id = key - KEY_1
		editor.selected_material = selected_id
		_update_selected_label()
		_update_editor_summary()
	elif key == KEY_R:
		reset_confirmation.popup_centered()
	elif key == KEY_G:
		cursor.show_grid = not cursor.show_grid
		cursor.queue_redraw()
	elif key == KEY_HOME:
		_reset_camera()
	elif key == KEY_F2:
		compact_hud_enabled = not compact_hud_enabled
		_apply_hud_mode()
	elif key == KEY_F3:
		debug_label.visible = not debug_label.visible
	elif key == KEY_F4:
		cursor.show_affected_dual_cells = not cursor.show_affected_dual_cells
		cursor.queue_redraw()
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
	elif key == KEY_H:
		height_edit_mode = not height_edit_mode
		editor.edit_mode = (
			WorldEditorController.EditMode.ELEVATION
			if height_edit_mode else WorldEditorController.EditMode.MATERIAL)
		_last_height_paint_cell = null
		_update_mode_label()
	elif key == KEY_P:
		procedural_elevation_enabled = not procedural_elevation_enabled
		terrain.set_procedural_elevation_enabled(procedural_elevation_enabled)
		_update_procedural_label()


func _update_keyboard_camera(delta: float) -> void:
	var direction := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT))
			- float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN))
			- float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
	)
	if not direction.is_zero_approx():
		camera.position += direction.normalized() * CAMERA_PAN_SPEED * delta / camera.zoom.x
		camera.force_update_scroll()


func _zoom_toward_cursor(factor: float) -> void:
	var old_zoom: float = camera.zoom.x
	var new_zoom: float = clampf(old_zoom * factor, CAMERA_MIN_ZOOM, CAMERA_MAX_ZOOM)
	if is_equal_approx(old_zoom, new_zoom):
		return

	var viewport_center: Vector2 = get_viewport_rect().size * 0.5
	var cursor_offset: Vector2 = get_viewport().get_mouse_position() - viewport_center
	var world_under_cursor: Vector2 = camera.position + cursor_offset / old_zoom
	camera.zoom = Vector2.ONE * new_zoom
	camera.position = world_under_cursor - cursor_offset / new_zoom
	camera.force_update_scroll()
	_update_zoom_label()


func _reset_camera() -> void:
	camera.position = DEMO_CENTER
	camera.zoom = Vector2.ONE
	camera.force_update_scroll()
	_middle_panning = false
	_update_zoom_label()


func _update_visible_world_region() -> void:
	var inverse_canvas: Transform2D = terrain.get_global_transform_with_canvas().affine_inverse()
	var viewport_size: Vector2 = get_viewport_rect().size
	var top_left: Vector2 = inverse_canvas * Vector2.ZERO
	var bottom_right: Vector2 = inverse_canvas * viewport_size
	var visible_rect := Rect2(top_left, bottom_right - top_left).abs()
	cursor.set_visible_world_rect(visible_rect)
	terrain.update_visible_world_rect(visible_rect)


func _screen_to_world_cell(screen_position: Vector2) -> Vector2i:
	return _screen_to_world_pick(screen_position).cell


func _screen_to_world_pick(screen_position: Vector2) -> Dictionary:
	var terrain_local: Vector2 = terrain.get_global_transform_with_canvas().affine_inverse() * screen_position
	var target_ground: bool = height_edit_mode and Input.is_key_pressed(KEY_ALT)
	return terrain.pick_world_position(terrain_local, target_ground)


func _mouse_over_ui() -> bool:
	var mouse_position: Vector2 = get_viewport().get_mouse_position()
	return (
		(hud != null and hud.visible and hud.get_global_rect().has_point(mouse_position))
		or (editor_panel != null and editor_panel.visible
			and editor_panel.get_global_rect().has_point(mouse_position))
		or (reset_confirmation != null and reset_confirmation.visible))


func _paint_height_cell_once(
		world_cell: Vector2i, adjustment: int,
		restore_generated: bool = false) -> bool:
	if _last_height_paint_cell != null and _last_height_paint_cell == world_cell:
		return false
	if restore_generated:
		terrain.restore_world_elevation(world_cell)
	else:
		terrain.set_world_elevation(
			world_cell, terrain.get_world_elevation(world_cell) + adjustment)
	_last_height_paint_cell = world_cell
	return true


func _update_selected_label() -> void:
	for material in Catalog.MATERIALS:
		if int(material["id"]) == selected_id:
			selected_label.text = "Selected: %s (key %d)" % [material["name"], selected_id + 1]
			_update_compact_hud()
			return


func _update_zoom_label() -> void:
	if zoom_label != null and camera != null:
		zoom_label.text = "Zoom: %d%%" % roundi(camera.zoom.x * 100.0)
		_update_compact_hud()


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
	replacement.apply_generation_config(generation)
	replacement.berry_regrowth_seconds = float(snapshot["resources"]["berry_regrowth_seconds"])
	replacement.load_margin_chunks = old_terrain.load_margin_chunks
	replacement.unload_margin_chunks = old_terrain.unload_margin_chunks
	replacement.chunks_created_per_frame = old_terrain.chunks_created_per_frame
	replacement.max_chunk_processing_ms = old_terrain.max_chunk_processing_ms
	replacement.chunk_work_quantum_cells = old_terrain.chunk_work_quantum_cells
	replacement.max_tile_cells_per_frame = old_terrain.max_tile_cells_per_frame
	replacement.texture_variation_enabled = texture_variation_enabled
	replacement.texture_variation_strength = texture_variation_strength
	replacement.texture_variation_frequency = texture_variation_frequency
	replacement.organic_boundaries_enabled = organic_boundaries_enabled
	replacement.organic_edge_strength = organic_edge_strength
	replacement.organic_edge_frequency = organic_edge_frequency
	replacement.procedural_cliff_materials_enabled = procedural_cliff_materials_enabled
	replacement.organic_cliff_geometry_enabled = organic_cliff_geometry_enabled
	replacement.unified_cliff_components_enabled = unified_cliff_components_enabled
	replacement.refined_cliff_silhouettes_enabled = refined_cliff_silhouettes_enabled
	replacement.connected_cliff_contours_enabled = connected_cliff_contours_enabled
	replacement.oblique_presentation_enabled = oblique_presentation_enabled
	replacement.organic_oblique_refinement_enabled = organic_oblique_refinement_enabled
	replacement.cliff_edge_overlays_visible = cliff_edge_overlays_visible
	replacement.cliff_shadows_visible = cliff_shadows_visible
	replacement.decorations_enabled = decorations_enabled
	replacement.environment_objects_enabled = environment_objects_enabled
	replacement.procedural_vegetation_enabled = procedural_vegetation_enabled
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
	terrain = replacement
	editor.configure(terrain)
	editor.reset_runtime_state()
	resource_interaction.configure(terrain)
	terrain.authoritative_state_changed.connect(_mark_world_dirty)
	terrain.resource_state_manager.inventory_changed.connect(_on_resource_inventory_changed)
	terrain.resource_state_manager.resource_changed.connect(_on_resource_state_changed)
	old_terrain.visible = false
	old_terrain.queue_free()

	world_identifier = String(saved_world["id"])
	world_display_name = String(saved_world["display_name"])
	_sync_configuration_from_terrain()
	var camera_state: Dictionary = saved_world.get("camera", {})
	if not camera_state.is_empty():
		camera.position = Vector2(float(camera_state["x"]), float(camera_state["y"]))
		camera.zoom = Vector2.ONE * float(camera_state["zoom"])
		camera.force_update_scroll()
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
	if mode_label != null:
		mode_label.text = "Editing: %s (H)" % ("Elevation" if height_edit_mode else "Material")
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
	var material_name: String = "Unknown"
	for material in Catalog.MATERIALS:
		if int(material["id"]) == selected_id:
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
			"Elevation" if height_edit_mode else "Material",
			editor.brush_size if editor != null else 1,
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
	title.text = "UNIVERSAL MASK TERRAIN"
	title.add_theme_color_override("font_color", Color("f2f4f0"))
	title.add_theme_font_size_override("font_size", 17)
	box.add_child(title)
	var instructions := Label.new()
	instructions.text = "1 Water   2 Sand   3 Dirt   4 Grass\n5 Stone   6 Snow   7 Mud   8 Gravel\n\nH: material / elevation mode   [ / ]: brush size\nLeft-drag: selected tool   Right-drag: restore / lower\nAlt + elevation edit: target logical ground cell\nQ: terrain/resource mode   Resource click: inspect\nE: designate   C: cancel   Esc: clear   F8: DEBUG complete\nCtrl+S: quicksave   Ctrl+L: quickload\nCtrl+Z: undo   Ctrl+Y or Ctrl+Shift+Z: redo\nWASD / arrows: move   Middle-drag: pan\nWheel: zoom   Home: camera reset\nR: confirm reset edits   G: grid   V: variation\nO: organic edges   D: ground details\nT: trees / objects   P: procedural elevation\nF2: compact HUD   F3: diagnostics\nF4: cell debug   F6: heights"
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
	editor_material_picker.select(selected_id)
	_add_editor_row("Material", editor_material_picker)
	editor_material_picker.item_selected.connect(func(index: int) -> void:
		selected_id = editor_material_picker.get_item_id(index)
		editor.selected_material = selected_id
		_update_selected_label()
		_update_editor_summary()
	)

	editor_mode_picker = OptionButton.new()
	editor_mode_picker.add_item("Material", WorldEditorController.EditMode.MATERIAL)
	editor_mode_picker.add_item("Elevation", WorldEditorController.EditMode.ELEVATION)
	_add_editor_row("Mode", editor_mode_picker)
	editor_mode_picker.item_selected.connect(func(index: int) -> void:
		editor.edit_mode = editor_mode_picker.get_item_id(index)
		height_edit_mode = editor.edit_mode == WorldEditorController.EditMode.ELEVATION
		_update_mode_label()
		_update_editor_summary()
	)

	editor_shape_picker = OptionButton.new()
	editor_shape_picker.add_item("Circle", WorldEditorController.BrushShape.CIRCLE)
	editor_shape_picker.add_item("Square", WorldEditorController.BrushShape.SQUARE)
	_add_editor_row("Shape", editor_shape_picker)
	editor_shape_picker.item_selected.connect(func(index: int) -> void:
		editor.brush_shape = editor_shape_picker.get_item_id(index)
		_refresh_brush_preview()
		_update_editor_summary()
	)

	editor_size_picker = OptionButton.new()
	for size in WorldEditorController.BRUSH_SIZES:
		editor_size_picker.add_item("%d cells" % size, size)
	_add_editor_row("Size", editor_size_picker)
	editor_size_picker.item_selected.connect(func(index: int) -> void:
		editor.brush_size = editor_size_picker.get_item_id(index)
		_refresh_brush_preview()
		_update_editor_summary()
	)

	editor_restore_material_toggle = CheckButton.new()
	editor_restore_material_toggle.text = "Restore generated material"
	editor_content.add_child(editor_restore_material_toggle)
	editor_restore_material_toggle.toggled.connect(func(enabled: bool) -> void:
		editor.restore_material = enabled
		_update_editor_summary()
	)

	editor_elevation_picker = OptionButton.new()
	editor_elevation_picker.add_item("Raise", WorldEditorController.ElevationTool.RAISE)
	editor_elevation_picker.add_item("Lower", WorldEditorController.ElevationTool.LOWER)
	editor_elevation_picker.add_item("Set height", WorldEditorController.ElevationTool.SET_HEIGHT)
	editor_elevation_picker.add_item("Flatten (sample)", WorldEditorController.ElevationTool.FLATTEN)
	editor_elevation_picker.add_item("Restore generated", WorldEditorController.ElevationTool.RESTORE)
	_add_editor_row("Elevation", editor_elevation_picker)
	editor_elevation_picker.item_selected.connect(func(index: int) -> void:
		editor.elevation_tool = editor_elevation_picker.get_item_id(index)
		_update_editor_summary()
	)

	editor_target_picker = OptionButton.new()
	for elevation in range(4):
		editor_target_picker.add_item("Level %d" % elevation, elevation)
	_add_editor_row("Target", editor_target_picker)
	editor_target_picker.item_selected.connect(func(index: int) -> void:
		editor.target_elevation = editor_target_picker.get_item_id(index)
		_update_editor_summary()
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
		_update_editor_summary()
	)
	redo_button.pressed.connect(func() -> void:
		editor.redo()
		_update_editor_summary()
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
		_update_editor_summary()
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
	var shape_name: String = (
		"Circle" if editor.brush_shape == WorldEditorController.BrushShape.CIRCLE else "Square")
	editor_summary_label.text = "%s %d  •  Undo %d  •  Redo %d" % [
		shape_name, editor.brush_size, editor.get_undo_count(), editor.get_redo_count()]
	undo_button.disabled = not editor.can_undo()
	redo_button.disabled = not editor.can_redo()
	_select_option_id(editor_material_picker, editor.selected_material)
	_select_option_id(editor_mode_picker, editor.edit_mode)
	_select_option_id(editor_shape_picker, editor.brush_shape)
	_select_option_id(editor_size_picker, editor.brush_size)
	_select_option_id(editor_elevation_picker, editor.elevation_tool)
	_select_option_id(editor_target_picker, editor.target_elevation)
	editor_restore_material_toggle.set_pressed_no_signal(editor.restore_material)
	_update_compact_hud()


func _select_option_id(option: OptionButton, item_id: int) -> void:
	if option == null:
		return
	var index: int = option.get_item_index(item_id)
	if index >= 0:
		option.select(index)

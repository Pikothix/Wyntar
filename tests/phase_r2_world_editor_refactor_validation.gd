extends SceneTree
## Focused R2 checks for editor-owned state, shortcuts, pointer strokes, HUD
## synchronization, and the central UI/resource/camera priority gates.

const MainScene = preload("res://main.tscn")
const WorldEditorController = preload("res://scripts/world_editor_controller.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main = MainScene.instantiate()
	main.include_elevation_demo = false
	main.load_margin_chunks = 0
	main.unload_margin_chunks = 1
	main.chunks_created_per_frame = 8
	main.max_chunk_processing_ms = 10.0
	main.chunk_work_quantum_cells = 256
	main.max_tile_cells_per_frame = 1024
	main.organic_cliff_geometry_enabled = false
	main.decorations_enabled = false
	main.environment_objects_enabled = false
	root.add_child(main)
	await process_frame

	_validate_state_interface(main)
	_validate_shortcut_routing(main)
	_validate_pointer_strokes(main)
	_validate_input_priority(main)

	main.queue_free()
	if failures.is_empty():
		print("PHASE_R2_WORLD_EDITOR_REFACTOR_VALIDATION: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("PHASE_R2_WORLD_EDITOR_REFACTOR_VALIDATION: FAIL (%d)" % failures.size())
		quit(1)


func _validate_state_interface(main) -> void:
	var counter := {"value": 0}
	main.editor.state_changed.connect(func() -> void: counter["value"] += 1)
	main.editor.set_brush_shape(WorldEditorController.BrushShape.SQUARE)
	main.editor.set_brush_size(5)
	main.editor.set_elevation_tool(WorldEditorController.ElevationTool.SET_HEIGHT)
	main.editor.set_target_elevation(2)
	main.editor.set_restore_material(true)
	var state: Dictionary = main.editor.get_state_snapshot()
	_expect(int(counter["value"]) == 5,
		"editor setters emit one presentation-state notification each")
	_expect(int(state["brush_shape"]) == WorldEditorController.BrushShape.SQUARE
		and int(state["brush_size"]) == 5
		and int(state["elevation_tool"]) == WorldEditorController.ElevationTool.SET_HEIGHT
		and int(state["target_elevation"]) == 2
		and bool(state["restore_material"]),
		"state snapshot exposes editor presentation state without duplicating ownership")
	_expect(main.cursor.brush_cells.size() == 25,
		"state notification refreshes the square brush preview")
	_expect(main.editor_summary_label.text.contains("Square 5"),
		"state notification refreshes editor HUD summary")


func _validate_shortcut_routing(main) -> void:
	main.editor.set_restore_material(false)
	var material_key := _key(KEY_3)
	main._unhandled_key_input(material_key)
	_expect(main.editor.selected_material == 2
		and main.selected_label.text.contains("key 3"),
		"material shortcut is handled by editor and reflected by HUD")
	var initial_size: int = main.editor.brush_size
	main._unhandled_key_input(_key(KEY_BRACKETRIGHT))
	_expect(main.editor.brush_size > initial_size, "brush-size shortcut is editor-owned")
	main._unhandled_key_input(_key(KEY_H))
	_expect(main.editor.edit_mode == WorldEditorController.EditMode.ELEVATION
		and main.mode_label.text.contains("Elevation"),
		"mode shortcut is editor-owned and reflected by HUD")


func _validate_pointer_strokes(main) -> void:
	var material_a := Vector2i(70, 70)
	var material_b := Vector2i(72, 70)
	main.editor.set_edit_mode(WorldEditorController.EditMode.MATERIAL)
	main.editor.set_selected_material(6)
	main.editor.set_brush_shape(WorldEditorController.BrushShape.CIRCLE)
	main.editor.set_brush_size(1)
	main.editor.update_pointer_stroke(material_a, true, true, false)
	main.editor.update_pointer_stroke(material_b, true, true, false)
	main.editor.update_pointer_stroke(material_b, true, false, false)
	_expect(main.terrain.get_world_cell(material_a) == 6
		and main.terrain.get_world_cell(material_b) == 6,
		"left drag preserves rasterized material painting")
	_expect(main.editor.can_undo(), "completed pointer stroke enters editor history")
	main.editor.handle_shortcut(_key(KEY_Z, true))
	_expect(main.terrain.get_world_material_override_state(material_a).has_override == false,
		"Ctrl+Z preserves editor undo")
	main.editor.handle_shortcut(_key(KEY_Y, true))
	_expect(main.terrain.get_world_cell(material_a) == 6, "Ctrl+Y preserves editor redo")

	main.editor.update_pointer_stroke(material_a, true, false, true)
	main.editor.update_pointer_stroke(material_a, true, false, false)
	_expect(not bool(main.terrain.get_world_material_override_state(material_a).has_override),
		"right pointer stroke preserves generated-material restore")

	var height_cell := Vector2i(80, 80)
	var starting_height: int = main.terrain.get_world_elevation(height_cell)
	main.editor.set_edit_mode(WorldEditorController.EditMode.ELEVATION)
	main.editor.set_elevation_tool(WorldEditorController.ElevationTool.RAISE)
	main.editor.update_pointer_stroke(height_cell, true, true, false)
	main.editor.update_pointer_stroke(height_cell, true, false, false)
	_expect(main.terrain.get_world_elevation(height_cell) == mini(starting_height + 1, 3),
		"left pointer stroke preserves elevation raising")
	main.editor.update_pointer_stroke(height_cell, true, false, true)
	main.editor.update_pointer_stroke(height_cell, true, false, false)
	_expect(main.terrain.get_world_elevation(height_cell) == maxi(starting_height, 0),
		"right pointer stroke preserves alternate elevation lowering")


func _validate_input_priority(main) -> void:
	var hud_point: Vector2 = main.hud.get_global_rect().get_center()
	_expect(main._screen_position_over_ui(hud_point), "HUD coordinates block editor painting")
	_expect(not main._can_editor_paint(true), "UI capture has priority over editor operations")

	main.resource_interaction.set_resource_mode(true)
	_expect(not main._can_editor_paint(false), "resource mode has priority over terrain editing")
	var camera_before: Vector2 = main.camera.position
	var resource_click := InputEventMouseButton.new()
	resource_click.button_index = MOUSE_BUTTON_LEFT
	resource_click.pressed = true
	resource_click.position = Vector2.ZERO
	main._unhandled_input(resource_click)
	_expect(main.camera.position == camera_before and not main.camera.is_middle_panning(),
		"resource left click is routed before camera interaction")

	main.resource_interaction.set_resource_mode(false)
	var middle_down := InputEventMouseButton.new()
	middle_down.button_index = MOUSE_BUTTON_MIDDLE
	middle_down.pressed = true
	main._unhandled_input(middle_down)
	_expect(main.camera.is_middle_panning() and not main._can_editor_paint(false),
		"camera middle drag blocks editor painting")
	middle_down.pressed = false
	main._unhandled_input(middle_down)
	_expect(not main.camera.is_middle_panning(), "camera receives middle release")


func _key(keycode: int, ctrl_pressed: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.ctrl_pressed = ctrl_pressed
	return event


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

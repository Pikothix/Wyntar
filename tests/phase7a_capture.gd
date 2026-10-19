extends SceneTree
## Reproducible Phase 7A captures of the toolbar, logical footprints,
## elevation sculpting, and the visible result of an undo transaction.

const OUTPUT_DIR := "res://screenshots"
const EditorController = preload("res://scripts/world_editor_controller.gd")

var demo
var terrain
var editor


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    DisplayServer.window_set_size(Vector2i(1280, 720))
    demo = load("res://main.tscn").instantiate()
    root.add_child(demo)
    await _wait_frames(6)
    terrain = demo.terrain
    editor = demo.editor
    _verify_existing_controls()
    Input.warp_mouse(demo.editor_panel.get_global_rect().get_center())
    await process_frame
    assert(demo._mouse_over_ui(), "Editor controls must block world painting")
    demo.camera.position = Vector2(Vector2i(16, 16) * terrain.TILE_SIZE)
    demo.camera.zoom = Vector2.ONE
    demo.camera.force_update_scroll()
    demo._update_visible_world_region()
    await _wait_until_streaming_idle()

    editor.brush_shape = EditorController.BrushShape.CIRCLE
    editor.brush_size = 5
    for zoom in [0.5, 1.0, 3.0]:
        demo.camera.zoom = Vector2.ONE * zoom
        demo.camera.force_update_scroll()
        _show_brush(Vector2i(16, 16))
        demo._update_editor_summary()
        await _capture("phase7a_circle_brush_%sx" % String.num(zoom, 1).replace(".", "_"))
        assert(demo.cursor.selected_cell == Vector2i(16, 16),
            "Projected selection must remain stable at zoom %s" % zoom)

    demo.camera.zoom = Vector2.ONE
    demo.camera.force_update_scroll()
    editor.brush_shape = EditorController.BrushShape.SQUARE
    editor.brush_size = 7
    _show_brush(Vector2i(16, 16))
    demo._update_editor_summary()
    await _capture("phase7a_square_brush_footprint")

    editor.edit_mode = EditorController.EditMode.MATERIAL
    editor.selected_material = 5
    editor.brush_shape = EditorController.BrushShape.CIRCLE
    editor.brush_size = 11
    editor.begin_stroke(Vector2i(11, 14))
    editor.end_stroke()
    _show_brush(Vector2i(11, 14))
    demo._update_editor_summary()
    await _wait_for_edit_refresh()
    await _capture("phase7a_large_material_brush")

    editor.edit_mode = EditorController.EditMode.ELEVATION
    demo.height_edit_mode = true
    editor.elevation_tool = EditorController.ElevationTool.SET_HEIGHT
    editor.target_elevation = 3
    editor.brush_shape = EditorController.BrushShape.CIRCLE
    editor.brush_size = 5
    editor.begin_stroke(Vector2i(16, 16))
    editor.end_stroke()
    _show_brush(Vector2i(16, 16))
    demo._update_editor_summary()
    await _wait_frames(4)
    await _capture("phase7a_elevation_sculpt_before_undo")

    editor.undo()
    demo._update_editor_summary()
    await _wait_frames(4)
    await _capture("phase7a_elevation_sculpt_after_undo")

    editor.elevation_tool = EditorController.ElevationTool.FLATTEN
    editor.brush_size = 5
    editor.begin_stroke(Vector2i(20, 16))
    editor.end_stroke()
    _show_brush(Vector2i(20, 16))
    demo._update_editor_summary()
    await _capture("phase7a_flatten_sampled_height")

    var collapse_button: Button = demo.editor_panel.get_child(0).get_child(0)
    collapse_button.pressed.emit()
    await _capture("phase7a_editor_collapsed")
    collapse_button.pressed.emit()
    demo.compact_hud_enabled = false
    demo._apply_hud_mode()
    await _capture("phase7a_editor_expanded")
    print("PHASE7A_GRAPHICAL_CAPTURE PASS")
    quit(0)


func _show_brush(cell: Vector2i) -> void:
    var projected_center: Vector2 = terrain.get_projected_cell_rect(cell).get_center()
    var screen_position: Vector2 = (
        get_root().get_visible_rect().size * 0.5
        + (projected_center - demo.camera.position) * demo.camera.zoom.x)
    Input.warp_mouse(screen_position)
    demo.cursor.selected_cell = cell
    demo.cursor.selected_height = terrain.get_world_surface_elevation(cell)
    demo.cursor.selected_is_cliff = false
    demo.cursor.brush_cells = editor.get_brush_cells(cell)
    demo.cursor.queue_redraw()


func _verify_existing_controls() -> void:
    var compact_before: bool = demo.compact_hud_enabled
    _press_key(KEY_F2)
    assert(demo.compact_hud_enabled != compact_before, "F2 must toggle compact HUD")
    _press_key(KEY_F2)
    var affected_before: bool = demo.cursor.show_affected_dual_cells
    _press_key(KEY_F4)
    assert(demo.cursor.show_affected_dual_cells != affected_before, "F4 must retain diagnostics")
    _press_key(KEY_F4)
    var camera_before: Vector2 = demo.camera.position
    _press_key(KEY_HOME)
    assert(demo.camera.position != camera_before or demo.camera.position == demo.DEMO_CENTER,
        "Home must retain camera reset")


func _press_key(keycode: Key) -> void:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.pressed = true
    demo._unhandled_key_input(event)


func _capture(label: String) -> void:
    await _wait_frames(3)
    var error: Error = root.get_texture().get_image().save_png(
        "%s/%s.png" % [OUTPUT_DIR, label])
    assert(error == OK, "Could not save %s" % label)


func _wait_until_streaming_idle(max_frames: int = 1200) -> void:
    for _frame in range(max_frames):
        await process_frame
        if terrain.get_pending_chunk_count() == 0:
            return
    push_warning("Streaming did not become idle")


func _wait_for_edit_refresh(max_frames: int = 120) -> void:
    for _frame in range(max_frames):
        await process_frame
        if (terrain.get_pending_edit_cell_count() == 0
                and terrain.get_pending_edit_environment_chunk_count() == 0):
            return
    push_warning("Edit refresh did not become idle")


func _wait_frames(count: int) -> void:
    for _frame in range(count):
        await process_frame

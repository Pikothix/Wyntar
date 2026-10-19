extends SceneTree
## Focused Phase 7A validation for logical brushes, interpolated strokes,
## authoritative override-state history, and cross-boundary batch edits.

const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")
const WorldEditorController = preload("res://scripts/world_editor_controller.gd")

var failures: Array[String] = []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var terrain = TerrainRenderer.new()
    root.add_child(terrain)
    await process_frame
    var editor = WorldEditorController.new()
    editor.configure(terrain)

    var circle_counts: Dictionary = {1: 1, 3: 5, 5: 13, 7: 29, 11: 81}
    for size in WorldEditorController.BRUSH_SIZES:
        editor.brush_size = size
        editor.brush_shape = WorldEditorController.BrushShape.SQUARE
        _expect(editor.get_brush_cells(Vector2i(-32, 31)).size() == size * size,
            "%d-cell square footprint" % size)
        editor.brush_shape = WorldEditorController.BrushShape.CIRCLE
        _expect(editor.get_brush_cells(Vector2i(-32, 31)).size() == int(circle_counts[size]),
            "%d-cell circular footprint" % size)

    editor.brush_size = 1
    editor.selected_material = 5
    editor.begin_stroke(Vector2i(-2, 31))
    editor.continue_stroke(Vector2i(2, 33))
    _expect(editor.end_stroke(), "interpolated material stroke committed")
    for cell in [Vector2i(-2, 31), Vector2i(-1, 32), Vector2i(0, 32), Vector2i(1, 33), Vector2i(2, 33)]:
        _expect(terrain.get_world_cell(cell) == 5, "Bresenham stroke includes %s" % cell)
    _expect(editor.undo(), "material stroke undo")
    _expect(not terrain.get_world_material_override_state(Vector2i(0, 32)).has_override,
        "undo restores absent material override")
    _expect(editor.redo(), "material stroke redo")
    _expect(terrain.get_world_material_override_state(Vector2i(0, 32)).has_override,
        "redo restores explicit material override")
    editor.restore_material = true
    editor.begin_stroke(Vector2i(0, 32))
    editor.end_stroke()
    _expect(not terrain.get_world_material_override_state(Vector2i(0, 32)).has_override,
        "generated material restoration removes sparse override")
    editor.restore_material = false

    var height_cell := Vector2i(31, -32)
    var initial_height: int = terrain.get_world_elevation(height_cell)
    editor.edit_mode = WorldEditorController.EditMode.ELEVATION
    editor.elevation_tool = WorldEditorController.ElevationTool.RAISE
    editor.begin_stroke(height_cell)
    editor.continue_stroke(height_cell + Vector2i.RIGHT)
    editor.continue_stroke(height_cell)
    editor.end_stroke()
    _expect(terrain.get_world_elevation(height_cell) == mini(initial_height + 1, 3),
        "raise changes a cell at most once per stroke")
    editor.undo()
    _expect(terrain.get_world_elevation(height_cell) == initial_height, "height undo exact")
    editor.elevation_tool = WorldEditorController.ElevationTool.LOWER
    editor.begin_stroke(height_cell)
    editor.continue_stroke(height_cell)
    editor.end_stroke()
    _expect(terrain.get_world_elevation(height_cell) == maxi(initial_height - 1, 0),
        "lower changes a cell at most once per stroke")

    editor.elevation_tool = WorldEditorController.ElevationTool.SET_HEIGHT
    editor.target_elevation = 3
    editor.begin_stroke(Vector2i(32, -32))
    editor.end_stroke()
    _expect(terrain.get_world_elevation(Vector2i(32, -32)) == 3, "set-height exact level")

    editor.elevation_tool = WorldEditorController.ElevationTool.FLATTEN
    editor.brush_size = 3
    var flatten_center := Vector2i(-33, -33)
    var sampled_height: int = terrain.get_world_elevation(flatten_center)
    editor.begin_stroke(flatten_center)
    editor.end_stroke()
    for cell in editor.get_brush_cells(flatten_center):
        _expect(terrain.get_world_elevation(cell) == sampled_height, "flatten uses sampled target")

    editor.elevation_tool = WorldEditorController.ElevationTool.RESTORE
    editor.brush_size = 1
    editor.begin_stroke(Vector2i(32, -32))
    editor.end_stroke()
    _expect(not terrain.get_world_elevation_override_state(Vector2i(32, -32)).has_override,
        "generated elevation restoration removes sparse override")

    editor.edit_mode = WorldEditorController.EditMode.MATERIAL
    editor.selected_material = 1
    editor.begin_stroke(Vector2i(6, 6))
    editor.end_stroke()
    editor.edit_mode = WorldEditorController.EditMode.ELEVATION
    editor.elevation_tool = WorldEditorController.ElevationTool.SET_HEIGHT
    editor.target_elevation = 2
    editor.begin_stroke(Vector2i(6, 6))
    editor.end_stroke()
    for _cycle in range(3):
        _expect(editor.undo(), "mixed edit repeated height undo")
        _expect(editor.undo(), "mixed edit repeated material undo")
        _expect(editor.redo(), "mixed edit repeated material redo")
        _expect(editor.redo(), "mixed edit repeated height redo")
    editor.undo()
    editor.edit_mode = WorldEditorController.EditMode.MATERIAL
    editor.selected_material = 7
    editor.begin_stroke(Vector2i(7, 6))
    editor.end_stroke()
    _expect(not editor.redo(), "new edit clears redo branch")

    var explicit_cell := Vector2i(12, -9)
    var generated_material: int = terrain.generator.get_cell(explicit_cell)
    terrain.apply_world_edit_states([{
        "cell": explicit_cell, "kind": "material",
        "state": {"has_override": true, "value": generated_material},
    }])
    _expect(terrain.get_world_material_override_state(explicit_cell).has_override,
        "explicit generated-value override state remains distinguishable")

    var water_cell := Vector2i(14, 14)
    var water_ground_height: int = terrain.get_world_elevation(water_cell)
    terrain.apply_world_edit_states([{
        "cell": water_cell, "kind": "material",
        "state": {"has_override": true, "value": 0},
    }])
    _expect(terrain.get_world_elevation(water_cell) == water_ground_height,
        "water-boundary painting preserves ground elevation")
    _expect(terrain.get_world_surface_elevation(water_cell) == terrain.sea_level,
        "painting water alone uses the configured liquid plane")
    _expect(terrain.get_world_visible_liquid_elevation(water_cell) == terrain.sea_level,
        "painting material alone does not mark ground as explicitly raised")

    _expect(editor.reset_all_edits(), "reset creates a transaction")
    _expect(terrain.get_override_count() == 0 and terrain.get_height_override_count() == 0,
        "reset restores generated terrain")
    _expect(editor.undo(), "reset is undoable")
    _expect(terrain.get_override_count() > 0 or terrain.get_height_override_count() > 0,
        "undo reset restores sparse edits")

    terrain.update_visible_world_rect(Rect2(Vector2(-640, -360), Vector2(1280, 720)))
    await _wait_until_streaming_idle(terrain)
    var persistent_cell := Vector2i(2, 2)
    terrain.apply_world_edit_states([{
        "cell": persistent_cell, "kind": "elevation",
        "state": {"has_override": true, "value": 3},
    }])
    _expect(terrain.get_pending_edit_environment_chunk_count() > 0,
        "terrain edit queues bounded environmental-object refresh")
    terrain.update_visible_world_rect(Rect2(Vector2(200000, 200000), Vector2(1280, 720)))
    await process_frame
    terrain.update_visible_world_rect(Rect2(Vector2(-640, -360), Vector2(1280, 720)))
    await _wait_until_streaming_idle(terrain)
    _expect(terrain.get_world_elevation(persistent_cell) == 3,
        "authoritative edit survives chunk unload and reload")

    terrain.queue_free()
    if failures.is_empty():
        print("PHASE7A_VALIDATION: PASS")
        quit(0)
    else:
        for failure in failures:
            push_error(failure)
        print("PHASE7A_VALIDATION: FAIL (%d)" % failures.size())
        quit(1)


func _expect(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)


func _wait_until_streaming_idle(terrain, max_frames: int = 1200) -> void:
    for _frame in range(max_frames):
        await process_frame
        if (terrain.get_pending_chunk_count() == 0
                and terrain.get_pending_edit_cell_count() == 0
                and terrain.get_pending_edit_environment_chunk_count() == 0):
            return
    failures.append("streaming and edit refresh did not become idle")

extends RefCounted
## Owns transient editor tool state and bounded command history. TerrainWorld
## remains authoritative; this controller only submits state transitions through
## TerrainRenderer and never stores a second editable copy of the world.

const BRUSH_SIZES: Array[int] = [1, 3, 5, 7, 11]
const HISTORY_LIMIT: int = 50

enum EditMode { MATERIAL, ELEVATION }
enum BrushShape { CIRCLE, SQUARE }
enum ElevationTool { RAISE, LOWER, SET_HEIGHT, FLATTEN, RESTORE }

var terrain
var edit_mode: EditMode = EditMode.MATERIAL
var brush_shape: BrushShape = BrushShape.CIRCLE
var brush_size: int = 1
var selected_material: int = 3
var elevation_tool: ElevationTool = ElevationTool.RAISE
var target_elevation: int = 0
var restore_material: bool = false

var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _stroke_changes: Dictionary = {} # "kind:x:y" -> authoritative state change
var _pending_states: Dictionary = {} # changed entries awaiting one batched apply
var _stroke_visited: Dictionary = {} # Vector2i -> true for raise/lower once-per-stroke
var _flatten_height: int = 0
var _stroke_active: bool = false
var _last_sampled_cell: Vector2i
var _stroke_restore_material: bool = false
var _stroke_elevation_tool: ElevationTool = ElevationTool.RAISE


func configure(terrain_renderer) -> void:
    terrain = terrain_renderer


func get_brush_cells(center: Vector2i) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    var radius: int = brush_size / 2
    for y in range(-radius, radius + 1):
        for x in range(-radius, radius + 1):
            if brush_shape == BrushShape.CIRCLE and x * x + y * y > radius * radius:
                continue
            result.append(center + Vector2i(x, y))
    return result


func change_brush_size(direction: int) -> void:
    var index: int = BRUSH_SIZES.find(brush_size)
    brush_size = BRUSH_SIZES[clampi(index + direction, 0, BRUSH_SIZES.size() - 1)]


func begin_stroke(cell: Vector2i, alternate_action: bool = false) -> void:
    _stroke_active = true
    _stroke_changes.clear()
    _pending_states.clear()
    _stroke_visited.clear()
    _last_sampled_cell = cell
    _stroke_restore_material = restore_material or alternate_action
    _stroke_elevation_tool = ElevationTool.LOWER if alternate_action else elevation_tool
    if edit_mode == EditMode.ELEVATION and _stroke_elevation_tool == ElevationTool.FLATTEN:
        _flatten_height = terrain.get_world_elevation(cell)
        target_elevation = _flatten_height
    _apply_sample(cell)


func continue_stroke(cell: Vector2i) -> void:
    if not _stroke_active:
        return
    for interpolated_cell in _raster_line(_last_sampled_cell, cell):
        _apply_sample(interpolated_cell)
    _last_sampled_cell = cell


func end_stroke() -> bool:
    if not _stroke_active:
        return false
    _stroke_active = false
    return _commit_pending_transaction()


func cancel_stroke() -> void:
    if _stroke_active and not _stroke_changes.is_empty():
        terrain.apply_world_edit_states(_states_for_transaction(
            {"changes": _stroke_changes.values()}, false))
    _stroke_active = false
    _stroke_changes.clear()
    _pending_states.clear()
    _stroke_visited.clear()


func undo() -> bool:
    if _undo_stack.is_empty() or _stroke_active:
        return false
    var transaction: Dictionary = _undo_stack.pop_back()
    terrain.apply_world_edit_states(_states_for_transaction(transaction, false))
    _redo_stack.append(transaction)
    return true


func redo() -> bool:
    if _redo_stack.is_empty() or _stroke_active:
        return false
    var transaction: Dictionary = _redo_stack.pop_back()
    terrain.apply_world_edit_states(_states_for_transaction(transaction, true))
    _undo_stack.append(transaction)
    return true


func reset_all_edits() -> bool:
    if _stroke_active:
        end_stroke()
    _stroke_changes.clear()
    for cell in terrain.get_all_override_cells():
        if terrain.get_world_material_override_state(cell).has_override:
            _record_change(cell, "material", {"has_override": false, "value": 0})
        if terrain.get_world_elevation_override_state(cell).has_override:
            _record_change(cell, "elevation", {"has_override": false, "value": 0})
    _flush_pending_preview()
    return _commit_pending_transaction()


func can_undo() -> bool:
    return not _undo_stack.is_empty()


func can_redo() -> bool:
    return not _redo_stack.is_empty()


func get_undo_count() -> int:
    return _undo_stack.size()


func get_redo_count() -> int:
    return _redo_stack.size()


func reset_runtime_state() -> void:
    ## Loading replaces authoritative state; prior-world strokes and history
    ## must not be replayable into the reconstructed world.
    _stroke_active = false
    _stroke_changes.clear()
    _pending_states.clear()
    _stroke_visited.clear()
    _undo_stack.clear()
    _redo_stack.clear()


func _apply_sample(center: Vector2i) -> void:
    for cell in get_brush_cells(center):
        if edit_mode == EditMode.MATERIAL:
            var material_state := {"has_override": not _stroke_restore_material, "value": selected_material}
            _record_change(cell, "material", material_state)
        else:
            _apply_elevation_tool(cell)
    _flush_pending_preview()


func _apply_elevation_tool(cell: Vector2i) -> void:
    var state: Dictionary
    if _stroke_elevation_tool == ElevationTool.RESTORE:
        state = {"has_override": false, "value": 0}
    elif _stroke_elevation_tool == ElevationTool.SET_HEIGHT:
        state = {"has_override": true, "value": target_elevation}
    elif _stroke_elevation_tool == ElevationTool.FLATTEN:
        state = {"has_override": true, "value": _flatten_height}
    else:
        if _stroke_visited.has(cell):
            return
        _stroke_visited[cell] = true
        var adjustment: int = 1 if _stroke_elevation_tool == ElevationTool.RAISE else -1
        state = {
            "has_override": true,
            "value": clampi(terrain.get_world_elevation(cell) + adjustment, 0, 3),
        }
    _record_change(cell, "elevation", state)


func _record_change(cell: Vector2i, kind: String, after: Dictionary) -> void:
    var key: String = "%s:%d:%d" % [kind, cell.x, cell.y]
    if not _stroke_changes.has(key):
        var before: Dictionary = (
            terrain.get_world_material_override_state(cell)
            if kind == "material"
            else terrain.get_world_elevation_override_state(cell))
        _stroke_changes[key] = {
            "cell": cell, "kind": kind, "before": before, "after": after.duplicate(),
        }
    else:
        _stroke_changes[key]["after"] = after.duplicate()
    _pending_states[key] = {
        "cell": cell, "kind": kind, "state": after.duplicate(),
    }


func _flush_pending_preview() -> void:
    var states: Array[Dictionary] = []
    states.assign(_pending_states.values())
    _pending_states.clear()
    terrain.apply_world_edit_states(states)


func _commit_pending_transaction() -> bool:
    var changes: Array[Dictionary] = []
    for change in _stroke_changes.values():
        if change.before != change.after:
            changes.append(change)
    _stroke_changes.clear()
    _pending_states.clear()
    _stroke_visited.clear()
    if changes.is_empty():
        return false
    _undo_stack.append({"changes": changes})
    if _undo_stack.size() > HISTORY_LIMIT:
        _undo_stack.pop_front()
    _redo_stack.clear()
    return true


func _states_for_transaction(transaction: Dictionary, use_after: bool) -> Array[Dictionary]:
    var states: Array[Dictionary] = []
    for change in transaction.changes:
        states.append({
            "cell": change.cell,
            "kind": change.kind,
            "state": change.after if use_after else change.before,
        })
    return states


func _raster_line(start: Vector2i, finish: Vector2i) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    var x: int = start.x
    var y: int = start.y
    var dx: int = absi(finish.x - start.x)
    var dy: int = -absi(finish.y - start.y)
    var step_x: int = 1 if x < finish.x else -1
    var step_y: int = 1 if y < finish.y else -1
    var error: int = dx + dy
    while true:
        result.append(Vector2i(x, y))
        if x == finish.x and y == finish.y:
            break
        var doubled_error: int = error * 2
        if doubled_error >= dy:
            error += dy
            x += step_x
        if doubled_error <= dx:
            error += dx
            y += step_y
    return result

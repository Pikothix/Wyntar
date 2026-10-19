extends SceneTree
## Phase 7A edit-latency benchmark. Each scenario records complete frame time,
## synchronous edit refresh cost, changed cells, dirty chunks, and scheduler overruns.

const SAMPLE_FRAMES: int = 60
const EditorController = preload("res://scripts/world_editor_controller.gd")

var demo
var terrain
var editor


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    DisplayServer.window_set_size(Vector2i(1280, 720))
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    demo = load("res://main.tscn").instantiate()
    root.add_child(demo)
    await _wait_frames(5)
    terrain = demo.terrain
    editor = demo.editor
    demo.hud.visible = false
    demo.editor_panel.visible = false
    demo.camera.position = Vector2(Vector2i(16, 16) * terrain.TILE_SIZE)
    demo.camera.force_update_scroll()
    demo._update_visible_world_region()
    await _wait_until_streaming_idle()

    await _run_baseline("baseline_static", false)
    await _run_continuous("single_cell", 1, false, false, Vector2i(-18, 8), 5)
    await _run_continuous("small_brush", 3, false, false, Vector2i(-18, 12), 4)
    await _run_continuous("large_brush", 11, false, false, Vector2i(-18, 18), 2)
    await _run_continuous("elevation_sculpt", 5, true, false, Vector2i(-18, 24), 0)
    await _run_continuous("chunk_boundary", 7, false, false, Vector2i(28, -2), 6)
    demo.camera.position = Vector2(Vector2i(16, 16) * terrain.TILE_SIZE)
    await _run_baseline("baseline_camera", true)
    demo.camera.position = Vector2(Vector2i(16, 16) * terrain.TILE_SIZE)
    await _run_continuous("painting_with_camera", 5, false, true, Vector2i(-18, 28), 7)
    await _run_undo_redo()
    print("PHASE7A_BENCHMARK PASS")
    quit(0)


func _run_continuous(
        label: String, brush_size: int, elevation: bool, move_camera: bool,
        origin: Vector2i = Vector2i(-24, 8), material_id: int = 5) -> void:
    editor.brush_size = brush_size
    editor.brush_shape = EditorController.BrushShape.CIRCLE
    editor.edit_mode = (
        EditorController.EditMode.ELEVATION if elevation else EditorController.EditMode.MATERIAL)
    editor.selected_material = material_id
    editor.elevation_tool = EditorController.ElevationTool.SET_HEIGHT
    editor.target_elevation = 3
    var frame_times: Array[float] = []
    var edit_times: Array[float] = []
    var refresh_times: Array[float] = []
    var environment_times: Array[float] = []
    var dirty_cells_total: int = 0
    var maximum_dirty_chunks: int = 0
    var overruns_start: int = terrain.chunk_processing_overrun_frames
    var previous_usec: int = Time.get_ticks_usec()
    editor.begin_stroke(origin)
    for frame_index in range(SAMPLE_FRAMES):
        var cell := origin + Vector2i(frame_index, roundi(sin(frame_index * 0.35) * 3.0))
        var edit_start: int = Time.get_ticks_usec()
        editor.continue_stroke(cell)
        edit_times.append(float(Time.get_ticks_usec() - edit_start) / 1000.0)
        refresh_times.append(float(terrain.last_edit_refresh_usec) / 1000.0)
        dirty_cells_total += terrain.last_edit_dirty_cell_count
        maximum_dirty_chunks = maxi(maximum_dirty_chunks, terrain.last_edit_dirty_chunk_count)
        if move_camera:
            demo.camera.position += Vector2(6.0, 2.0)
            demo.camera.force_update_scroll()
        await process_frame
        environment_times.append(float(terrain.last_edit_environment_refresh_usec) / 1000.0)
        var now_usec: int = Time.get_ticks_usec()
        frame_times.append(float(now_usec - previous_usec) / 1000.0)
        previous_usec = now_usec
    editor.end_stroke()
    await _drain_edit_refresh()
    _print_metrics(
        label, frame_times, edit_times, refresh_times, environment_times, dirty_cells_total,
        maximum_dirty_chunks, terrain.chunk_processing_overrun_frames - overruns_start)


func _run_baseline(label: String, move_camera: bool) -> void:
    var frame_times: Array[float] = []
    var previous_usec: int = Time.get_ticks_usec()
    var overruns_start: int = terrain.chunk_processing_overrun_frames
    for _frame_index in range(SAMPLE_FRAMES):
        if move_camera:
            demo.camera.position += Vector2(6.0, 2.0)
            demo.camera.force_update_scroll()
        await process_frame
        var now_usec: int = Time.get_ticks_usec()
        frame_times.append(float(now_usec - previous_usec) / 1000.0)
        previous_usec = now_usec
    var zeros: Array[float] = []
    zeros.resize(SAMPLE_FRAMES)
    zeros.fill(0.0)
    _print_metrics(
        label, frame_times, zeros.duplicate(), zeros.duplicate(), zeros.duplicate(),
        0, 0, terrain.chunk_processing_overrun_frames - overruns_start)


func _run_undo_redo() -> void:
    editor.edit_mode = EditorController.EditMode.MATERIAL
    editor.brush_shape = EditorController.BrushShape.SQUARE
    editor.brush_size = 11
    editor.selected_material = 4
    editor.begin_stroke(Vector2i(-5, -5))
    editor.continue_stroke(Vector2i(8, 8))
    editor.end_stroke()
    var times: Array[float] = []
    var frame_times: Array[float] = []
    var refresh_times: Array[float] = []
    var environment_times: Array[float] = []
    var dirty_cells_total: int = 0
    var maximum_dirty_chunks: int = 0
    var overruns_start: int = terrain.chunk_processing_overrun_frames
    for _cycle in range(10):
        var start_usec: int = Time.get_ticks_usec()
        editor.undo()
        times.append(float(Time.get_ticks_usec() - start_usec) / 1000.0)
        refresh_times.append(float(terrain.last_edit_refresh_usec) / 1000.0)
        dirty_cells_total += terrain.last_edit_dirty_cell_count
        maximum_dirty_chunks = maxi(maximum_dirty_chunks, terrain.last_edit_dirty_chunk_count)
        await _drain_edit_refresh_profile(frame_times, refresh_times, environment_times)
        start_usec = Time.get_ticks_usec()
        editor.redo()
        times.append(float(Time.get_ticks_usec() - start_usec) / 1000.0)
        refresh_times.append(float(terrain.last_edit_refresh_usec) / 1000.0)
        dirty_cells_total += terrain.last_edit_dirty_cell_count
        maximum_dirty_chunks = maxi(maximum_dirty_chunks, terrain.last_edit_dirty_chunk_count)
        await _drain_edit_refresh_profile(frame_times, refresh_times, environment_times)
    _print_metrics(
        "undo_redo_large", frame_times, times, refresh_times, environment_times, dirty_cells_total,
        maximum_dirty_chunks, terrain.chunk_processing_overrun_frames - overruns_start)


func _print_metrics(
        label: String, frame_times: Array[float], edit_times: Array[float],
        refresh_times: Array[float], environment_times: Array[float],
        dirty_cells_total: int, maximum_dirty_chunks: int, overruns: int) -> void:
    frame_times.sort()
    edit_times.sort()
    refresh_times.sort()
    environment_times.sort()
    var frame_sum: float = 0.0
    for value in frame_times:
        frame_sum += value
    var edit_sum: float = 0.0
    for value in edit_times:
        edit_sum += value
    var refresh_sum: float = 0.0
    for value in refresh_times:
        refresh_sum += value
    var environment_sum: float = 0.0
    for value in environment_times:
        environment_sum += value
    var memory_mib: float = Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0)
    print("PHASE7A_MODE mode=%s frames=%d avg_ms=%.3f p95_ms=%.3f p99_ms=%.3f worst_ms=%.3f edit_avg_ms=%.3f edit_p95_ms=%.3f refresh_avg_ms=%.3f environment_avg_ms=%.3f dirty_cells=%d max_dirty_chunks=%d overruns=%d memory_mib=%.2f" % [
        label, frame_times.size(), frame_sum / frame_times.size(),
        _percentile(frame_times, 0.95), _percentile(frame_times, 0.99), frame_times[-1],
        edit_sum / edit_times.size(), _percentile(edit_times, 0.95),
        refresh_sum / refresh_times.size(), environment_sum / environment_times.size(),
        dirty_cells_total, maximum_dirty_chunks, overruns, memory_mib])


func _drain_edit_refresh(max_frames: int = 120) -> void:
    for _frame in range(max_frames):
        if (terrain.get_pending_edit_cell_count() == 0
                and terrain.get_pending_edit_environment_chunk_count() == 0):
            return
        await process_frame


func _drain_edit_refresh_profile(
        frame_times: Array[float], refresh_times: Array[float],
        environment_times: Array[float], max_frames: int = 120) -> void:
    var previous_usec: int = Time.get_ticks_usec()
    for _frame in range(max_frames):
        if (terrain.get_pending_edit_cell_count() == 0
                and terrain.get_pending_edit_environment_chunk_count() == 0):
            return
        await process_frame
        var now_usec: int = Time.get_ticks_usec()
        frame_times.append(float(now_usec - previous_usec) / 1000.0)
        previous_usec = now_usec
        refresh_times.append(float(terrain.last_edit_refresh_usec) / 1000.0)
        environment_times.append(float(terrain.last_edit_environment_refresh_usec) / 1000.0)


func _percentile(values: Array[float], percentile: float) -> float:
    return values[clampi(ceili(values.size() * percentile) - 1, 0, values.size() - 1)]


func _wait_until_streaming_idle(max_frames: int = 1200) -> void:
    for _frame in range(max_frames):
        await process_frame
        if terrain.get_pending_chunk_count() == 0:
            return


func _wait_frames(count: int) -> void:
    for _frame in range(count):
        await process_frame

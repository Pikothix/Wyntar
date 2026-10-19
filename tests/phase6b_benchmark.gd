extends SceneTree
## Reproducible Phase 6B three-mode benchmark. Ground decorations remain on;
## only large-object generation and visibility differ between modes.

const FRAME_COUNT: int = 720

var _demo
var _terrain


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    DisplayServer.window_set_size(Vector2i(1280, 720))
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    _demo = load("res://main.tscn").instantiate()
    root.add_child(_demo)
    await _wait_frames(4)
    _terrain = _demo.terrain
    _demo.hud.visible = false
    _create_visual_fixtures()

    await _run_mode("disabled", false, false)
    await _run_mode("placement_hidden", true, false)
    await _run_mode("full", true, true)
    print("PHASE6B_BENCHMARK PASS")
    quit(0)


func _run_mode(label: String, generation_enabled: bool, visible: bool) -> void:
    _terrain.environment_object_generation_enabled = generation_enabled
    _terrain.environment_object_context["generation_enabled"] = generation_enabled
    _terrain.set_environment_objects_enabled(visible)
    var route := [
        Vector2(Vector2i(210, 200) * _terrain.TILE_SIZE),
        Vector2(Vector2i(274, 200) * _terrain.TILE_SIZE),
        Vector2(Vector2i(210, 264) * _terrain.TILE_SIZE),
        Vector2(Vector2i(274, 232) * _terrain.TILE_SIZE),
    ]
    _demo.camera.position = route[0]
    _demo.camera.zoom = Vector2.ONE
    _demo.camera.force_update_scroll()
    _demo._update_visible_world_region()
    _terrain._invalidate_streamed_chunks()
    await _wait_frames(2)

    var frame_times: Array[float] = []
    var draw_calls: Array[float] = []
    var overrun_start: int = _terrain.chunk_processing_overrun_frames
    var chunk_count_start: int = _terrain.total_profiled_chunks
    var chunk_usec_start: int = _terrain.profile_total_chunk_usec
    var preparation_usec_start: int = _terrain.profile_total_environment_usec
    var submission_usec_start: int = _terrain.profile_total_environment_submission_usec
    var previous_usec: int = Time.get_ticks_usec()
    for frame_index in range(FRAME_COUNT):
        var segment: int = mini(route.size() - 2, floori(float(frame_index) / 240.0))
        var segment_t: float = float(frame_index % 240) / 239.0
        _demo.camera.position = route[segment].lerp(route[segment + 1], segment_t)
        _demo.camera.force_update_scroll()
        await process_frame
        var now_usec: int = Time.get_ticks_usec()
        frame_times.append(float(now_usec - previous_usec) / 1000.0)
        previous_usec = now_usec
        draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
    frame_times.sort()
    var sum_ms: float = 0.0
    for value in frame_times:
        sum_ms += value
    var sum_draw_calls: float = 0.0
    for value in draw_calls:
        sum_draw_calls += value
    var completed_chunks: int = _terrain.total_profiled_chunks - chunk_count_start
    var chunk_ms: float = 0.0
    var preparation_ms: float = 0.0
    var submission_ms: float = 0.0
    if completed_chunks > 0:
        chunk_ms = float(_terrain.profile_total_chunk_usec - chunk_usec_start) / completed_chunks / 1000.0
        preparation_ms = float(_terrain.profile_total_environment_usec - preparation_usec_start) / completed_chunks / 1000.0
        submission_ms = float(_terrain.profile_total_environment_submission_usec - submission_usec_start) / completed_chunks / 1000.0
    var loaded_count: int = _terrain.get_loaded_chunk_count()
    var memory_mib: float = Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0)
    var visible_count: int = _terrain.get_visible_environment_object_count()
    var categories: Dictionary = _terrain.get_environment_object_category_counts()
    _demo.camera.position = route[-1] + Vector2(_terrain.CHUNK_SIZE * _terrain.TILE_SIZE.x * 12, 0)
    _demo.camera.force_update_scroll()
    var cleanup_start: int = Time.get_ticks_usec()
    _demo._update_visible_world_region()
    var cleanup_ms: float = float(Time.get_ticks_usec() - cleanup_start) / 1000.0
    await _wait_frames(2)
    print("PHASE6B_MODE mode=%s frames=%d avg_ms=%.3f p95_ms=%.3f p99_ms=%.3f worst_ms=%.3f chunk_avg_ms=%.3f object_prep_avg_ms=%.3f object_submission_avg_ms=%.3f cleanup_ms=%.3f overruns=%d loaded=%d memory_mib=%.2f draw_calls_avg=%.2f visible_objects=%d trees=%d bushes=%d rocks=%d debris=%d" % [
        label, frame_times.size(), sum_ms / frame_times.size(),
        _percentile(frame_times, 0.95), _percentile(frame_times, 0.99), frame_times[-1],
        chunk_ms, preparation_ms, submission_ms, cleanup_ms,
        _terrain.chunk_processing_overrun_frames - overrun_start,
        loaded_count, memory_mib, sum_draw_calls / draw_calls.size(), visible_count,
        int(categories.get("trees", 0)), int(categories.get("bushes", 0)),
        int(categories.get("rocks", 0)), int(categories.get("debris", 0)),
    ])


func _create_visual_fixtures() -> void:
    _fill(Vector2i(196, 186), Vector2i(28, 28), 3, 0)
    _fill(Vector2i(228, 186), Vector2i(28, 28), 3, 0)
    _fill(Vector2i(237, 195), Vector2i(11, 10), 0, 3)
    for y in range(194, 207):
        for x in range(236, 250):
            if _terrain.world.get_cell(Vector2i(x, y)) != 0 and (x in [236, 249] or y in [194, 206]):
                _set_fixture_cell(Vector2i(x, y), 6, 0)
    _fill(Vector2i(260, 186), Vector2i(28, 28), 3, 0)
    _fill(Vector2i(266, 192), Vector2i(16, 16), 3, 2)
    _fill(Vector2i(196, 218), Vector2i(28, 28), 2, 0)
    _fill(Vector2i(202, 224), Vector2i(16, 16), 4, 2)
    _fill(Vector2i(207, 227), Vector2i(7, 8), 4, 3)
    _fill(Vector2i(228, 218), Vector2i(28, 28), 4, 2)
    _fill(Vector2i(234, 224), Vector2i(16, 16), 5, 3)
    _fill(Vector2i(260, 218), Vector2i(14, 28), 1, 0)
    _fill(Vector2i(274, 218), Vector2i(14, 28), 7, 0)
    _fill(Vector2i(196, 250), Vector2i(28, 28), 2, 0)
    _fill(Vector2i(202, 256), Vector2i(16, 15), 3, 2)
    _fill(Vector2i(242, 250), Vector2i(28, 28), 0, 2)
    _fill(Vector2i(252, 256), Vector2i(9, 15), 3, 2)


func _fill(origin: Vector2i, size: Vector2i, terrain_id: int, elevation: int) -> void:
    for y in range(origin.y, origin.y + size.y):
        for x in range(origin.x, origin.x + size.x):
            _set_fixture_cell(Vector2i(x, y), terrain_id, elevation)


func _set_fixture_cell(pos: Vector2i, terrain_id: int, elevation: int) -> void:
    _terrain.world.set_override(pos, terrain_id)
    _terrain.world.set_elevation_override(pos, elevation)


func _percentile(sorted_values: Array[float], percentile: float) -> float:
    var index: int = clampi(ceili(sorted_values.size() * percentile) - 1, 0, sorted_values.size() - 1)
    return sorted_values[index]


func _wait_frames(count: int) -> void:
    for _frame in range(count):
        await process_frame

extends SceneTree
## Graphical Phase 5D evidence and reproducible streaming benchmark. This test
## owns only temporary in-process overrides; production persistence is untouched.

const OUTPUT_DIR := "res://screenshots"
const ZOOMS: Array[float] = [0.5, 1.0, 3.0]

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
    await _wait_until_streaming_idle()

    await _capture_zoom_set("main_mountain_lake", Vector2(16.0, 16.0))
    await _capture_height_diagnostic(Vector2(16.0, 16.0))

    _create_visual_fixtures()
    _terrain._invalidate_streamed_chunks()
    await _wait_until_streaming_idle()
    var cases := [
        {"name": "grass_plateau_water", "cell": Vector2i(70, 70)},
        {"name": "rock_plateau_water", "cell": Vector2i(102, 70)},
        {"name": "flat_beach_water", "cell": Vector2i(70, 102)},
        {"name": "irregular_shore_cliff_corners", "cell": Vector2i(102, 102)},
        {"name": "cliff_chunk_boundary", "cell": Vector2i(128, 70)},
        {"name": "four_direction_transitions", "cell": Vector2i(128, 102)},
    ]
    for capture_case in cases:
        var cell: Vector2i = capture_case.cell
        await _capture_zoom_set(
            String(capture_case.name),
            Vector2(cell * _terrain.TILE_SIZE) + Vector2(16.0, 16.0))

    await _run_camera_benchmark()
    print("PHASE5D_GRAPHICAL_CAPTURE PASS")
    quit(0)


func _create_visual_fixtures() -> void:
    _fill(Vector2i(58, 58), Vector2i(24, 24), 0, 3)
    _fill(Vector2i(66, 66), Vector2i(9, 9), 3, 2)

    _fill(Vector2i(90, 58), Vector2i(24, 24), 0, 2)
    _fill(Vector2i(98, 66), Vector2i(9, 9), 4, 2)

    _fill(Vector2i(58, 90), Vector2i(24, 24), 0, 2)
    _fill(Vector2i(58, 90), Vector2i(12, 24), 1, 0)

    _fill(Vector2i(90, 90), Vector2i(24, 24), 0, 3)
    for y in range(95, 109):
        for x in range(95, 109):
            if x <= 101 or y <= 100 or (x + y) % 5 == 0:
                _set_fixture_cell(Vector2i(x, y), 3, 1 + int((x + y) % 7 == 0))

    _fill(Vector2i(116, 58), Vector2i(24, 24), 0, 2)
    _fill(Vector2i(124, 64), Vector2i(9, 13), 3, 2)

    _fill(Vector2i(116, 90), Vector2i(24, 24), 3, 0)
    _fill(Vector2i(124, 98), Vector2i(9, 9), 3, 2)
    _set_fixture_cell(Vector2i(128, 97), 0, 3)
    _set_fixture_cell(Vector2i(123, 102), 0, 2)
    _set_fixture_cell(Vector2i(133, 102), 0, 1)
    _set_fixture_cell(Vector2i(128, 107), 0, 3)


func _fill(origin: Vector2i, size: Vector2i, terrain_id: int, elevation: int) -> void:
    for y in range(origin.y, origin.y + size.y):
        for x in range(origin.x, origin.x + size.x):
            _set_fixture_cell(Vector2i(x, y), terrain_id, elevation)


func _set_fixture_cell(pos: Vector2i, terrain_id: int, elevation: int) -> void:
    _terrain.world.set_override(pos, terrain_id)
    _terrain.world.set_elevation_override(pos, elevation)


func _capture_zoom_set(label: String, camera_position: Vector2) -> void:
    for zoom in ZOOMS:
        _demo.camera.position = camera_position
        _demo.camera.zoom = Vector2.ONE * zoom
        _demo.camera.force_update_scroll()
        _demo._update_visible_world_region()
        await _wait_until_streaming_idle()
        await _wait_frames(3)
        var zoom_label: String = String.num(zoom, 1).replace(".", "_")
        var path: String = "%s/phase5d_after_%s_%sx.png" % [OUTPUT_DIR, label, zoom_label]
        var error: Error = root.get_texture().get_image().save_png(path)
        if error != OK:
            push_error("Could not save capture %s: %s" % [path, error_string(error)])


func _capture_height_diagnostic(camera_position: Vector2) -> void:
    _demo.camera.position = camera_position
    _demo.camera.zoom = Vector2.ONE
    _demo.cursor.show_elevation_overlay = true
    _demo.cursor.queue_redraw()
    _demo.camera.force_update_scroll()
    _demo._update_visible_world_region()
    await _wait_until_streaming_idle()
    await _wait_frames(3)
    var path: String = "%s/phase5d_height_diagnostic_1_0x.png" % OUTPUT_DIR
    var error: Error = root.get_texture().get_image().save_png(path)
    if error != OK:
        push_error("Could not save diagnostic capture %s: %s" % [path, error_string(error)])
    _demo.cursor.show_elevation_overlay = false
    _demo.cursor.queue_redraw()


func _run_camera_benchmark() -> void:
    var frame_times: Array[float] = []
    var route := [
        Vector2(16.0, 16.0),
        Vector2(Vector2i(70, 70) * _terrain.TILE_SIZE),
        Vector2(Vector2i(102, 102) * _terrain.TILE_SIZE),
        Vector2(Vector2i(128, 70) * _terrain.TILE_SIZE),
    ]
    var overrun_start: int = _terrain.chunk_processing_overrun_frames
    var chunk_count_start: int = _terrain.total_profiled_chunks
    var chunk_usec_start: int = _terrain.profile_total_chunk_usec
    var cliff_usec_start: int = _terrain.profile_total_cliff_usec
    var previous_usec: int = Time.get_ticks_usec()
    for frame_index in range(720):
        var segment: int = mini(route.size() - 2, frame_index / 240)
        var segment_t: float = float(frame_index % 240) / 239.0
        _demo.camera.position = route[segment].lerp(route[segment + 1], segment_t)
        _demo.camera.force_update_scroll()
        await process_frame
        var now_usec: int = Time.get_ticks_usec()
        frame_times.append(float(now_usec - previous_usec) / 1000.0)
        previous_usec = now_usec
    frame_times.sort()
    var sum_ms: float = 0.0
    for value in frame_times:
        sum_ms += value
    var completed_chunks: int = _terrain.total_profiled_chunks - chunk_count_start
    var average_chunk_ms: float = 0.0
    var average_cliff_ms: float = 0.0
    if completed_chunks > 0:
        average_chunk_ms = float(_terrain.profile_total_chunk_usec - chunk_usec_start) / completed_chunks / 1000.0
        average_cliff_ms = float(_terrain.profile_total_cliff_usec - cliff_usec_start) / completed_chunks / 1000.0
    print("PHASE5D_FRAME_BENCHMARK frames=%d avg_ms=%.3f p95_ms=%.3f p99_ms=%.3f worst_ms=%.3f chunk_avg_ms=%.3f cliff_avg_ms=%.3f overruns=%d loaded=%d memory_mib=%.2f" % [
        frame_times.size(), sum_ms / frame_times.size(),
        _percentile(frame_times, 0.95), _percentile(frame_times, 0.99),
        frame_times[-1], average_chunk_ms, average_cliff_ms,
        _terrain.chunk_processing_overrun_frames - overrun_start,
        _terrain.get_loaded_chunk_count(),
        Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0),
    ])


func _percentile(sorted_values: Array[float], percentile: float) -> float:
    var index: int = clampi(ceili(sorted_values.size() * percentile) - 1, 0, sorted_values.size() - 1)
    return sorted_values[index]


func _wait_until_streaming_idle(max_frames: int = 900) -> void:
    for _frame in range(max_frames):
        await process_frame
        if _terrain != null and _terrain.get_pending_chunk_count() == 0:
            return
    push_warning("Streaming did not become idle within %d frames" % max_frames)


func _wait_frames(count: int) -> void:
    for _frame in range(count):
        await process_frame

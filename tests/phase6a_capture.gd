extends SceneTree
## Reproducible Phase 6A visual matrix and enabled/disabled performance route.
## Temporary fixture overrides live only for this process.

const OUTPUT_DIR := "res://.artifacts"
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

    _create_visual_fixtures()
    _terrain._invalidate_streamed_chunks()
    await _wait_until_streaming_idle()

    var benchmark_only: bool = "--benchmark-only" in OS.get_cmdline_user_args()
    var cases := [
        {"name": "open_grasslands", "cell": Vector2i(210, 200)},
        {"name": "grass_near_water", "cell": Vector2i(242, 200)},
        {"name": "elevated_grass", "cell": Vector2i(274, 200)},
        {"name": "rocky_mountain", "cell": Vector2i(210, 232)},
        {"name": "snow_highlands", "cell": Vector2i(242, 232)},
        {"name": "sand_gravel", "cell": Vector2i(274, 232)},
        {"name": "cliff_top_vegetation", "cell": Vector2i(210, 264)},
        {"name": "chunk_boundary", "cell": Vector2i(256, 264)},
    ]
    if not benchmark_only:
        for enabled in [false, true]:
            _terrain.set_decorations_enabled(enabled)
            for capture_case in cases:
                var cell: Vector2i = capture_case.cell
                await _capture_zoom_set(
                    "after" if enabled else "before",
                    String(capture_case.name),
                    Vector2(cell * _terrain.TILE_SIZE) + Vector2(16.0, 16.0))

    await _run_camera_benchmark(false)
    await _run_camera_benchmark(true)
    print("PHASE6A_GRAPHICAL_CAPTURE PASS")
    quit(0)


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


func _capture_zoom_set(state_label: String, label: String, camera_position: Vector2) -> void:
    for zoom in ZOOMS:
        _demo.camera.position = camera_position
        _demo.camera.zoom = Vector2.ONE * zoom
        _demo.camera.force_update_scroll()
        _demo._update_visible_world_region()
        await _wait_until_streaming_idle()
        await _wait_frames(3)
        var zoom_label: String = String.num(zoom, 1).replace(".", "_")
        var path: String = "%s/phase6a_%s_%s_%sx.png" % [
            OUTPUT_DIR, state_label, label, zoom_label]
        var error: Error = root.get_texture().get_image().save_png(path)
        if error != OK:
            push_error("Could not save capture %s: %s" % [path, error_string(error)])


func _run_camera_benchmark(enabled: bool) -> void:
    _terrain.set_decorations_enabled(enabled)
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
    var overrun_start: int = _terrain.chunk_processing_overrun_frames
    var chunk_count_start: int = _terrain.total_profiled_chunks
    var chunk_usec_start: int = _terrain.profile_total_chunk_usec
    var decoration_usec_start: int = _terrain.profile_total_decoration_usec
    var previous_usec: int = Time.get_ticks_usec()
    for frame_index in range(720):
        var segment: int = mini(route.size() - 2, floori(float(frame_index) / 240.0))
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
    var average_decoration_ms: float = 0.0
    if completed_chunks > 0:
        average_chunk_ms = float(
            _terrain.profile_total_chunk_usec - chunk_usec_start) / completed_chunks / 1000.0
        average_decoration_ms = float(
            _terrain.profile_total_decoration_usec - decoration_usec_start) / completed_chunks / 1000.0
    print("PHASE6A_FRAME_BENCHMARK decorations=%s frames=%d avg_ms=%.3f p95_ms=%.3f p99_ms=%.3f worst_ms=%.3f chunk_avg_ms=%.3f decoration_avg_ms=%.3f overruns=%d loaded=%d memory_mib=%.2f visible_decorations=%d" % [
        "on" if enabled else "off", frame_times.size(),
        sum_ms / frame_times.size(), _percentile(frame_times, 0.95),
        _percentile(frame_times, 0.99), frame_times[-1], average_chunk_ms,
        average_decoration_ms,
        _terrain.chunk_processing_overrun_frames - overrun_start,
        _terrain.get_loaded_chunk_count(),
        Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0),
        _terrain.get_visible_decoration_count(),
    ])


func _percentile(sorted_values: Array[float], percentile: float) -> float:
    var index: int = clampi(
        ceili(sorted_values.size() * percentile) - 1,
        0, sorted_values.size() - 1)
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

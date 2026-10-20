extends SceneTree
## Representative Phase 6A.5 readability and HUD captures.

var _demo
var _terrain


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    DisplayServer.window_set_size(Vector2i(1280, 720))
    _demo = load("res://main.tscn").instantiate()
    root.add_child(_demo)
    await _wait_frames(4)
    _terrain = _demo.terrain
    _create_fixture()
    _terrain._invalidate_streamed_chunks()

    _demo.compact_hud_enabled = true
    _demo._apply_hud_mode()
    await _capture(
        "res://.artifacts/phase6a5_compact_hud_1x.png",
        Vector2(Vector2i(228, 202) * _terrain.TILE_SIZE), 1.0)
    await _capture(
        "res://.artifacts/phase6a5_readability_shore_3x.png",
        Vector2(Vector2i(230, 202) * _terrain.TILE_SIZE), 3.0)

    _demo.compact_hud_enabled = false
    _demo._apply_hud_mode()
    await _capture(
        "res://.artifacts/phase6a5_expanded_hud_1x.png",
        Vector2(Vector2i(228, 202) * _terrain.TILE_SIZE), 1.0)
    print("PHASE6A5_GRAPHICAL_CAPTURE PASS")
    quit(0)


func _create_fixture() -> void:
    _fill(Vector2i(204, 184), Vector2i(48, 36), 3, 0)
    _fill(Vector2i(232, 190), Vector2i(14, 22), 0, 2)
    for y in range(189, 213):
        for x in range(231, 247):
            var pos := Vector2i(x, y)
            if _terrain.world.get_cell(pos) != 0 and (x in [231, 246] or y in [189, 212]):
                _set_fixture_cell(pos, 6, 0)
    _fill(Vector2i(208, 208), Vector2i(15, 8), 3, 2)
    _fill(Vector2i(246, 184), Vector2i(10, 36), 7, 0)


func _fill(origin: Vector2i, size: Vector2i, terrain_id: int, elevation: int) -> void:
    for y in range(origin.y, origin.y + size.y):
        for x in range(origin.x, origin.x + size.x):
            _set_fixture_cell(Vector2i(x, y), terrain_id, elevation)


func _set_fixture_cell(pos: Vector2i, terrain_id: int, elevation: int) -> void:
    _terrain.world.set_override(pos, terrain_id)
    _terrain.world.set_elevation_override(pos, elevation)


func _capture(path: String, position: Vector2, zoom: float) -> void:
    _demo.camera.position = position
    _demo.camera.zoom = Vector2.ONE * zoom
    _demo.camera.force_update_scroll()
    await process_frame
    _demo._update_visible_world_region()
    await _wait_until_streaming_idle()
    _demo.camera.force_update_scroll()
    await _wait_frames(3)
    var error: Error = root.get_texture().get_image().save_png(path)
    if error != OK:
        push_error("Could not save %s: %s" % [path, error_string(error)])


func _wait_until_streaming_idle(max_frames: int = 900) -> void:
    for _frame in range(max_frames):
        await process_frame
        if _terrain.get_pending_chunk_count() == 0:
            return
    push_warning("Streaming did not become idle within %d frames" % max_frames)


func _wait_frames(count: int) -> void:
    for _frame in range(count):
        await process_frame

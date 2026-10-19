extends SceneTree
## Reproducible Phase 6B visual matrix. Fixture overrides exist only in this
## process and do not alter the project scene or persistence model.

const OUTPUT_DIR := "res://screenshots"
const ZOOMS: Array[float] = [0.5, 1.0, 3.0]

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
    _verify_hud_and_visibility_controls()
    _demo.hud.visible = false
    _create_visual_fixtures()
    _terrain._invalidate_streamed_chunks()
    await _wait_until_streaming_idle()

    var cases := [
        {"name": "sparse_grassland", "cell": Vector2i(210, 200)},
        {"name": "clustered_woodland", "cell": Vector2i(242, 200)},
        {"name": "conifer_highland", "cell": Vector2i(274, 200)},
        {"name": "rocky_boulders", "cell": Vector2i(210, 232)},
        {"name": "lake_vegetation", "cell": Vector2i(242, 232)},
        {"name": "elevated_plateau", "cell": Vector2i(274, 232)},
        {"name": "chunk_boundary_canopies", "cell": Vector2i(256, 264)},
        {"name": "objects_and_ground_details", "cell": Vector2i(210, 264)},
    ]

    _terrain.set_environment_objects_enabled(false)
    await _capture(
        "phase6b_objects_disabled_sparse_grassland_1_0x",
        Vector2(cases[0].cell * _terrain.TILE_SIZE) + Vector2(16.0, 16.0), 1.0)
    _terrain.set_environment_objects_enabled(true)
    for capture_case in cases:
        for zoom in ZOOMS:
            var zoom_label: String = String.num(zoom, 1).replace(".", "_")
            await _capture(
                "phase6b_%s_%sx" % [capture_case.name, zoom_label],
                Vector2(capture_case.cell * _terrain.TILE_SIZE) + Vector2(16.0, 16.0),
                zoom)
    print("PHASE6B_GRAPHICAL_CAPTURE PASS")
    quit(0)


func _verify_hud_and_visibility_controls() -> void:
    var initial_visibility: bool = _demo.environment_objects_enabled
    _press_key(KEY_T)
    assert(_demo.environment_objects_enabled != initial_visibility,
        "T must toggle environmental-object visibility")
    _press_key(KEY_T)
    assert(_demo.environment_objects_enabled == initial_visibility,
        "A second T press must restore environmental-object visibility")
    var initial_hud_mode: bool = _demo.compact_hud_enabled
    _press_key(KEY_F2)
    assert(_demo.compact_hud_enabled != initial_hud_mode,
        "F2 must switch compact and expanded HUD modes")
    _press_key(KEY_F2)
    assert(_demo.compact_hud_enabled == initial_hud_mode,
        "A second F2 press must restore the HUD mode")
    var initial_diagnostics: bool = _demo.debug_label.visible
    _press_key(KEY_F3)
    assert(_demo.debug_label.visible != initial_diagnostics,
        "F3 must toggle diagnostics")
    _press_key(KEY_F3)


func _press_key(keycode: Key) -> void:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.pressed = true
    _demo._unhandled_key_input(event)


func _create_visual_fixtures() -> void:
    _fill(Vector2i(194, 184), Vector2i(32, 32), 3, 0)

    _fill(Vector2i(226, 184), Vector2i(32, 32), 3, 0)

    _fill(Vector2i(258, 184), Vector2i(32, 32), 3, 2)
    _fill(Vector2i(267, 191), Vector2i(16, 18), 5, 3)

    _fill(Vector2i(194, 216), Vector2i(32, 32), 4, 2)
    _fill(Vector2i(203, 225), Vector2i(14, 14), 7, 3)

    _fill(Vector2i(226, 216), Vector2i(32, 32), 3, 0)
    _fill(Vector2i(235, 224), Vector2i(14, 15), 0, 2)
    for y in range(223, 240):
        for x in range(234, 250):
            var pos := Vector2i(x, y)
            if _terrain.world.get_cell(pos) != 0 and (x in [234, 249] or y in [223, 239]):
                _set_fixture_cell(pos, 6, 0)

    _fill(Vector2i(258, 216), Vector2i(32, 32), 2, 0)
    _fill(Vector2i(265, 223), Vector2i(18, 18), 3, 2)

    _fill(Vector2i(240, 248), Vector2i(32, 32), 3, 1)
    _fill(Vector2i(248, 255), Vector2i(17, 18), 3, 2)

    _fill(Vector2i(194, 248), Vector2i(32, 32), 3, 0)
    _fill(Vector2i(201, 255), Vector2i(18, 18), 2, 0)


func _fill(origin: Vector2i, size: Vector2i, terrain_id: int, elevation: int) -> void:
    for y in range(origin.y, origin.y + size.y):
        for x in range(origin.x, origin.x + size.x):
            _set_fixture_cell(Vector2i(x, y), terrain_id, elevation)


func _set_fixture_cell(pos: Vector2i, terrain_id: int, elevation: int) -> void:
    _terrain.world.set_override(pos, terrain_id)
    _terrain.world.set_elevation_override(pos, elevation)


func _capture(label: String, camera_position: Vector2, zoom: float) -> void:
    _demo.camera.position = camera_position
    _demo.camera.zoom = Vector2.ONE * zoom
    _demo.camera.force_update_scroll()
    await process_frame
    _demo._update_visible_world_region()
    await _wait_until_streaming_idle()
    _demo.camera.force_update_scroll()
    await _wait_frames(3)
    var path: String = "%s/%s.png" % [OUTPUT_DIR, label]
    var error: Error = root.get_texture().get_image().save_png(path)
    if error != OK:
        push_error("Could not save %s: %s" % [path, error_string(error)])


func _wait_until_streaming_idle(max_frames: int = 1200) -> void:
    for _frame in range(max_frames):
        await process_frame
        if _terrain.get_pending_chunk_count() == 0:
            return
    push_warning("Streaming did not become idle within %d frames" % max_frames)


func _wait_frames(count: int) -> void:
    for _frame in range(count):
        await process_frame

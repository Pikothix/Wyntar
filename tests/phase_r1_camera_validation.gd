extends SceneTree
## Focused parity checks for the Phase R1 camera extraction, including the
## legacy pan/zoom formulas, input routing, streaming, and world replacement.

const MainScene = preload("res://main.tscn")
const CameraController = preload("res://scripts/camera_controller.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_detached_camera_math()
	await _validate_main_integration()
	if failures.is_empty():
		print("PHASE_R1_CAMERA_VALIDATION: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("PHASE_R1_CAMERA_VALIDATION: FAIL (%d)" % failures.size())
		quit(1)


func _validate_detached_camera_math() -> void:
	var camera = CameraController.new()
	root.add_child(camera)
	camera.make_current()
	camera.apply_state(Vector2(120.0, -75.0), 2.0)

	var expected_pan: Vector2 = camera.position + Vector2(1.0, 1.0).normalized() \
		* 700.0 * 0.25 / camera.zoom.x
	camera.pan_direction(Vector2(1.0, 1.0), 0.25)
	_expect(camera.position.is_equal_approx(expected_pan),
		"keyboard pan preserves normalized direction, speed, delta and zoom scaling")

	var viewport_size := Vector2(1280.0, 720.0)
	var cursor_position := Vector2(930.0, 155.0)
	var old_position: Vector2 = camera.position
	var old_zoom: float = camera.zoom.x
	var expected_zoom: float = clampf(old_zoom * 1.15, 0.001, 166.0)
	var cursor_offset: Vector2 = cursor_position - viewport_size * 0.5
	var expected_position: Vector2 = (
		old_position + cursor_offset / old_zoom - cursor_offset / expected_zoom)
	camera.zoom_toward_screen_point(1.15, cursor_position, viewport_size)
	_expect(is_equal_approx(camera.zoom.x, expected_zoom)
		and camera.position.is_equal_approx(expected_position),
		"cursor-centred zoom matches the pre-refactor formula")

	camera.apply_state(Vector2.ZERO, 165.0)
	camera.zoom_toward_screen_point(1.15, viewport_size * 0.5, viewport_size)
	_expect(is_equal_approx(camera.zoom.x, 166.0), "maximum zoom remains 166")
	camera.apply_state(Vector2.ZERO, 0.0011)
	camera.zoom_toward_screen_point(1.0 / 1.15, viewport_size * 0.5, viewport_size)
	_expect(is_equal_approx(camera.zoom.x, 0.001), "minimum zoom remains 0.001")

	camera.apply_state(Vector2(20.0, 30.0), 2.0)
	var middle_down := InputEventMouseButton.new()
	middle_down.button_index = MOUSE_BUTTON_MIDDLE
	middle_down.pressed = true
	_expect(camera.handle_pointer_input(middle_down) and camera.is_middle_panning(),
		"middle press begins panning")
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(18.0, -10.0)
	_expect(camera.handle_pointer_input(motion)
		and camera.position.is_equal_approx(Vector2(11.0, 35.0)),
		"middle drag preserves inverse-zoom movement")
	middle_down.pressed = false
	_expect(camera.handle_pointer_input(middle_down) and not camera.is_middle_panning(),
		"middle release ends panning")
	var left_click := InputEventMouseButton.new()
	left_click.button_index = MOUSE_BUTTON_LEFT
	left_click.pressed = true
	_expect(not camera.handle_pointer_input(left_click),
		"non-camera pointer input remains available to the world editor")

	var home := InputEventKey.new()
	home.keycode = KEY_HOME
	_expect(camera.handle_navigation_shortcut(home)
		and camera.position == Vector2(16.0, 16.0) and camera.zoom == Vector2.ONE,
		"Home preserves the initial camera centre and zoom")
	camera.queue_free()


func _validate_main_integration() -> void:
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

	_expect(main.camera.get_script() == CameraController,
		"main scene starts with the extracted CameraController")
	_expect(main.camera.position == Vector2(16.0, 16.0) and main.camera.zoom == Vector2.ONE,
		"main scene retains its initial camera state")

	main.camera.apply_state(Vector2(245.0, -130.0), 1.6)
	await process_frame
	var viewport_size: Vector2 = main.get_viewport_rect().size
	var inverse_canvas: Transform2D = main.terrain.get_global_transform_with_canvas().affine_inverse()
	var legacy_rect := Rect2(
		inverse_canvas * Vector2.ZERO,
		inverse_canvas * viewport_size - inverse_canvas * Vector2.ZERO).abs()
	var extracted_rect: Rect2 = main.camera.get_visible_world_rect(main.terrain, viewport_size)
	_expect(extracted_rect.is_equal_approx(legacy_rect),
		"visible-world rectangle matches the pre-refactor canvas-transform calculation")
	main._update_visible_world_region()
	_expect(main.cursor.visible_world_rect.is_equal_approx(extracted_rect),
		"main passes the camera rectangle to the cursor overlay")

	await _wait_until_idle(main.terrain, 600)
	var initial_chunks: Dictionary = main.terrain.loaded_chunks.duplicate()
	main.camera.position += Vector2(4096.0, 4096.0)
	main.camera.force_update_scroll()
	main._update_visible_world_region()
	await _wait_until_idle(main.terrain, 600)
	_expect(not main.terrain.loaded_chunks.is_empty()
		and main.terrain.loaded_chunks.keys() != initial_chunks.keys(),
		"camera movement continues to drive chunk loading and unloading")

	var snapshot: Dictionary = main.save_service.capture_snapshot(
		main.terrain, main.camera, main.world_identifier, main.world_display_name)
	snapshot["world"]["camera"] = {"x": -512.5, "y": 768.25, "zoom": 1.75}
	var replacement_result: Dictionary = main._replace_world_from_snapshot(snapshot)
	_expect(bool(replacement_result.get("ok", false)), "world replacement succeeds")
	_expect(main.camera.position.is_equal_approx(Vector2(-512.5, 768.25))
		and is_equal_approx(main.camera.zoom.x, 1.75),
		"world replacement restores camera state through the controller")
	var restored_rect: Rect2 = main.camera.get_visible_world_rect(
		main.terrain, main.get_viewport_rect().size)
	_expect(main.cursor.visible_world_rect.is_equal_approx(restored_rect),
		"world replacement immediately refreshes visible-world consumers")

	main.resource_interaction.set_resource_mode(true)
	var before_left_click: Vector2 = main.camera.position
	var left_click := InputEventMouseButton.new()
	left_click.button_index = MOUSE_BUTTON_LEFT
	left_click.pressed = true
	left_click.position = Vector2.ZERO
	main._unhandled_input(left_click)
	_expect(main.camera.position == before_left_click and not main.camera.is_middle_panning(),
		"resource/editor left-click priority remains ahead of camera input")

	main.queue_free()


func _wait_until_idle(terrain, max_frames: int) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	failures.append("terrain streaming did not become idle within %d frames" % max_frames)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

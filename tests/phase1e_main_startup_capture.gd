extends SceneTree
## Verifies that normal main.tscn startup selects the refined Phase 1E path
## without a capture-only toggle and records the ordinary gameplay view.

const OUTPUT_PATH := "res://.artifacts/phase1e_main_startup_1_0x.png"

var demo
var terrain


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	demo = load("res://main.tscn").instantiate()
	root.add_child(demo)
	await _wait_frames(8)
	terrain = demo.terrain
	await _wait_until_idle()
	if not demo.refined_cliff_silhouettes_enabled:
		_fail("main.tscn did not enable Phase 1E")
		return
	if not terrain.is_refined_cliff_silhouettes_enabled():
		_fail("TerrainRenderer did not receive the Phase 1E startup setting")
		return
	var found_refined_mesh: bool = false
	for chunk in terrain.loaded_chunks.values():
		var stats: Dictionary = chunk.get_organic_cliff_geometry_stats()
		found_refined_mesh = found_refined_mesh or int(stats.edge_mesh_count) > 0
		for layer in chunk.cliff_edge_layers:
			if layer != null and layer.visible:
				_fail("legacy cliff edge overlay remained visible at startup")
				return
		for layer in chunk.cliff_shadow_layers:
			if layer != null and layer.visible:
				_fail("legacy cliff shadow remained visible at startup")
				return
	if not found_refined_mesh:
		_fail("normal startup did not build refined edge meshes")
		return
	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.cursor.visible = false
	demo.camera.zoom = Vector2.ONE
	demo.camera.force_update_scroll()
	await _wait_frames(3)
	var image: Image = root.get_texture().get_image()
	if image == null or image.save_png(OUTPUT_PATH) != OK:
		_fail("could not save Phase 1E startup capture")
		return
	print("PHASE1E_MAIN_STARTUP_CAPTURE: PASS")
	quit(0)


func _wait_until_idle(max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if terrain.get_pending_chunk_count() == 0:
			return
	_fail("normal startup streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

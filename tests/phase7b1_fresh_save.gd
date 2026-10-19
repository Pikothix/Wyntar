extends SceneTree
## First half of the fresh-process persistence test. Creates a deterministic
## streamed fixture and leaves its save for phase7b1_fresh_load.gd.

const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")
const WorldSaveService = preload("res://scripts/world_save_service.gd")

const TEST_PATH := "user://saves/phase7b1_fresh_process.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	var terrain = TerrainRenderer.new()
	terrain.world_seed = -77777
	terrain.environment_object_density = 2.0
	terrain.berry_regrowth_seconds = 180.0
	root.add_child(terrain)
	await process_frame
	var routes: Array[Rect2] = [
		Rect2(Vector2(-2200, -1600), Vector2(4400, 3200)),
		Rect2(Vector2(-24000, 14000), Vector2(4400, 3200)),
		Rect2(Vector2(19000, -15000), Vector2(4400, 3200)),
	]
	var by_category: Dictionary = {}
	for route in routes:
		terrain.update_visible_world_rect(route)
		await _wait_until_idle(terrain)
		for resource in terrain.get_loaded_resources():
			by_category[String(resource["category"])] = resource
		if by_category.has("wood") and by_category.has("stone") and by_category.has("food"):
			break
	_expect(by_category.has("wood") and by_category.has("stone") and by_category.has("food"),
		"streamed fresh-process fixture contains every resource category")
	if not failures.is_empty():
		_finish(terrain)
		return

	var edit_cell := Vector2i(-33, 32)
	terrain.apply_world_edit_states([
		{"cell": edit_cell, "kind": "material", "state": {"has_override": true, "value": 6}},
		{"cell": edit_cell, "kind": "elevation", "state": {"has_override": true, "value": 3}},
		{"cell": Vector2i(32, -33), "kind": "elevation", "state": {"has_override": true, "value": 0}},
	])
	for category in ["wood", "stone", "food"]:
		var resource: Dictionary = by_category[category]
		_expect(terrain.designate_resource(int(resource["definition_id"]), resource["anchor"]),
			"%s fixture can be designated" % category)
		_expect(bool(terrain.complete_designated_resource(
			int(resource["definition_id"]), resource["anchor"])["success"]),
			"%s fixture can be completed" % category)
	terrain.advance_resource_time(37.0)

	var camera := Camera2D.new()
	var food: Dictionary = by_category["food"]
	camera.position = Vector2(food["anchor"] * terrain.TILE_SIZE)
	camera.zoom = Vector2.ONE * 1.6
	root.add_child(camera)
	var service = WorldSaveService.new()
	var snapshot: Dictionary = service.capture_snapshot(
		terrain, camera, "fresh-process-world", "Fresh Process World")
	var result: Dictionary = service.save_snapshot(snapshot, TEST_PATH)
	_expect(bool(result.get("ok", false)), "fresh-process fixture save succeeds")
	_expect(int(result.get("size_bytes", 0)) > 0, "fresh-process save has content")
	camera.queue_free()
	_finish(terrain)


func _finish(terrain) -> void:
	terrain.queue_free()
	if failures.is_empty():
		print("PHASE7B1_FRESH_SAVE: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("PHASE7B1_FRESH_SAVE: FAIL (%d)" % failures.size())
		quit(1)


func _wait_until_idle(terrain, max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	failures.append("streaming did not become idle")


func _cleanup() -> void:
	for suffix in ["", ".tmp", ".bak", ".bak.new"]:
		var path: String = ProjectSettings.globalize_path(TEST_PATH + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

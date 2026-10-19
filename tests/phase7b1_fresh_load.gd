extends SceneTree
## Second half of the fresh-process persistence test. Starts with a different
## active Main world, replaces it from disk, then validates rebuilt visuals.

const MainScene = preload("res://main.tscn")
const WorldSaveService = preload("res://scripts/world_save_service.gd")

const TEST_PATH := "user://saves/phase7b1_fresh_process.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main = MainScene.instantiate()
	main.world_seed = 112233
	root.add_child(main)
	await process_frame
	_expect(main.terrain.world_seed == 112233, "different active world exists before load")
	main.editor.begin_stroke(Vector2i(5, 5))
	main.editor.end_stroke()
	_expect(main.editor.can_undo(), "pre-load world has editor history")

	var service = WorldSaveService.new()
	var loaded: Dictionary = service.load_snapshot(TEST_PATH)
	_expect(bool(loaded.get("ok", false)), "fresh process reads and validates saved JSON")
	if not bool(loaded.get("ok", false)):
		_finish(main)
		return
	var snapshot: Dictionary = loaded["snapshot"]
	var result: Dictionary = main._replace_world_from_snapshot(snapshot)
	_expect(bool(result.get("ok", false)), "Main replaces the active world from snapshot")
	_expect(main.terrain.world_seed == -77777, "saved generation config replaces active config")
	_expect(not main.editor.can_undo() and not main.editor.can_redo(),
		"world replacement clears transient editor history")
	_expect(main.terrain.get_world_cell(Vector2i(-33, 32)) == 6
		and main.terrain.get_world_elevation(Vector2i(-33, 32)) == 3,
		"material and elevation edits restore at signed chunk boundary")
	var restored_inventory: Dictionary = main.terrain.get_resource_inventory()
	var saved_inventory: Dictionary = snapshot["resources"]["inventory"]
	_expect(int(restored_inventory["wood"]) == int(saved_inventory["wood"])
		and int(restored_inventory["stone"]) == int(saved_inventory["stone"])
		and int(restored_inventory["food"]) == int(saved_inventory["food"])
		and int(restored_inventory["wood"]) > 0
		and int(restored_inventory["stone"]) > 0
		and int(restored_inventory["food"]) > 0,
		"wood, stone and food totals restore")
	_expect(float(snapshot["resources"]["simulated_time"]) >= 37.0
		and is_equal_approx(main.terrain.resource_state_manager.simulated_time,
			float(snapshot["resources"]["simulated_time"])),
		"saved simulated time restores exactly")

	var records_by_category: Dictionary = {}
	for record in snapshot["resources"]["state_deviations"]:
		records_by_category[String(record["category"])] = record
	_expect(records_by_category.has("wood") and records_by_category.has("stone")
		and records_by_category.has("food"), "all resource deviations restore")
	if records_by_category.size() >= 3:
		var food_record: Dictionary = records_by_category["food"]
		var expected_camera := Vector2(
			float(snapshot["world"]["camera"]["x"]),
			float(snapshot["world"]["camera"]["y"]))
		_expect(main.camera.position.is_equal_approx(expected_camera)
			and is_equal_approx(main.camera.zoom.x, 1.6), "camera position and zoom restore")
		for category in ["wood", "stone", "food"]:
			var record: Dictionary = records_by_category[category]
			var anchor := Vector2i(int(record["x"]), int(record["y"]))
			main.terrain.update_visible_world_rect(Rect2(
				Vector2(anchor * main.terrain.TILE_SIZE) - Vector2(640, 360), Vector2(1280, 720)))
			await _wait_until_idle(main.terrain)
			var visual: Dictionary = main.terrain.get_resource_at_cell(anchor)
			if category == "food":
				_expect(not visual.is_empty() and not bool(visual["ripe"]),
					"harvested bush rebuilds as visible unripe visual")
			else:
				_expect(visual.is_empty(), "%s resource stays absent after rebuilt streaming" % category)

		var food_anchor := Vector2i(int(food_record["x"]), int(food_record["y"]))
		main.terrain.update_visible_world_rect(Rect2(Vector2(90000, 90000), Vector2(1280, 720)))
		await _wait_until_idle(main.terrain)
		main.terrain.update_visible_world_rect(Rect2(
			Vector2(food_anchor * main.terrain.TILE_SIZE) - Vector2(640, 360), Vector2(1280, 720)))
		await _wait_until_idle(main.terrain)
		_expect(not bool(main.terrain.get_resource_at_cell(food_anchor)["ripe"]),
			"restored bush state survives unload and reload")
		var remaining: float = main.terrain.resource_state_manager.get_remaining_regrowth_time(
			int(food_record["definition_id"]), food_anchor)
		main.terrain.advance_resource_time(remaining + 1.0)
		await _wait_until_idle(main.terrain)
		_expect(bool(main.terrain.get_resource_at_cell(food_anchor)["ripe"]),
			"berry regrowth resumes from restored simulated deadline")

	_finish(main)


func _finish(main) -> void:
	main.queue_free()
	_cleanup()
	if failures.is_empty():
		print("PHASE7B1_FRESH_LOAD: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("PHASE7B1_FRESH_LOAD: FAIL (%d)" % failures.size())
		quit(1)


func _wait_until_idle(terrain, max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	failures.append("restored streaming did not become idle")


func _cleanup() -> void:
	for suffix in ["", ".tmp", ".bak", ".bak.new"]:
		var path: String = ProjectSettings.globalize_path(TEST_PATH + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

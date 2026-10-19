extends SceneTree
## Save-format, validation, backup and authoritative round-trip tests.

const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")
const WorldSaveService = preload("res://scripts/world_save_service.gd")
const WorldEditorController = preload("res://scripts/world_editor_controller.gd")

const TEST_PATH := "user://saves/phase7b1_validation.json"
const CORRUPT_PATH := "user://saves/phase7b1_corrupt.json"
const MISSING_PATH := "user://saves/phase7b1_missing.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	var service = WorldSaveService.new()
	var terrain = TerrainRenderer.new()
	terrain.world_seed = -193771
	terrain.biome_frequency = 0.017
	terrain.detail_frequency = 0.061
	terrain.sea_level = 1
	terrain.berry_regrowth_seconds = 120.0
	root.add_child(terrain)
	await process_frame
	var edit_states: Array[Dictionary] = [
		{"cell": Vector2i(-33, 31), "kind": "material", "state": {"has_override": true, "value": 5}},
		{"cell": Vector2i(32, -32), "kind": "material", "state": {"has_override": true, "value": 7}},
		{"cell": Vector2i(-33, 31), "kind": "elevation", "state": {"has_override": true, "value": 3}},
		{"cell": Vector2i(32, -32), "kind": "elevation", "state": {"has_override": true, "value": 1}},
	]
	terrain.apply_world_edit_states(edit_states)
	var tree_anchor := Vector2i(-65, -1)
	var rock_anchor := Vector2i(32, -33)
	var bush_anchor := Vector2i(-32, 32)
	terrain.designate_resource(0, tree_anchor)
	terrain.complete_designated_resource(0, tree_anchor)
	terrain.designate_resource(8, rock_anchor)
	terrain.complete_designated_resource(8, rock_anchor)
	terrain.designate_resource(4, bush_anchor)
	terrain.complete_designated_resource(4, bush_anchor)
	terrain.advance_resource_time(25.0)
	var camera := Camera2D.new()
	camera.position = Vector2(-1040.5, 999.25)
	camera.zoom = Vector2.ONE * 1.75
	root.add_child(camera)

	var snapshot: Dictionary = service.capture_snapshot(
		terrain, camera, "validation-world", "Validation World")
	var validation: Dictionary = service.validate_snapshot(snapshot)
	_expect(bool(validation["ok"]), "valid authoritative snapshot accepted")
	var save_result: Dictionary = service.save_snapshot(snapshot, TEST_PATH)
	_expect(bool(save_result["ok"]), "safe save write succeeds")
	_expect(FileAccess.file_exists(ProjectSettings.globalize_path(TEST_PATH)), "save destination exists")

	var loaded: Dictionary = service.load_snapshot(TEST_PATH)
	_expect(bool(loaded["ok"]), "saved JSON loads and validates")
	if bool(loaded["ok"]):
		var restored = TerrainRenderer.new()
		restored.apply_generation_config(loaded["snapshot"]["world"]["generation"])
		restored.berry_regrowth_seconds = float(loaded["snapshot"]["resources"]["berry_regrowth_seconds"])
		root.add_child(restored)
		await process_frame
		var import_result: Dictionary = restored.import_authoritative_snapshot({
			"terrain": loaded["snapshot"]["terrain"],
			"resources": loaded["snapshot"]["resources"],
		})
		_expect(bool(import_result["ok"]), "validated snapshot imports atomically")
		_expect(restored.world_seed == -193771 and is_equal_approx(restored.biome_frequency, 0.017),
			"saved generation configuration restored before streaming")
		_expect(restored.get_world_cell(Vector2i(-33, 31)) == 5
			and restored.get_world_elevation(Vector2i(-33, 31)) == 3,
			"signed terrain overrides restored")
		_expect(not bool(restored.resource_state_manager.get_snapshot(0, tree_anchor)["available"]),
			"chopped tree state restored")
		_expect(not bool(restored.resource_state_manager.get_snapshot(8, rock_anchor)["available"]),
			"collected rock state restored")
		var restored_bush: Dictionary = restored.resource_state_manager.get_snapshot(4, bush_anchor)
		_expect(not bool(restored_bush["ripe"])
			and restored.resource_state_manager.get_remaining_regrowth_time(4, bush_anchor) > 90.0,
			"berry deadline resumes relative to saved simulated time")
		_expect(restored.get_resource_inventory() == {"wood": 5, "stone": 4, "food": 3},
			"inventory totals restored")
		_expect(restored.resource_state_manager.make_resource_id(0, tree_anchor)
			== terrain.resource_state_manager.make_resource_id(0, tree_anchor),
			"stable resource IDs survive signed-coordinate round trip")
		restored.queue_free()

	var second_snapshot: Dictionary = snapshot.duplicate(true)
	second_snapshot["world"]["display_name"] = "Second Save"
	_expect(bool(service.save_snapshot(second_snapshot, TEST_PATH)["ok"]),
		"second save safely replaces destination")
	var backup: Dictionary = service.load_snapshot(TEST_PATH + ".bak")
	_expect(bool(backup["ok"])
		and String(backup["snapshot"]["world"]["display_name"]) == "Validation World",
		"previous known-good save is preserved as backup")

	_write_text(ProjectSettings.globalize_path(TEST_PATH) + ".tmp", "interrupted temporary data")
	_expect(bool(service.save_snapshot(snapshot, TEST_PATH)["ok"]),
		"stale interrupted temporary file is recoverable")
	_expect(not bool(service.load_snapshot(MISSING_PATH)["ok"]), "missing file rejected")
	_write_text(ProjectSettings.globalize_path(CORRUPT_PATH), "{ definitely not json")
	_expect(not bool(service.load_snapshot(CORRUPT_PATH)["ok"]), "corrupt JSON rejected")

	var unsupported: Dictionary = snapshot.duplicate(true)
	unsupported["format_version"] = 999
	_expect(not bool(service.validate_snapshot(unsupported)["ok"]), "unsupported version rejected")
	var bad_material: Dictionary = snapshot.duplicate(true)
	bad_material["terrain"]["material_overrides"][0]["material_id"] = 999
	_expect(not bool(service.validate_snapshot(bad_material)["ok"]), "invalid material rejected")
	_expect(not bool(service.save_snapshot(bad_material, TEST_PATH)["ok"]),
		"invalid snapshot cannot enter the replacement sequence")
	var preserved_after_failed_save: Dictionary = service.load_snapshot(TEST_PATH)
	_expect(bool(preserved_after_failed_save["ok"])
		and String(preserved_after_failed_save["snapshot"]["world"]["display_name"])
		== "Validation World", "failed save preserves the existing valid destination")
	var bad_elevation: Dictionary = snapshot.duplicate(true)
	bad_elevation["terrain"]["elevation_overrides"][0]["elevation"] = 9
	_expect(not bool(service.validate_snapshot(bad_elevation)["ok"]), "invalid elevation rejected")
	var negative_inventory: Dictionary = snapshot.duplicate(true)
	negative_inventory["resources"]["inventory"]["wood"] = -1
	_expect(not bool(service.validate_snapshot(negative_inventory)["ok"]), "negative inventory rejected")
	var bad_resource: Dictionary = snapshot.duplicate(true)
	bad_resource["resources"]["state_deviations"][0]["resource_id"] = "forged"
	_expect(not bool(service.validate_snapshot(bad_resource)["ok"]), "invalid resource record rejected")
	var duplicate_resource: Dictionary = snapshot.duplicate(true)
	duplicate_resource["resources"]["state_deviations"].append(
		duplicate_resource["resources"]["state_deviations"][0].duplicate(true))
	_expect(not bool(service.validate_snapshot(duplicate_resource)["ok"]),
		"duplicate resource record rejected")

	var active_material_before: int = terrain.get_world_cell(Vector2i(-33, 31))
	var invalid_result: Dictionary = service.validate_snapshot(bad_material)
	_expect(not bool(invalid_result["ok"])
		and terrain.get_world_cell(Vector2i(-33, 31)) == active_material_before,
		"invalid validation leaves active world unchanged")

	var editor = WorldEditorController.new()
	editor.configure(terrain)
	editor.begin_stroke(Vector2i(7, 7))
	editor.end_stroke()
	_expect(editor.can_undo(), "editor fixture created history")
	editor.reset_runtime_state()
	_expect(not editor.can_undo() and not editor.can_redo(), "load reset clears editor history")

	terrain.queue_free()
	camera.queue_free()
	_cleanup()
	if failures.is_empty():
		print("PHASE7B1_VALIDATION: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("PHASE7B1_VALIDATION: FAIL (%d)" % failures.size())
		quit(1)


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(text)
	file.close()


func _cleanup() -> void:
	for path in [TEST_PATH, TEST_PATH + ".tmp", TEST_PATH + ".bak", TEST_PATH + ".bak.new", CORRUPT_PATH]:
		var absolute: String = ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(absolute):
			DirAccess.remove_absolute(absolute)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

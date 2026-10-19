extends SceneTree
## Phase 7B.1 save/load timing and size measurements for sparse clean and
## heavily edited authoritative worlds. Values are diagnostic, not thresholds.

const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")
const WorldSaveService = preload("res://scripts/world_save_service.gd")

const CLEAN_PATH := "user://saves/phase7b1_benchmark_clean.json"
const HEAVY_PATH := "user://saves/phase7b1_benchmark_heavy.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	var clean = TerrainRenderer.new()
	clean.world_seed = -404040
	root.add_child(clean)
	await process_frame
	var camera := Camera2D.new()
	camera.position = Vector2(-1024, 768)
	root.add_child(camera)
	var clean_metrics: Dictionary = await _measure(clean, camera, CLEAN_PATH, "clean")

	var heavy = TerrainRenderer.new()
	heavy.world_seed = -404040
	heavy.berry_regrowth_seconds = 1200.0
	root.add_child(heavy)
	await process_frame
	var edits: Array[Dictionary] = []
	for index in range(4000):
		var x: int = (index % 100) - 50
		var y: int = (index / 100) - 20
		var cell := Vector2i(x, y)
		edits.append({
			"cell": cell, "kind": "material",
			"state": {"has_override": true, "value": index % 8},
		})
		edits.append({
			"cell": cell, "kind": "elevation",
			"state": {"has_override": true, "value": index % 4},
		})
	heavy.apply_world_edit_states(edits)
	for index in range(300):
		var definition_id: int = [0, 8, 4][index % 3]
		var anchor := Vector2i(-600 + index * 4, -700 + index * 3)
		heavy.designate_resource(definition_id, anchor)
		if index % 2 == 0:
			heavy.complete_designated_resource(definition_id, anchor)
	heavy.advance_resource_time(25.0)
	var heavy_metrics: Dictionary = await _measure(heavy, camera, HEAVY_PATH, "heavy")

	_expect(int(clean_metrics.get("size_bytes", 0)) < int(heavy_metrics.get("size_bytes", 0)),
		"heavily edited save is larger than sparse clean save")
	print("PHASE7B1_BENCHMARK clean=%s" % JSON.stringify(clean_metrics))
	print("PHASE7B1_BENCHMARK heavy=%s" % JSON.stringify(heavy_metrics))
	clean.queue_free()
	heavy.queue_free()
	camera.queue_free()
	_cleanup()
	if failures.is_empty():
		print("PHASE7B1_BENCHMARK: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("PHASE7B1_BENCHMARK: FAIL (%d)" % failures.size())
		quit(1)


func _measure(terrain, camera: Camera2D, path: String, label: String) -> Dictionary:
	var service = WorldSaveService.new()
	var snapshot_start: int = Time.get_ticks_usec()
	var snapshot: Dictionary = service.capture_snapshot(
		terrain, camera, "benchmark-%s" % label, "Benchmark %s" % label.capitalize())
	var snapshot_usec: int = Time.get_ticks_usec() - snapshot_start
	var save_result: Dictionary = service.save_snapshot(snapshot, path)
	_expect(bool(save_result.get("ok", false)), "%s benchmark save succeeds" % label)
	var load_result: Dictionary = service.load_snapshot(path)
	_expect(bool(load_result.get("ok", false)), "%s benchmark load succeeds" % label)
	if not bool(load_result.get("ok", false)):
		return {}
	var restored = TerrainRenderer.new()
	restored.apply_generation_config(load_result["snapshot"]["world"]["generation"])
	restored.berry_regrowth_seconds = float(
		load_result["snapshot"]["resources"]["berry_regrowth_seconds"])
	root.add_child(restored)
	var restore_start: int = Time.get_ticks_usec()
	var import_result: Dictionary = restored.import_authoritative_snapshot({
		"terrain": load_result["snapshot"]["terrain"],
		"resources": load_result["snapshot"]["resources"],
	})
	var restore_usec: int = Time.get_ticks_usec() - restore_start
	_expect(bool(import_result.get("ok", false)), "%s authority restoration succeeds" % label)
	var regeneration_start: int = Time.get_ticks_usec()
	restored.update_visible_world_rect(Rect2(Vector2(-640, -360), Vector2(1280, 720)))
	await _wait_until_idle(restored)
	var regeneration_usec: int = Time.get_ticks_usec() - regeneration_start
	var metrics := {
		"snapshot_ms": snapshot_usec / 1000.0,
		"serialization_ms": int(save_result.get("serialization_usec", 0)) / 1000.0,
		"disk_write_ms": int(save_result.get("write_usec", 0)) / 1000.0,
		"load_validation_ms": int(load_result.get("validation_usec", 0)) / 1000.0,
		"load_total_ms": int(load_result.get("load_usec", 0)) / 1000.0,
		"restoration_ms": restore_usec / 1000.0,
		"initial_regeneration_ms": regeneration_usec / 1000.0,
		"size_bytes": int(load_result.get("size_bytes", 0)),
		"material_overrides": terrain.get_override_count(),
		"elevation_overrides": terrain.get_height_override_count(),
		"resource_deviations": terrain.resource_state_manager.get_modified_state_count(),
	}
	restored.queue_free()
	return metrics


func _wait_until_idle(terrain, max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	failures.append("benchmark chunk regeneration did not become idle")


func _cleanup() -> void:
	for base_path in [CLEAN_PATH, HEAVY_PATH]:
		for suffix in ["", ".tmp", ".bak", ".bak.new"]:
			var path: String = ProjectSettings.globalize_path(base_path + suffix)
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

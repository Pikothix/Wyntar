extends SceneTree
## Repeatable Phase 8B interaction benchmark. Reports full-frame percentiles,
## batch submission cost, sparse-state memory and scheduler overruns.

const SAMPLE_FRAMES: int = 60

var demo
var terrain
var interaction
var resources: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	demo = load("res://main.tscn").instantiate()
	root.add_child(demo)
	await _wait_frames(6)
	terrain = demo.terrain
	interaction = demo.resource_interaction
	interaction.set_resource_mode(true)
	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.camera.position = Vector2(Vector2i(16, 16) * terrain.TILE_SIZE)
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	await _wait_until_idle()

	await _sample_mode("camera_streaming", func(frame: int) -> void:
		demo.camera.position += Vector2(6.0, 2.0)
		demo.camera.force_update_scroll())

	terrain.environment_object_context["density"] = 2.0
	terrain._invalidate_streamed_chunks()
	await _wait_until_idle()
	resources = terrain.get_loaded_resources()
	assert(not resources.is_empty(), "Benchmark requires loaded resources")

	await _sample_mode("resource_selection", func(frame: int) -> void:
		interaction.select_at(resources[frame % resources.size()]["anchor"]))

	var designatable: Array[Dictionary] = resources.slice(0, mini(30, resources.size()))
	await _sample_mode("multi_designation", func(frame: int) -> void:
		if frame < designatable.size():
			var resource: Dictionary = designatable[frame]
			terrain.designate_resource(int(resource["definition_id"]), resource["anchor"]))
	for resource in designatable:
		terrain.cancel_resource_designation(int(resource["definition_id"]), resource["anchor"])

	var trees := _resources_for("wood", 12)
	await _sample_mode("tree_harvest_group", func(frame: int) -> void:
		if frame < trees.size():
			var resource: Dictionary = trees[frame]
			terrain.designate_resource(int(resource["definition_id"]), resource["anchor"])
			terrain.complete_designated_resource(int(resource["definition_id"]), resource["anchor"]))

	var rocks := _resources_for("stone", 12)
	await _sample_mode("rock_collection_group", func(frame: int) -> void:
		if frame < rocks.size():
			var resource: Dictionary = rocks[frame]
			terrain.designate_resource(int(resource["definition_id"]), resource["anchor"])
			terrain.complete_designated_resource(int(resource["definition_id"]), resource["anchor"]))

	var bushes := _resources_for("food", 12)
	await _sample_mode("berry_harvest_group", func(frame: int) -> void:
		if frame < bushes.size():
			var resource: Dictionary = bushes[frame]
			terrain.designate_resource(int(resource["definition_id"]), resource["anchor"])
			terrain.complete_designated_resource(int(resource["definition_id"]), resource["anchor"]))
	await _sample_mode("berry_regrowth", func(frame: int) -> void:
		if frame == 0:
			terrain.advance_resource_time(demo.berry_regrowth_seconds))

	var return_position: Vector2 = demo.camera.position
	await _sample_mode("depleted_chunk_reload", func(frame: int) -> void:
		if frame == 0:
			demo.camera.position = Vector2(90000, 90000)
			demo.camera.force_update_scroll()
		elif frame == 30:
			demo.camera.position = return_position
			demo.camera.force_update_scroll())
	await _wait_until_idle()

	resources = terrain.get_loaded_resources()
	var editable: Dictionary = resources[0]
	var anchor: Vector2i = editable["anchor"]
	var original_state: Dictionary = terrain.get_world_material_override_state(anchor)
	await _sample_mode("terrain_edit_near_resource", func(frame: int) -> void:
		if frame == 0:
			_apply_material_state(anchor, {"has_override": true, "value": 0})
		elif frame == 30:
			_apply_material_state(anchor, original_state))
	await _wait_until_idle()

	var totals: Dictionary = terrain.get_resource_inventory()
	print("PHASE8B_TOTALS wood=%d stone=%d food=%d modified_states=%d state_memory_bytes=%d" % [
		int(totals["wood"]), int(totals["stone"]), int(totals["food"]),
		int(terrain.get_resource_state_metrics()["modified_states"]),
		int(terrain.get_resource_state_metrics()["memory_bytes"]),
	])
	print("PHASE8B_BENCHMARK: PASS")
	quit(0)


func _sample_mode(label: String, action: Callable) -> void:
	var frame_times: Array[float] = []
	var submission_times: Array[float] = []
	var overruns_before: int = terrain.chunk_processing_overrun_frames
	var previous_usec: int = Time.get_ticks_usec()
	for frame in range(SAMPLE_FRAMES):
		terrain.environment_object_renderer.last_submission_usec = 0
		action.call(frame)
		submission_times.append(
			float(terrain.environment_object_renderer.last_submission_usec) / 1000.0)
		await process_frame
		var now_usec: int = Time.get_ticks_usec()
		frame_times.append(float(now_usec - previous_usec) / 1000.0)
		previous_usec = now_usec
	_print_metrics(
		label, frame_times, submission_times,
		terrain.chunk_processing_overrun_frames - overruns_before)


func _resources_for(category: String, maximum: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for resource in resources:
		if String(resource["category"]) == category and bool(resource["available"]):
			result.append(resource)
			if result.size() >= maximum:
				break
	return result


func _apply_material_state(anchor: Vector2i, state: Dictionary) -> void:
	var edits: Array[Dictionary] = [{
		"cell": anchor, "kind": "material", "state": state,
	}]
	terrain.apply_world_edit_states(edits)


func _print_metrics(
		label: String, frame_times: Array[float],
		submission_times: Array[float], overruns: int) -> void:
	frame_times.sort()
	submission_times.sort()
	var total: float = 0.0
	for value in frame_times:
		total += value
	var submission_total: float = 0.0
	for value in submission_times:
		submission_total += value
	var state_metrics: Dictionary = terrain.get_resource_state_metrics()
	print("PHASE8B_MODE mode=%s frames=%d avg_ms=%.3f p95_ms=%.3f p99_ms=%.3f worst_ms=%.3f submission_avg_ms=%.3f submission_p95_ms=%.3f state_memory_bytes=%d modified_states=%d overruns=%d" % [
		label, frame_times.size(), total / frame_times.size(),
		_percentile(frame_times, 0.95), _percentile(frame_times, 0.99), frame_times[-1],
		submission_total / submission_times.size(), _percentile(submission_times, 0.95),
		int(state_metrics["memory_bytes"]), int(state_metrics["modified_states"]), overruns])


func _percentile(values: Array[float], percentile: float) -> float:
	return values[clampi(ceili(values.size() * percentile) - 1, 0, values.size() - 1)]


func _wait_until_idle(max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	assert(false, "Benchmark streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame

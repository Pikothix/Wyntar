extends SceneTree
## Phase 8B validation for sparse authoritative resource state, single-credit
## completion, simulated-time regrowth, interaction isolation and streaming.

const ResourceStateManager = preload("res://scripts/resource_state_manager.gd")
const ResourceInteractionController = preload("res://scripts/resource_interaction_controller.gd")
const EnvironmentObjectCatalog = preload("res://scripts/environment_object_catalog.gd")
const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_authoritative_state_manager()
	await _test_streamed_integration()
	if failures.is_empty():
		print("PHASE8B_VALIDATION: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("PHASE8B_VALIDATION: FAIL (%d)" % failures.size())
		quit(1)


func _test_authoritative_state_manager() -> void:
	var manager = ResourceStateManager.new()
	manager.configure(84521, EnvironmentObjectCatalog.build_by_id(), 10.0)
	var negative_anchor := Vector2i(-37, -91)
	var stable_id: String = manager.make_resource_id(0, negative_anchor)
	_expect(stable_id == manager.make_resource_id(0, negative_anchor),
		"signed-coordinate resource IDs are stable")
	_expect(stable_id != manager.make_resource_id(0, Vector2i(37, 91)),
		"signed-coordinate resource IDs do not alias")
	_expect(manager.get_modified_state_count() == 0,
		"reading procedural baseline resources does not allocate sparse state")

	_expect(manager.designate(0, negative_anchor), "tree can be designated")
	var tree_result: Dictionary = manager.complete_designated_harvest(0, negative_anchor)
	_expect(bool(tree_result["success"]) and int(tree_result["quantity"]) == 5,
		"tree completion credits catalog wood yield")
	_expect(not bool(manager.complete_designated_harvest(0, negative_anchor)["success"]),
		"tree cannot credit inventory twice")
	_expect(not bool(manager.get_snapshot(0, negative_anchor)["available"]),
		"chopped tree remains depleted")

	var rock_anchor := Vector2i(18, -22)
	manager.designate(8, rock_anchor)
	var rock_result: Dictionary = manager.complete_designated_harvest(8, rock_anchor)
	_expect(bool(rock_result["success"]) and int(rock_result["quantity"]) == 4,
		"rock collection credits catalog stone yield")

	var bush_anchor := Vector2i(-9, 12)
	manager.designate(4, bush_anchor)
	var bush_result: Dictionary = manager.complete_designated_harvest(4, bush_anchor)
	_expect(bool(bush_result["success"]) and int(bush_result["quantity"]) == 3,
		"berry harvest credits authoritative food yield")
	_expect(not bool(manager.get_snapshot(4, bush_anchor)["ripe"]),
		"harvested bush becomes unripe")
	_expect(manager.advance_simulated_time(9.9) == 0,
		"berries do not regrow before simulated deadline")
	_expect(manager.advance_simulated_time(0.1) == 1,
		"berries regrow at simulated deadline while unloaded")
	_expect(bool(manager.get_snapshot(4, bush_anchor)["ripe"]),
		"regrown bush restores procedural baseline")
	var totals: Dictionary = manager.get_inventory()
	_expect(totals == {"wood": 5, "stone": 4, "food": 3},
		"inventory totals are authoritative and non-negative")


func _test_streamed_integration() -> void:
	var terrain = TerrainRenderer.new()
	terrain.environment_object_density = 2.0
	terrain.berry_regrowth_seconds = 1000.0
	root.add_child(terrain)
	await process_frame
	var routes: Array[Rect2] = [
		Rect2(Vector2(-1600, -1000), Vector2(3200, 2000)),
		Rect2(Vector2(18000, -12000), Vector2(3200, 2000)),
		Rect2(Vector2(-22000, 15000), Vector2(3200, 2000)),
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
		"streamed fixtures contain all three resource behaviours")
	if not (by_category.has("wood") and by_category.has("stone") and by_category.has("food")):
		terrain.queue_free()
		return

	var interaction = ResourceInteractionController.new()
	interaction.configure(terrain)
	interaction.set_resource_mode(true)
	var material_edits_before: int = terrain.get_override_count()
	var height_edits_before: int = terrain.get_height_override_count()
	var tree: Dictionary = by_category["wood"]
	_expect(interaction.select_at(tree["anchor"]), "resource click selects tree")
	_expect(interaction.designate_selected(), "selected tree can be designated")
	_expect(terrain.get_override_count() == material_edits_before
		and terrain.get_height_override_count() == height_edits_before,
		"selection and designation do not paint terrain")
	var tree_id: String = String(tree["resource_id"])
	var tree_result: Dictionary = interaction.debug_complete_selected()
	_expect(bool(tree_result["success"]), "debug completion uses authoritative completion API")
	_expect(terrain.get_resource_at_cell(tree["anchor"]).is_empty(),
		"chopped tree disappears from visible batches")

	var rock: Dictionary = by_category["stone"]
	interaction.select_at(rock["anchor"])
	interaction.designate_selected()
	var rock_result: Dictionary = interaction.debug_complete_selected()
	_expect(bool(rock_result["success"]), "designated rock can be collected")
	_expect(terrain.get_resource_at_cell(rock["anchor"]).is_empty(),
		"collected rock disappears")

	var bush: Dictionary = by_category["food"]
	interaction.select_at(bush["anchor"])
	interaction.designate_selected()
	var bush_result: Dictionary = interaction.debug_complete_selected()
	_expect(bool(bush_result["success"]), "designated berries can be harvested")
	var depleted_bush: Dictionary = terrain.get_resource_at_cell(bush["anchor"])
	_expect(not depleted_bush.is_empty() and not bool(depleted_bush["ripe"]),
		"depleted berry bush remains visible and unripe")
	terrain.advance_resource_time(1000.0)
	var ripe_bush: Dictionary = terrain.get_resource_at_cell(bush["anchor"])
	_expect(not ripe_bush.is_empty() and bool(ripe_bush["ripe"]),
		"berry visual returns to ripe after simulated time")

	terrain.update_visible_world_rect(Rect2(Vector2(90000, 90000), Vector2(1280, 720)))
	await _wait_until_idle(terrain)
	terrain.update_visible_world_rect(Rect2(Vector2(tree["anchor"] * terrain.TILE_SIZE), Vector2(1280, 720)))
	await _wait_until_idle(terrain)
	_expect(not bool(terrain.resource_state_manager.get_snapshot(
		int(tree["definition_id"]), tree["anchor"])["available"]),
		"chopped tree stays absent across chunk unload/reload")
	_expect(terrain.resource_state_manager.make_resource_id(
		int(tree["definition_id"]), tree["anchor"]) == tree_id,
		"resource identity survives streaming")

	var editable: Dictionary = {}
	for resource in terrain.get_loaded_resources():
		if bool(resource["available"]):
			editable = resource
			break
	if not editable.is_empty():
		var anchor: Vector2i = editable["anchor"]
		var definition_id: int = int(editable["definition_id"])
		var original_material_state: Dictionary = terrain.get_world_material_override_state(anchor)
		terrain.designate_resource(definition_id, anchor)
		terrain.apply_world_edit_states([{
			"cell": anchor, "kind": "material",
			"state": {"has_override": true, "value": 0},
		}])
		await _wait_until_idle(terrain)
		_expect(terrain.get_resource_at_cell(anchor).is_empty(),
			"incompatible water edit removes resource without floating")
		_expect(not bool(terrain.resource_state_manager.get_snapshot(
			definition_id, anchor)["designated"]),
			"terrain invalidation cancels missing designation")
		terrain.apply_world_edit_states([{
			"cell": anchor, "kind": "material", "state": original_material_state,
		}])
		await _wait_until_idle(terrain)
		var restored: Dictionary = terrain.get_resource_at_cell(anchor)
		_expect(not restored.is_empty() and String(restored["resource_id"]) == String(editable["resource_id"]),
			"undo-equivalent terrain restoration preserves stable resource identity")

	var totals: Dictionary = terrain.get_resource_inventory()
	_expect(int(totals["wood"]) > 0 and int(totals["stone"]) > 0 and int(totals["food"]) > 0,
		"integrated inventory receives all resource categories")
	terrain.queue_free()


func _wait_until_idle(terrain, max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	failures.append("streaming or edit refresh did not become idle")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

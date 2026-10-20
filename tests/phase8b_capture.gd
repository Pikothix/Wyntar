extends SceneTree
## Graphical evidence for designation, removal, inventory credit and berry
## ripe/unripe presentation using the real interaction and completion APIs.

const OUTPUT_DIR := "res://.artifacts"

var demo
var terrain


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	demo = load("res://main.tscn").instantiate()
	root.add_child(demo)
	await _wait_frames(6)
	terrain = demo.terrain
	demo.editor_panel.visible = false
	demo.compact_hud_enabled = false
	demo._apply_hud_mode()
	demo.resource_interaction.set_resource_mode(true)
	demo._update_resource_mode_label()
	terrain.environment_object_context["density"] = 2.0
	terrain._invalidate_streamed_chunks()

	var resources: Dictionary = await _find_resource_categories()
	assert(resources.has("wood") and resources.has("stone") and resources.has("food"),
		"Capture routes must contain wood, stone and food resources")

	var tree: Dictionary = resources["wood"]
	await _focus_resource(tree)
	demo.resource_interaction.select_at(tree["anchor"])
	demo.resource_interaction.designate_selected()
	await _capture("phase8b_tree_designated")
	demo.resource_interaction.debug_complete_selected()
	await _wait_frames(3)
	await _capture("phase8b_tree_chopped_inventory")

	var rock: Dictionary = resources["stone"]
	await _focus_resource(rock)
	demo.resource_interaction.select_at(rock["anchor"])
	demo.resource_interaction.designate_selected()
	await _capture("phase8b_rock_designated")
	demo.resource_interaction.debug_complete_selected()
	await _wait_frames(3)
	await _capture("phase8b_rock_collected_inventory")

	var bush: Dictionary = resources["food"]
	await _focus_resource(bush)
	demo.resource_interaction.select_at(bush["anchor"])
	demo.resource_interaction.designate_selected()
	await _capture("phase8b_berry_bush_ripe_designated")
	demo.resource_interaction.debug_complete_selected()
	await _wait_frames(3)
	await _capture("phase8b_berry_bush_unripe")
	terrain.advance_resource_time(demo.berry_regrowth_seconds)
	demo.resource_interaction.refresh_selected()
	await _wait_frames(3)
	await _capture("phase8b_berry_bush_regrown")

	print("PHASE8B_GRAPHICAL_CAPTURE: PASS")
	quit(0)


func _find_resource_categories() -> Dictionary:
	var found: Dictionary = {}
	var routes: Array[Rect2] = [
		Rect2(Vector2(-1600, -1000), Vector2(3200, 2000)),
		Rect2(Vector2(18000, -12000), Vector2(3200, 2000)),
		Rect2(Vector2(-22000, 15000), Vector2(3200, 2000)),
	]
	for route in routes:
		terrain.update_visible_world_rect(route)
		await _wait_until_idle()
		for resource in terrain.get_loaded_resources():
			found[String(resource["category"])] = resource
		if found.has("wood") and found.has("stone") and found.has("food"):
			break
	return found


func _focus_resource(resource: Dictionary) -> void:
	demo.camera.position = (
		Vector2(resource["anchor"] * terrain.TILE_SIZE)
		+ Vector2(16, 16)
		- Vector2(120, 0))
	demo.camera.zoom = Vector2.ONE * 2.0
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	await _wait_until_idle()
	await _wait_frames(3)


func _capture(label: String) -> void:
	await _wait_frames(2)
	var error: Error = root.get_texture().get_image().save_png(
		"%s/%s.png" % [OUTPUT_DIR, label])
	assert(error == OK, "Could not save %s" % label)


func _wait_until_idle(max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	assert(false, "Streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame

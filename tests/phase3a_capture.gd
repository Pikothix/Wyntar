extends SceneTree
## Phase 3A family showcase plus identical procedural/legacy gameplay framing.

const ProcTrees = preload("res://scripts/procgen/proc_trees.gd")
const OUTPUT_DIR := "res://screenshots"

var demo
var terrain


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_create_family_showcase()
	DisplayServer.window_set_size(Vector2i(1280, 720))
	demo = load("res://main.tscn").instantiate()
	demo.environment_object_density = 2.0
	root.add_child(demo)
	await _wait_frames(8)
	terrain = demo.terrain
	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.cursor.visible = false
	await _create_curated_forest_fixture()
	terrain.set_procedural_vegetation_enabled(false)
	await _wait_frames(3)
	await _save("phase3a_existing_tree_assets_ab_1_0x")
	terrain.set_procedural_vegetation_enabled(true)
	await _wait_frames(3)
	await _save("phase3a_procedural_tree_assets_ab_1_0x")
	await _create_natural_gameplay_fixture()
	await _save("phase3a_natural_gameplay_forest_1_0x")
	print("PHASE3A_GRAPHICAL_CAPTURE: PASS")
	quit(0)


func _create_family_showcase() -> void:
	var showcase := Image.create(1280, 720, false, Image.FORMAT_RGBA8)
	showcase.fill(Color("18232a"))
	showcase.fill_rect(Rect2i(28, 28, 596, 664), Color("26363a"))
	showcase.fill_rect(Rect2i(656, 28, 596, 664), Color("222f38"))
	for family_index in range(2):
		var archetype: String = "deciduous" if family_index == 0 else "conifer"
		var panel_x: int = 48 if family_index == 0 else 676
		for variant in range(12):
			var generated: Dictionary = ProcTrees.generate_tree(
				31001 + variant * 7919, 32, archetype, "GRASS", "large", "mature")
			var sprite: Image = generated.canvas.to_image()
			sprite.resize(sprite.get_width() * 2, sprite.get_height() * 2, Image.INTERPOLATE_NEAREST)
			var column: int = variant % 4
			var row: int = variant / 4
			var cell_origin := Vector2i(panel_x + column * 142, 66 + row * 205)
			_draw_showcase_shadow(showcase, cell_origin + Vector2i(70, 145), sprite.get_width())
			showcase.blend_rect(
				sprite, Rect2i(Vector2i.ZERO, sprite.get_size()),
				cell_origin + Vector2i(70 - sprite.get_width() / 2, 145 - sprite.get_height()))
	var error: Error = showcase.save_png("%s/phase3a_tree_family_showcase.png" % OUTPUT_DIR)
	assert(error == OK, "Could not save Phase 3A family showcase")


func _draw_showcase_shadow(image: Image, center: Vector2i, sprite_width: int) -> void:
	var radius_x: int = clampi(sprite_width / 3, 12, 32)
	var radius_y: int = maxi(4, radius_x / 4)
	for y in range(-radius_y, radius_y + 1):
		for x in range(-radius_x, radius_x + 1):
			if (float(x * x) / float(radius_x * radius_x)
					+ float(y * y) / float(radius_y * radius_y)) <= 1.0:
				image.set_pixel(center.x + x + 6, center.y + y, Color8(8, 12, 12, 92))


func _create_curated_forest_fixture() -> void:
	terrain.set_environment_object_generation_enabled(false)
	var origin := Vector2i(384, 384)
	_fill(origin, Vector2i(32, 16), 3, 0)
	_fill(origin + Vector2i(0, 16), Vector2i(32, 16), 3, 1)
	terrain._invalidate_streamed_chunks()
	await _move_camera(origin + Vector2i(16, 16))
	var anchors: Array[Vector2i] = [
		origin + Vector2i(5, 11), origin + Vector2i(11, 14),
		origin + Vector2i(17, 11), origin + Vector2i(23, 14),
		origin + Vector2i(28, 11), origin + Vector2i(5, 21),
		origin + Vector2i(11, 24), origin + Vector2i(17, 21),
		origin + Vector2i(23, 24), origin + Vector2i(28, 21),
	]
	var ids := PackedInt32Array()
	var variants := PackedByteArray()
	var anchor_x := PackedInt32Array()
	var anchor_y := PackedInt32Array()
	var heights := PackedByteArray()
	for index in range(anchors.size()):
		ids.append(0 if index % 3 == 0 else (1 if index % 3 == 1 else 2))
		variants.append(index % (4 if index % 3 != 1 else 3))
		anchor_x.append(anchors[index].x)
		anchor_y.append(anchors[index].y)
		heights.append(0 if anchors[index].y < origin.y + 16 else 1)
	terrain.environment_object_renderer.set_chunk_objects(
		terrain.world_cell_to_chunk(origin), ids, variants, anchor_x, anchor_y, heights)
	terrain.environment_object_renderer.flush_pending()
	await _wait_frames(4)


func _create_natural_gameplay_fixture() -> void:
	var origin := Vector2i(512, 512)
	_fill(origin, Vector2i(48, 40), 3, 0)
	_fill(origin + Vector2i(8, 18), Vector2i(32, 22), 3, 1)
	_fill(origin + Vector2i(18, 28), Vector2i(15, 12), 5, 2)
	terrain.set_environment_object_generation_enabled(true)
	terrain._invalidate_streamed_chunks()
	await _move_camera(origin + Vector2i(24, 20))


func _fill(origin: Vector2i, size: Vector2i, terrain_id: int, elevation: int) -> void:
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			var pos := Vector2i(x, y)
			terrain.world.set_override(pos, terrain_id)
			terrain.world.set_elevation_override(pos, elevation)


func _move_camera(cell: Vector2i) -> void:
	demo.camera.position = Vector2(cell * terrain.TILE_SIZE) + Vector2(16, 16)
	demo.camera.zoom = Vector2.ONE
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	await _wait_until_idle()
	demo.camera.force_update_scroll()
	await _wait_frames(3)


func _save(label: String) -> void:
	var path: String = "%s/%s.png" % [OUTPUT_DIR, label]
	var error: Error = root.get_texture().get_image().save_png(path)
	assert(error == OK, "Could not save %s" % path)


func _wait_until_idle(max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_chunk_retirement_count() == 0):
			return
	assert(false, "Phase 3A capture did not settle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame

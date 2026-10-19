extends SceneTree
## Phase 7C.3 validation for raised-liquid editing, explicit ground picking,
## save-compatible authority, signed chunk seams, and connected cliff artwork.

const Catalog = preload("res://scripts/terrain_catalog.gd")
const EditorController = preload("res://scripts/world_editor_controller.gd")
const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")

var failures: Array[String] = []
var terrain
var editor


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	terrain = TerrainRenderer.new()
	terrain.sea_level = 0
	root.add_child(terrain)
	await process_frame
	editor = EditorController.new()
	editor.configure(terrain)
	_test_liquid_and_land_semantics()
	_test_operation_orders_and_history()
	_test_ground_picking()
	_test_signed_chunk_edges()
	_test_save_compatibility()
	_test_cliff_atlas_connections()
	terrain.queue_free()
	if failures.is_empty():
		print("PHASE7C3_VALIDATION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE7C3_VALIDATION: FAIL (%d)" % failures.size())
	quit(1)


func _test_liquid_and_land_semantics() -> void:
	var cell := Vector2i(12, -7)
	terrain.world.set_override(cell, 0)
	terrain.world.set_elevation_override(cell, 0)
	_expect(terrain.get_world_cell(cell) == 0, "water remains authoritative material")
	_expect(terrain.get_world_visible_cell(cell) == 0, "submerged water renders as liquid")
	_expect(terrain.get_world_visible_liquid_elevation(cell) == 0,
		"visible liquid remains fixed at sea level")
	var raised_height: int = 1 if terrain.generator.get_elevation(cell) != 1 else 2
	terrain.world.set_elevation_override(cell, raised_height)
	_expect(terrain.get_world_cell(cell) == 0,
		"raising ground does not silently change authoritative material")
	_expect(terrain.get_world_elevation(cell) == raised_height, "raised ground remains authoritative")
	_expect(terrain.get_world_visible_cell(cell) == 1,
		"raised liquid cell exposes its declared sand substrate")
	_expect(terrain.get_world_surface_elevation(cell) == raised_height,
		"exposed ground renders at its authoritative elevation")
	_expect(terrain.get_world_visible_liquid_elevation(cell) == -1,
		"liquid surface does not rise with the seabed")
	terrain.world.set_elevation_override(cell, 0)
	_expect(terrain.get_world_visible_cell(cell) == 0,
		"lowered exposed substrate becomes water again")


func _test_operation_orders_and_history() -> void:
	var material_first := Vector2i(20, 20)
	terrain.world.set_override(material_first, 0)
	terrain.world.set_elevation_override(material_first, 0)
	editor.edit_mode = EditorController.EditMode.MATERIAL
	editor.selected_material = 1
	editor.begin_stroke(material_first)
	editor.end_stroke()
	_expect(terrain.get_world_cell(material_first) == 1, "sand paint applies before raising")
	_expect(terrain.get_world_elevation(material_first) == 0,
		"painting sand does not alter ground height")
	editor.edit_mode = EditorController.EditMode.ELEVATION
	editor.elevation_tool = EditorController.ElevationTool.RAISE
	editor.begin_stroke(material_first)
	editor.end_stroke()
	editor.begin_stroke(material_first)
	editor.end_stroke()
	_expect(terrain.get_world_elevation(material_first) == 2,
		"the same ground cell raises to height two")
	_expect(editor.undo() and terrain.get_world_elevation(material_first) == 1,
		"undo restores the previous elevation")
	_expect(editor.redo() and terrain.get_world_elevation(material_first) == 2,
		"redo restores the raised island")

	var elevation_first := Vector2i(22, 20)
	terrain.world.set_override(elevation_first, 0)
	terrain.world.set_elevation_override(elevation_first, 0)
	editor.begin_stroke(elevation_first)
	editor.end_stroke()
	_expect(terrain.get_world_cell(elevation_first) == 0,
		"elevation-first workflow keeps water authoritative")
	_expect(terrain.get_world_visible_cell(elevation_first) == 1,
		"elevation-first workflow visibly exposes substrate")
	editor.edit_mode = EditorController.EditMode.MATERIAL
	editor.selected_material = 1
	editor.begin_stroke(elevation_first)
	editor.end_stroke()
	_expect(terrain.get_world_elevation(elevation_first) == 1,
		"painting after raising preserves elevation")


func _test_ground_picking() -> void:
	for cell in [Vector2i(8, 9), Vector2i(-9, -8)]:
		var pixel := Vector2(cell * terrain.TILE_SIZE) + Vector2(4, 4)
		var pick: Dictionary = terrain.pick_world_position(pixel, true)
		_expect(pick.cell == cell, "ground picking preserves logical coordinates at %s" % cell)
		_expect(bool(pick.targets_ground), "ground picking reports its deliberate target")
		_expect(pick.has("material_id") and pick.has("ground_elevation")
			and pick.has("liquid_elevation"), "pick diagnostics expose material/ground/liquid")


func _test_signed_chunk_edges() -> void:
	for cell in [Vector2i(31, 4), Vector2i(32, 4), Vector2i(-1, -4), Vector2i(0, -4)]:
		terrain.world.set_override(cell, 0)
		var raised_height: int = 1 if terrain.generator.get_elevation(cell) != 1 else 2
		terrain.world.set_elevation_override(cell, raised_height)
		_expect(terrain.get_world_visible_cell(cell) == 1,
			"raised substrate crosses signed chunk boundary at %s" % cell)
		_expect(terrain.get_world_surface_elevation(cell) == raised_height,
			"raised height crosses signed chunk boundary at %s" % cell)


func _test_save_compatibility() -> void:
	var snapshot: Dictionary = terrain.export_authoritative_snapshot()
	var terrain_snapshot: Dictionary = snapshot.get("terrain", {})
	_expect(terrain_snapshot.has("material_overrides")
		and terrain_snapshot.has("elevation_overrides"),
		"existing terrain save fields are preserved")
	_expect(not terrain_snapshot.has("visible_material_overrides"),
		"derived exposed substrate adds no save field")
	var result: Dictionary = terrain.import_authoritative_snapshot(snapshot)
	_expect(bool(result["ok"]), "raised island snapshot reloads")


func _test_cliff_atlas_connections() -> void:
	var source: TileSetAtlasSource = terrain.cliff_edge_tileset.get_source(0)
	var image: Image = source.texture.get_image()
	var side_only_x: int = 2 * terrain.TILE_SIZE.x
	_expect(image.get_pixel(side_only_x, 15).a == 0.0,
		"unconnected mid-cell side return is absent")
	var north_east_corner_x: int = 5 * terrain.TILE_SIZE.x
	_expect(image.get_pixel(north_east_corner_x + 25, 0).a == 0.0,
		"north lip is clipped away from an unsupported east corner")
	var wall_source: TileSetAtlasSource = terrain.cliff_tileset.get_source(0)
	var wall_image: Image = wall_source.texture.get_image()
	var capped_variant_x: int = terrain.TILE_SIZE.x
	_expect(wall_image.get_pixel(capped_variant_x, 4).a < 1.0,
		"terminal wall cap tapers instead of forming a rectangular overhang")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

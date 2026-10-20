extends SceneTree
## Controlled Phase 3C corner/return comparison. The same fixtures and camera
## path are used for the pre-correction baseline and corrected prototype.

const OUTPUT_DIR := "res://.artifacts"
const FIXTURE_SIZE := Vector2i(44, 28)
const ZOOMS: Array[float] = [1.0, 3.0]

var demo
var terrain
var capture_label: String
var scenarios: Array[Dictionary] = []
var captures: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty() or String(arguments[0]) not in ["baseline", "prototype"]:
		push_error("Phase 3C capture requires user argument: baseline or prototype")
		quit(1)
		return
	capture_label = String(arguments[0])
	DisplayServer.window_set_size(Vector2i(1280, 720))
	demo = load("res://main.tscn").instantiate()
	root.add_child(demo)
	await _wait_frames(8)
	terrain = demo.terrain
	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.cursor.visible = false
	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)
	terrain.set_procedural_cliff_materials_enabled(true)
	terrain.set_organic_cliff_geometry_enabled(true)
	terrain.set_unified_cliff_components_enabled(true)
	terrain.set_refined_cliff_silhouettes_enabled(true)
	_build_fixtures()
	terrain._invalidate_streamed_chunks()
	for scenario in scenarios:
		await _capture_scenario(scenario)
	await _capture_diagnostics(scenarios[0])
	_write_manifest()
	print("PHASE3C_CAPTURE: PASS label=%s captures=%d" % [capture_label, captures.size()])
	quit(0)


func _build_fixtures() -> void:
	var wedge := Vector2i(18048, 9024)
	var corners := Vector2i(18144, 9024)
	var isolated := Vector2i(18240, 9024)
	var materials := Vector2i(18336, 9024)
	var positive := Vector2i(18432, 9216)
	var negative := Vector2i(-18432, -9216)

	_clear_fixture(wedge)
	# A tall dirt block, a one-cell stone pillar, and asymmetric shelves recreate
	# the conspicuous triangular corner regions seen in ordinary dense terrain.
	_fill(wedge + Vector2i(-13, -8), Vector2i(11, 10), 2, 3)
	_fill(wedge + Vector2i(-10, 2), Vector2i(7, 3), 2, 1)
	_set_cell(wedge + Vector2i(3, -3), 4, 3)
	_fill(wedge + Vector2i(8, -6), Vector2i(9, 8), 4, 2)
	_fill(wedge + Vector2i(8, 2), Vector2i(6, 3), 2, 1)
	_add_scenario("grey_wedge_reproduction", wedge,
		"Tall dirt and stone corners with asymmetric drops matching reported wedges.")

	_clear_fixture(corners)
	_fill(corners + Vector2i(-15, -9), Vector2i(10, 15), 2, 2)
	_fill(corners + Vector2i(-5, -9), Vector2i(8, 6), 2, 2)
	_fill(corners + Vector2i(4, -6), Vector2i(12, 12), 4, 3)
	_fill(corners + Vector2i(8, -2), Vector2i(5, 5), 3, 0)
	_add_scenario("convex_concave_corners", corners,
		"Explicit convex spurs and concave notches in dirt and stone plateaus.")

	_clear_fixture(isolated)
	_fill(isolated + Vector2i(-14, -4), Vector2i(3, 4), 2, 1)
	_fill(isolated + Vector2i(-4, -4), Vector2i(3, 4), 4, 2)
	_fill(isolated + Vector2i(7, -4), Vector2i(3, 4), 2, 3)
	_add_scenario("isolated_one_two_three", isolated,
		"Isolated one-, two-, and three-level formations.")

	_clear_fixture(materials)
	_fill(materials + Vector2i(-16, -8), Vector2i(16, 12), 2, 3)
	_fill(materials + Vector2i(0, -8), Vector2i(16, 12), 4, 3)
	_fill(materials + Vector2i(-10, 4), Vector2i(9, 3), 4, 1)
	_fill(materials + Vector2i(2, 4), Vector2i(9, 3), 2, 2)
	_add_scenario("adjacent_dirt_stone", materials,
		"Adjacent dirt and stone walls with crossed lower shelves.")

	_build_seam_fixture(positive)
	_add_scenario("positive_chunk_boundaries", positive,
		"Corner and return strips crossing positive X and Y chunk boundaries.")
	_build_seam_fixture(negative)
	_add_scenario("negative_chunk_boundaries", negative,
		"Corner and return strips crossing negative X and Y chunk boundaries.")


func _clear_fixture(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)


func _build_seam_fixture(center: Vector2i) -> void:
	_clear_fixture(center)
	_fill(center + Vector2i(-11, -10), Vector2i(9, 15), 2, 3)
	_fill(center + Vector2i(-2, -5), Vector2i(13, 10), 4, 2)
	_fill(center + Vector2i(3, -1), Vector2i(4, 4), 3, 0)


func _add_scenario(label: String, center: Vector2i, description: String) -> void:
	scenarios.append({"label": label, "center": center, "description": description})


func _fill(origin: Vector2i, size: Vector2i, material_id: int, elevation: int) -> void:
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			_set_cell(Vector2i(x, y), material_id, elevation)


func _set_cell(position: Vector2i, material_id: int, elevation: int) -> void:
	terrain.world.set_override(position, material_id)
	terrain.world.set_elevation_override(position, elevation)


func _capture_scenario(scenario: Dictionary) -> void:
	for zoom in ZOOMS:
		await _move_camera(scenario.center, zoom)
		await _save_capture(String(scenario.label), zoom, "all_components")


func _capture_diagnostics(scenario: Dictionary) -> void:
	await _move_camera(scenario.center, 3.0)
	terrain.set_cliff_shadows_visible(false)
	await _wait_frames(3)
	await _save_capture(String(scenario.label), 3.0, "no_contact_shadow")
	terrain.set_cliff_shadows_visible(true)
	terrain.set_cliff_edge_overlays_visible(false)
	await _wait_frames(3)
	await _save_capture(String(scenario.label), 3.0, "no_lips_or_returns")
	terrain.set_cliff_edge_overlays_visible(true)


func _move_camera(cell: Vector2i, zoom: float) -> void:
	demo.camera.position = Vector2(cell * terrain.TILE_SIZE) + Vector2(16, 16)
	demo.camera.zoom = Vector2.ONE * zoom
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	await _wait_until_idle()
	demo.camera.force_update_scroll()
	await _wait_frames(4)


func _save_capture(scenario: String, zoom: float, components: String) -> void:
	var file_name := "phase3c_%s_%s_%s_%s.png" % [
		capture_label, scenario, _zoom_label(zoom), components]
	var image: Image = root.get_texture().get_image()
	if image == null:
		push_error("Graphical renderer is required for Phase 3C captures")
		quit(1)
		return
	var error := image.save_png("%s/%s" % [OUTPUT_DIR, file_name])
	if error != OK:
		push_error("Could not save %s" % file_name)
		quit(1)
		return
	captures.append({
		"path": "%s/%s" % [OUTPUT_DIR, file_name],
		"scenario": scenario,
		"zoom": zoom,
		"components": components,
	})


func _write_manifest() -> void:
	var manifest := {
		"phase": "3C",
		"capture_label": capture_label,
		"engine": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(),
		"viewport": [1280, 720],
		"world_seed": terrain.world_seed,
		"zooms": ZOOMS,
		"scenarios": scenarios,
		"captures": captures,
	}
	var path := "%s/phase3c_%s_capture_manifest.json" % [OUTPUT_DIR, capture_label]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not create %s" % path)
		quit(1)
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()


func _zoom_label(zoom: float) -> String:
	return "1_0x" if is_equal_approx(zoom, 1.0) else "3_0x"


func _wait_until_idle(max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	assert(false, "Phase 3C capture streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame

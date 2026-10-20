extends SceneTree
## Phase 3B deterministic geological-cliff comparison matrix. Run with the
## user argument `baseline` before shader changes and `prototype` afterwards.

const OUTPUT_DIR := "res://.artifacts"
const FIXTURE_SIZE := Vector2i(58, 36)
const ZOOMS: Array[float] = [0.5, 1.0, 3.0]

var demo
var terrain
var capture_label: String = ""
var scenarios: Array[Dictionary] = []
var captures: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.is_empty() or String(arguments[0]) not in ["baseline", "prototype"]:
		push_error("Phase 3B capture requires user argument: baseline or prototype")
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
	terrain.set_procedural_cliff_materials_enabled(true)
	terrain.set_organic_cliff_geometry_enabled(true)
	terrain.set_unified_cliff_components_enabled(true)
	terrain.set_refined_cliff_silhouettes_enabled(true)

	# Preserve one ordinary generated view before fixture-only presentation is
	# stripped back. This prevents acceptance from relying only on curated cases.
	scenarios.append({
		"label": "natural_gameplay",
		"center": Vector2i.ZERO,
		"kind": "generated",
		"description": "Unmodified generated terrain with normal decorations and objects.",
	})
	await _capture_scenario(scenarios[-1])

	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)
	_build_controlled_scenarios()
	terrain._invalidate_streamed_chunks()
	for scenario in scenarios.slice(1):
		await _capture_scenario(scenario)

	_write_manifest()
	print("PHASE3B_CAPTURE: PASS label=%s captures=%d" % [capture_label, captures.size()])
	quit(0)


func _build_controlled_scenarios() -> void:
	var positive := Vector2i(16384, 8192)
	var winding := Vector2i(16480, 8192)
	var materials := Vector2i(16576, 8192)
	var isolated := Vector2i(16672, 8192)
	var negative := Vector2i(-16384, -8192)

	_build_diagonal_fixture(positive, 4)
	scenarios.append({
		"label": "positive_seam_diagonal",
		"center": positive,
		"kind": "controlled",
		"description": "Long stone diagonal crossing positive X/Y chunk boundaries.",
	})

	_build_winding_fixture(winding)
	scenarios.append({
		"label": "winding_convex_concave",
		"center": winding,
		"kind": "controlled",
		"description": "S-shaped dirt boundary with paired convex spur and concave notch.",
	})

	_build_material_fixture(materials)
	scenarios.append({
		"label": "materials_three_level_shoreline",
		"center": materials,
		"kind": "controlled",
		"description": "Broad three-level dirt and stone drops meeting a water shoreline.",
	})

	_build_isolated_fixture(isolated)
	scenarios.append({
		"label": "isolated_raised_formation",
		"center": isolated,
		"kind": "controlled",
		"description": "Small isolated stone formation with one-, two-, and three-level faces.",
	})

	_build_diagonal_fixture(negative, 2)
	scenarios.append({
		"label": "negative_seam_diagonal",
		"center": negative,
		"kind": "controlled",
		"description": "Long dirt diagonal crossing negative X/Y chunk boundaries.",
	})


func _build_diagonal_fixture(center: Vector2i, material_id: int) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	for y in range(-16, 16):
		for x in range(-27, 28):
			if x <= floori(float(y) * 1.45):
				_set_cell(center + Vector2i(x, y), material_id, 3)


func _build_winding_fixture(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	for y in range(-15, 16):
		var edge: int = floori(sin(float(y) * 0.42) * 8.0)
		for x in range(-27, edge + 1):
			_set_cell(center + Vector2i(x, y), 2, 2)
	# Explicit notch and spur exercise the established corner classifiers.
	_fill(center + Vector2i(-4, -4), Vector2i(8, 7), 3, 0)
	_fill(center + Vector2i(2, 7), Vector2i(11, 5), 2, 2)


func _build_material_fixture(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 0, 0)
	# The southern faces drop directly from height three to water so foot-local
	# wet shading and the no-contact-shadow shoreline policy are both visible.
	_fill(center + Vector2i(-26, -15), Vector2i(25, 19), 2, 3)
	_fill(center + Vector2i(1, -15), Vector2i(26, 19), 4, 3)
	# Lower shelves make each material readable away from the water contact too.
	_fill(center + Vector2i(-21, -4), Vector2i(15, 7), 2, 1)
	_fill(center + Vector2i(7, -4), Vector2i(15, 7), 4, 2)


func _build_isolated_fixture(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	_set_cell(center, 4, 3)
	_fill(center + Vector2i(-7, -2), Vector2i(3, 3), 4, 2)
	_fill(center + Vector2i(5, -2), Vector2i(5, 4), 2, 1)


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
		var file_name := "phase3b_%s_%s_%s.png" % [
			capture_label, String(scenario.label), _zoom_label(zoom)]
		await _save(file_name)
		captures.append({
			"path": "%s/%s" % [OUTPUT_DIR, file_name],
			"scenario": String(scenario.label),
			"camera_cell": _vector_to_array(scenario.center),
			"camera_world": _vector_to_array(demo.camera.position),
			"zoom": zoom,
		})


func _move_camera(cell: Vector2i, zoom: float) -> void:
	demo.camera.position = Vector2(cell * terrain.TILE_SIZE) + Vector2(16, 16)
	demo.camera.zoom = Vector2.ONE * zoom
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	await _wait_until_idle()
	demo.camera.force_update_scroll()
	await _wait_frames(4)


func _save(file_name: String) -> void:
	var image: Image = root.get_texture().get_image()
	if image == null:
		push_error("Graphical renderer is required for Phase 3B captures")
		quit(1)
		return
	var error: Error = image.save_png("%s/%s" % [OUTPUT_DIR, file_name])
	if error != OK:
		push_error("Could not save %s" % file_name)
		quit(1)


func _write_manifest() -> void:
	var scenario_records: Array[Dictionary] = []
	for scenario in scenarios:
		scenario_records.append({
			"label": String(scenario.label),
			"kind": String(scenario.kind),
			"center_cell": _vector_to_array(scenario.center),
			"description": String(scenario.description),
		})
	var manifest := {
		"phase": "3B",
		"capture_label": capture_label,
		"engine": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(),
		"viewport": [1280, 720],
		"world_seed": terrain.world_seed,
		"fixture_size_cells": _vector_to_array(FIXTURE_SIZE),
		"zooms": ZOOMS,
		"rendering_flags": {
			"procedural_cliff_materials": terrain.is_procedural_cliff_materials_enabled(),
			"organic_cliff_geometry": terrain.is_organic_cliff_geometry_enabled(),
			"unified_cliff_components": terrain.is_unified_cliff_components_enabled(),
			"refined_cliff_silhouettes": terrain.is_refined_cliff_silhouettes_enabled(),
		},
		"scenarios": scenario_records,
		"captures": captures,
	}
	var path := "%s/phase3b_%s_capture_manifest.json" % [OUTPUT_DIR, capture_label]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not create %s" % path)
		quit(1)
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()


func _zoom_label(zoom: float) -> String:
	if is_equal_approx(zoom, 0.5):
		return "0_5x"
	if is_equal_approx(zoom, 1.0):
		return "1_0x"
	return "3_0x"


func _vector_to_array(value: Variant) -> Array:
	return [value.x, value.y]


func _wait_until_idle(max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	assert(false, "Phase 3B capture streaming did not become idle")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame

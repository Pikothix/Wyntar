extends "res://tests/phase3f_capture.gd"
## Phase C4C evaluation-only cliff comparison capture harness. Every mode
## explicitly configures presentation flags and writes only to .artifacts/.

const CAPTURE_ZOOM := 2.31
const CONTEXT_ZOOM := 1.0
const WORLD_SEED := 84521

var mode: String = ""
var mode_zooms: Array[float] = []


func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.is_empty() or not _is_supported_mode(String(arguments[0])):
		push_error("Phase C4C capture requires a supported comparison mode")
		quit(1)
		return
	mode = String(arguments[0])
	capture_label = mode
	DisplayServer.window_set_size(Vector2i(1280, 720))
	demo = load("res://main.tscn").instantiate()
	root.add_child(demo)
	await _wait_frames(8)
	terrain = demo.terrain
	assert(terrain.world_seed == WORLD_SEED)
	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.cursor.visible = false
	terrain.set_water_animation_time_override(0.0)
	_configure_mode()
	_build_mode_scenarios()
	terrain._invalidate_streamed_chunks()
	for scenario in scenarios:
		await _capture_scenario(scenario)
	_write_c4c_manifest()
	print("PHASE_C4C_CAPTURE: PASS mode=%s images=%d" % [mode, captures.size()])
	quit(0)


func _is_supported_mode(value: String) -> bool:
	return value in [
		"contours_connected", "contours_unified",
		"directional_off", "directional_on",
		"height_baseline", "height_moderate", "height_prominent",
		"components_none", "components_overlay", "components_shadow",
		"components_both", "vegetation_context",
	]


func _configure_mode() -> void:
	var context_mode: bool = mode == "vegetation_context"
	if not context_mode:
		terrain.set_decoration_generation_enabled(false)
		terrain.set_environment_object_generation_enabled(false)
	else:
		terrain.decoration_context["density"] = 2.0
		terrain.decoration_context["clustering"] = 1.0
		terrain.environment_object_context["density"] = 2.0
	terrain.set_procedural_cliff_materials_enabled(true)
	terrain.set_organic_cliff_geometry_enabled(true)
	terrain.set_unified_cliff_components_enabled(true)
	terrain.set_refined_cliff_silhouettes_enabled(true)
	terrain.set_connected_cliff_contours_enabled(true)
	terrain.set_unified_cliff_contours_enabled(mode != "contours_connected")
	terrain.set_directional_cliff_projection_enabled(mode == "directional_on")
	var profile: int = TerrainRenderer.CliffHeightProfile.BASELINE
	if mode == "height_moderate":
		profile = TerrainRenderer.CliffHeightProfile.MODERATE
	elif mode in ["height_prominent", "directional_off", "directional_on"]:
		profile = TerrainRenderer.CliffHeightProfile.PROMINENT
	terrain.set_cliff_height_profile(profile)
	terrain.set_cliff_edge_overlays_visible(mode in ["components_overlay", "components_both"])
	terrain.set_cliff_shadows_visible(mode in ["components_shadow", "components_both"])
	mode_zooms.clear()
	if mode.begins_with("height_"):
		mode_zooms.append(1.0)
		mode_zooms.append(CAPTURE_ZOOM)
	else:
		mode_zooms.append(CONTEXT_ZOOM if context_mode else CAPTURE_ZOOM)


func _build_mode_scenarios() -> void:
	if mode == "vegetation_context":
		var center := Vector2i(31040, 15360)
		_build_vegetation_context(center)
		_add_scenario("vegetation_context", center,
			"Raised grass and stone boundary with deterministic decorations and objects.")
		return
	if mode.begins_with("height_"):
		var center := Vector2i(30720, 15360)
		_build_mixed_orientation_fixture(center)
		_add_scenario("mixed_orientation_height", center,
			"One-, two-, and three-level faces in cardinal and diagonal orientations.")
		return
	if mode.begins_with("components_"):
		var center := Vector2i(30464, 15360)
		_build_orientation_corner_fixture(center)
		_add_scenario("orientation_corners", center,
			"Cardinal faces with convex and concave corners.")
		return
	var orientation_center := Vector2i(30080, 15360)
	_build_orientation_corner_fixture(orientation_center)
	_add_scenario("orientation_corners", orientation_center,
		"Cardinal faces with convex and concave corners.")
	var water_center := Vector2i(32, -28672)
	_build_water_seam_fixture(water_center)
	_add_scenario("water_signed_seam", water_center,
		"Mixed-height shoreline crossing the positive X chunk boundary.")


func _build_orientation_corner_fixture(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	_fill(center + Vector2i(-6, -4), Vector2i(12, 8), 4, 2)
	_fill(center + Vector2i(-2, -4), Vector2i(4, 3), 3, 0)
	_fill(center + Vector2i(6, 1), Vector2i(3, 3), 4, 2)
	_fill(center + Vector2i(-3, -1), Vector2i(5, 4), 2, 3)


func _build_water_seam_fixture(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 0, 0)
	for y in range(-5, 5):
		var edge: int = 5 + floori(sin(float(y) * 0.55) * 2.0)
		for x in range(-7, edge + 1):
			var height: int = 1 if y < -2 else (2 if y < 2 else 3)
			_set_cell(center + Vector2i(x, y), 1 if height == 1 else 4, height)
	# A water notch forces inner shoreline corners on both sides of the seam.
	_fill(center + Vector2i(-2, -1), Vector2i(5, 3), 0, 0)


func _build_mixed_orientation_fixture(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	_fill(center + Vector2i(-7, -5), Vector2i(5, 10), 3, 1)
	_fill(center + Vector2i(-2, -4), Vector2i(5, 8), 2, 2)
	for y in range(-5, 6):
		var edge: int = 4 + floori(float(y) * 0.45)
		for x in range(3, mini(8, edge + 1)):
			_set_cell(center + Vector2i(x, y), 4, 3)


func _build_vegetation_context(center: Vector2i) -> void:
	_fill(center - FIXTURE_SIZE / 2, FIXTURE_SIZE, 3, 0)
	for y in range(-12, 13):
		var edge: int = floori(sin(float(y) * 0.28) * 5.0) + 8
		for x in range(-26, edge + 1):
			_set_cell(center + Vector2i(x, y), 3 if y < 4 else 4, 2)


func _capture_scenario(scenario: Dictionary) -> void:
	for zoom in mode_zooms:
		await _move_camera(scenario.center, zoom)
		if mode == "vegetation_context":
			assert(terrain.get_visible_decoration_count() > 0)
			assert(terrain.get_visible_environment_object_count() > 0)
		var file_name := "c4c_%s_%s_seed%d_z%s.png" % [
			mode, String(scenario.label), WORLD_SEED, _zoom_label(zoom)]
		await _save(file_name)
		captures.append({
			"path": "%s/%s" % [OUTPUT_DIR, file_name],
			"scenario": String(scenario.label),
			"seed": WORLD_SEED,
			"zoom": zoom,
			"camera_cell": _vector_to_array(scenario.center),
			"camera_world": _vector_to_array(demo.camera.position),
			"settings": _settings_snapshot(),
		})


func _settings_snapshot() -> Dictionary:
	return {
		"procedural_materials": terrain.procedural_cliff_materials_enabled,
		"organic_geometry": terrain.organic_cliff_geometry_enabled,
		"unified_components": terrain.unified_cliff_components_enabled,
		"refined_silhouettes": terrain.refined_cliff_silhouettes_enabled,
		"connected_contours": terrain.connected_cliff_contours_enabled,
		"unified_contours": terrain.unified_cliff_contours_enabled,
		"directional_projection": terrain.directional_cliff_projection_enabled,
		"height_profile": terrain.get_cliff_height_profile(),
		"height_step": terrain.get_cliff_height_step(),
		"edge_overlays": terrain.cliff_edge_overlays_visible,
		"shadows": terrain.cliff_shadows_visible,
		"water_time_override": 0.0,
	}


func _write_c4c_manifest() -> void:
	var path := "%s/c4c_%s_manifest.json" % [OUTPUT_DIR, mode]
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "Could not create Phase C4C manifest")
	file.store_string(JSON.stringify({
		"phase": "C4C", "mode": mode,
		"engine": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"viewport": [1280, 720], "seed": WORLD_SEED,
		"settings": _settings_snapshot(), "scenarios": scenarios,
		"captures": captures,
	}, "\t"))
	file.close()

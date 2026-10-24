extends "res://tests/phase1f_benchmark.gd"
## Matched L2 captures of one deterministic mixed-material, water-contact,
## multi-level cliff fixture at every requested zoom.

const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")
const OUTPUT_DIR := "res://.artifacts/l2_cliff_shader_lod"
const MANIFEST_PATH := "res://.artifacts/l2_cliff_shader_lod_capture_manifest.json"
const L2_ZOOMS := [0.125, 0.25, 0.5, 1.0, 1.75, 2.5, 3.5]


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	RenderingServer.set_default_clear_color(Color("23313a"))
	demo = load("res://main.tscn").instantiate()
	demo.chunk_profiling_enabled = true
	demo.decorations_enabled = false
	demo.environment_objects_enabled = false
	root.add_child(demo)
	await _wait_frames(8)
	terrain = demo.terrain
	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.cursor.visible = false
	terrain.set_water_animation_time_override(0.0)
	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)
	terrain.set_cliff_rendering_mode(TerrainRenderer.CliffRenderingMode.LEGACY)
	terrain.set_legacy_cliff_coverage_repair_enabled(true)

	var output_absolute: String = ProjectSettings.globalize_path(OUTPUT_DIR)
	assert(DirAccess.make_dir_recursive_absolute(output_absolute) == OK)
	var center := Vector2i(10200, 5100)
	_build_l2_fixture(center)
	terrain._invalidate_streamed_chunks()
	var records: Array[Dictionary] = []
	for zoom in L2_ZOOMS:
		demo.camera.apply_state(Vector2(center * terrain.TILE_SIZE) + Vector2(16, 16), zoom)
		demo._update_visible_world_region()
		await _wait_until_idle()
		await _wait_frames(3)
		for enabled in [false, true]:
			terrain.set_cliff_shader_lod_enabled(enabled)
			terrain.set_cliff_shader_lod_zoom(zoom)
			await _wait_frames(3)
			var label := "enabled" if enabled else "disabled"
			var zoom_label := str(roundi(zoom * 100.0)).pad_zeros(3)
			var path := "%s/l2_%s_zoom_%s.png" % [OUTPUT_DIR, label, zoom_label]
			var image: Image = root.get_texture().get_image()
			assert(image != null and image.save_png(path) == OK)
			records.append({
				"path": path,
				"enabled": enabled,
				"zoom": zoom,
				"detail_level": terrain.cliff_shader_lod_detail,
				"draw_calls": Performance.get_monitor(
					Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				"geometry": _geometry_totals(),
				"image_hash": hash(image.get_data()),
			})

	var manifest := {
		"phase": "L2",
		"engine": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"viewport": [1280, 720],
		"world_seed": terrain.world_seed,
		"mode": "LEGACY",
		"thresholds": {
			"minimum_zoom": terrain.cliff_shader_lod_min_zoom,
			"full_detail_zoom": terrain.cliff_shader_lod_full_detail_zoom,
			"minimum_detail": terrain.cliff_shader_lod_min_detail,
		},
		"records": records,
	}
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("PHASE_L2_CAPTURE: PASS captures=%d" % records.size())
	quit(0)


func _build_l2_fixture(center: Vector2i) -> void:
	_fill(center - Vector2i(58, 44), Vector2i(116, 88), 3, 0)
	# Water contact on the west side of the formation.
	_fill(center - Vector2i(58, 35), Vector2i(25, 70), 0, 0)
	for y in range(-34, 35):
		for x in range(-38, 43):
			var radius: float = Vector2(float(x) / 42.0, float(y) / 35.0).length()
			var ridge: float = sin(float(x) * 0.31) * 0.36 + cos(float(y) * 0.27) * 0.30
			var height: int = 0
			if radius + ridge * 0.18 < 0.92:
				height = 1
			if radius + ridge * 0.14 < 0.66:
				height = 2
			if radius + ridge * 0.10 < 0.36:
				height = 3
			if height > 0:
				var material_id: int = 4 if posmod(x + y, 5) != 0 else 2
				_set_cell(center + Vector2i(x, y), material_id, height)


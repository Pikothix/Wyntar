extends "res://tests/phase1f_benchmark.gd"
## Matched L2 visual-cost benchmark. Shader LOD changes shared uniforms only;
## this records frame time without assuming a GPU improvement.

const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")
const L2_OUTPUT_PATH := "res://.artifacts/l2_cliff_shader_lod_benchmark.json"
const L2_SAMPLE_FRAMES := 120
const UPDATE_SAMPLES := 1000


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
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

	var dense_center := Vector2i(10200, 5100)
	_build_fixture(dense_center)
	var dense: Dictionary = await _measure_fixture(dense_center)
	var typical_center := Vector2i(15400, 7700)
	_build_typical_fixture(typical_center)
	var typical: Dictionary = await _measure_fixture(typical_center)

	var update_started: int = Time.get_ticks_usec()
	for index in range(UPDATE_SAMPLES):
		var zoom: float = lerpf(0.125, 3.5, float(index) / float(UPDATE_SAMPLES - 1))
		terrain.set_cliff_shader_lod_zoom(zoom)
	var update_usec: int = Time.get_ticks_usec() - update_started
	var result := {
		"phase": "L2",
		"engine": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"viewport": [1280, 720],
		"sample_frames": L2_SAMPLE_FRAMES,
		"dense": dense,
		"typical": typical,
		"zoom_uniform_update": {
			"samples": UPDATE_SAMPLES,
			"total_ms": float(update_usec) / 1000.0,
			"average_ms": float(update_usec) / 1000.0 / UPDATE_SAMPLES,
		},
		"material_resources": (
			terrain.cliff_material_by_source.size()
			+ terrain.cliff_shadow_material_by_source.size() + 1),
	}
	var file := FileAccess.open(L2_OUTPUT_PATH, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("PHASE_L2_BENCHMARK: PASS")
	quit(0)


func _measure_fixture(center: Vector2i) -> Dictionary:
	demo.camera.apply_state(Vector2(center * terrain.TILE_SIZE) + Vector2(16, 16), 0.25)
	demo._update_visible_world_region()
	await _wait_until_idle()
	var material_ids: Array[int] = _material_ids()
	var geometry_before: Dictionary = _geometry_totals()
	terrain.set_cliff_shader_lod_enabled(false)
	terrain.set_cliff_shader_lod_zoom(0.25)
	var disabled: Dictionary = await _sample_fixed_frames(L2_SAMPLE_FRAMES)
	terrain.set_cliff_shader_lod_enabled(true)
	terrain.set_cliff_shader_lod_zoom(0.25)
	var enabled: Dictionary = await _sample_fixed_frames(L2_SAMPLE_FRAMES)
	var geometry_after: Dictionary = _geometry_totals()
	return {
		"zoom": 0.25,
		"detail_enabled": terrain.cliff_shader_lod_detail,
		"disabled": disabled,
		"enabled": enabled,
		"geometry_before": geometry_before,
		"geometry_after": geometry_after,
		"geometry_unchanged": (
			int(geometry_before.vertices) == int(geometry_after.vertices)
			and int(geometry_before.triangles) == int(geometry_after.triangles)),
		"materials_unchanged": material_ids == _material_ids(),
		"pending_chunks_after_toggle": terrain.get_pending_chunk_count(),
	}


func _build_typical_fixture(center: Vector2i) -> void:
	_fill(center - Vector2i(42, 30), Vector2i(84, 60), 3, 0)
	for y in range(-24, 25):
		for x in range(-36, 37):
			var ridge: float = sin(float(x) * 0.13) + cos(float(y) * 0.17)
			if ridge > 0.75:
				var height: int = 2 if ridge > 1.55 else 1
				_set_cell(center + Vector2i(x, y), 4 if posmod(x + y, 5) else 2, height)


func _material_ids() -> Array[int]:
	var result: Array[int] = []
	for material in terrain.cliff_material_by_source.values():
		result.append(material.get_instance_id())
	for material in terrain.cliff_shadow_material_by_source.values():
		result.append(material.get_instance_id())
	result.append(terrain.organic_cliff_material.get_instance_id())
	return result

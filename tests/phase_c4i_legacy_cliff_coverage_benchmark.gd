extends "res://tests/phase1f_benchmark.gd"
## Matched dense-fixture C4I geometry, streaming, draw-call, and frame cost.

const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")
const C4I_OUTPUT_PATH := "res://.artifacts/c4i_legacy_cliff_coverage_benchmark.json"


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	demo = load("res://main.tscn").instantiate()
	demo.chunk_profiling_enabled = true
	root.add_child(demo)
	await _wait_frames(8)
	terrain = demo.terrain
	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.cursor.visible = false
	terrain.set_water_animation_time_override(0.0)
	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)
	terrain.set_procedural_cliff_materials_enabled(true)
	terrain.set_organic_cliff_geometry_enabled(true)
	terrain.set_unified_cliff_components_enabled(true)
	terrain.set_refined_cliff_silhouettes_enabled(true)
	terrain.set_connected_cliff_contours_enabled(true)
	terrain.set_unified_cliff_contours_enabled(true)
	terrain.set_directional_cliff_projection_enabled(true)
	terrain.set_grid_aligned_cliff_rim_enabled(false)
	terrain.set_cliff_rendering_mode(TerrainRenderer.CliffRenderingMode.LEGACY)
	terrain.set_cliff_height_profile(TerrainRenderer.CliffHeightProfile.PROMINENT)
	terrain.set_cliff_edge_overlays_visible(false)
	terrain.set_cliff_shadows_visible(false)
	var center := Vector2i(10200, 5100)
	_build_fixture(center)
	demo.camera.position = Vector2(center * terrain.TILE_SIZE) + Vector2(16, 16)
	demo.camera.zoom = Vector2.ONE
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	var result := {
		"engine": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"fixture": "phase1g_dense_exact", "seed": terrain.world_seed,
		"viewport": [1280, 720], "steady_frames": SAMPLE_FRAMES,
		"before": await _measure_coverage(false),
		"after": await _measure_coverage(true),
	}
	var file := FileAccess.open(C4I_OUTPUT_PATH, FileAccess.WRITE)
	assert(file != null, "Could not write C4I benchmark")
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("PHASE_C4I_BENCHMARK: PASS")
	quit(0)


func _measure_coverage(enabled: bool) -> Dictionary:
	terrain.set_legacy_cliff_coverage_repair_enabled(enabled)
	await _wait_until_idle()
	await _wait_frames(120)
	var steady: Dictionary = await _sample_fixed_frames(SAMPLE_FRAMES)
	terrain.reset_incremental_cliff_scheduler_metrics()
	terrain._invalidate_streamed_chunks()
	demo._update_visible_world_region()
	var streaming: Dictionary = await _sample_until_idle()
	var geometry: Dictionary = _geometry_totals()
	geometry.merge(_coverage_geometry_totals(), true)
	return {
		"coverage_enabled": enabled,
		"steady": steady,
		"streaming": streaming,
		"geometry": geometry,
	}


func _coverage_geometry_totals() -> Dictionary:
	var vertices: int = 0
	var triangles: int = 0
	var meshes: int = 0
	for chunk in terrain.loaded_chunks.values():
		var stats: Dictionary = chunk.get_organic_cliff_geometry_stats()
		vertices += int(stats.coverage_vertex_count)
		triangles += int(stats.coverage_triangle_count)
		meshes += int(stats.coverage_mesh_count)
	return {
		"coverage_vertices": vertices,
		"coverage_triangles": triangles,
		"coverage_meshes": meshes,
	}

extends "res://tests/phase_c4h_legacy_cliff_coverage_capture.gd"
## C4K diagnosis only: captures accepted LEGACY fixtures with normal rendering
## and exact-colour layer isolation. Production geometry is not changed here.

const C4K_OUTPUT_DIR := "res://.artifacts/c4k_sidewall_diagnostic"
const C4K_ZOOMS := [1.0, 2.5, 3.5]

var records: Array[Dictionary] = []
var diagnostic_materials: Dictionary = {}


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	RenderingServer.set_default_clear_color(Color("ff00ff"))
	assert(DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(C4K_OUTPUT_DIR)) == OK)
	demo = load("res://main.tscn").instantiate()
	root.add_child(demo)
	await _wait_frames(8)
	terrain = demo.terrain
	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.cursor.visible = false
	terrain.set_water_animation_time_override(0.0)
	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)
	terrain.set_organic_cliff_geometry_enabled(true)
	terrain.set_unified_cliff_components_enabled(true)
	terrain.set_refined_cliff_silhouettes_enabled(true)
	terrain.set_connected_cliff_contours_enabled(true)
	terrain.set_unified_cliff_contours_enabled(true)
	terrain.set_directional_cliff_projection_enabled(true)
	terrain.set_grid_aligned_cliff_rim_enabled(false)
	terrain.set_cliff_rendering_mode(TerrainRenderer.CliffRenderingMode.LEGACY)
	terrain.set_legacy_cliff_coverage_repair_enabled(true)
	terrain.set_cliff_height_profile(TerrainRenderer.CliffHeightProfile.MODERATE)
	terrain.set_cliff_edge_overlays_visible(false)
	terrain.set_cliff_shadows_visible(false)
	_build_c4h_scenarios()
	terrain._invalidate_streamed_chunks()

	for scenario in scenarios:
		for zoom in C4K_ZOOMS:
			await _move_camera(scenario.center, zoom)
			await _capture_pass(scenario, zoom, "normal", "normal")
		if String(scenario.label) in DIAGNOSTIC_SCENARIOS:
			await _move_camera(scenario.center, 2.5)
			_apply_diagnostic_materials()
			await _capture_pass(scenario, 2.5, "diagnostic_all", "diagnostic_all")
			_set_c4k_visibility(true, false, false, false, false)
			await _capture_pass(scenario, 2.5, "lower_only", "diagnostic")
			_set_c4k_visibility(false, true, false, false, false)
			await _capture_pass(scenario, 2.5, "upper_only", "diagnostic")
			_set_c4k_visibility(false, false, true, false, false)
			await _capture_pass(scenario, 2.5, "face_only", "diagnostic")
			_set_c4k_visibility(false, false, false, true, false)
			await _capture_pass(scenario, 2.5, "coverage_only", "diagnostic")
			_set_c4k_visibility(false, false, false, false, true)
			await _capture_pass(scenario, 2.5, "sidewall_only", "diagnostic")
			_set_c4k_visibility(true, false, true, false, false)
			await _capture_pass(scenario, 2.5, "lower_and_face", "diagnostic")
			_restore_materials_and_visibility()

	var manifest := {
		"phase": "C4K-diagnostic",
		"engine": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"viewport": [1280, 720],
		"clear_color": "ff00ff",
		"diagnostic_colors": {
			"lower_surface": "00ff40",
			"upper_surface": "ffd000",
			"main_face": "8a2be2",
			"coverage_underlay": "00d9ff",
			"sidewall_occluder": "ff304f",
		},
		"records": records,
	}
	var file := FileAccess.open(
		"%s/c4k_diagnostic_manifest.json" % C4K_OUTPUT_DIR, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("PHASE_C4K_DIAGNOSTIC_CAPTURE: PASS captures=%d" % records.size())
	quit(0)


func _capture_pass(
		scenario: Dictionary, zoom: float, pass_label: String, kind: String) -> void:
	await _wait_frames(2)
	var zoom_label := str(roundi(zoom * 100.0)).pad_zeros(3)
	var file_name := "c4k_%s_%s_%s.png" % [
		String(scenario.label), pass_label, zoom_label]
	var image: Image = root.get_texture().get_image()
	assert(image != null and image.save_png(
		"%s/%s" % [C4K_OUTPUT_DIR, file_name]) == OK)
	records.append({
		"path": "%s/%s" % [C4K_OUTPUT_DIR, file_name],
		"scenario": String(scenario.label),
		"pass": pass_label,
		"kind": kind,
		"zoom": zoom,
	})


func _apply_diagnostic_materials() -> void:
	diagnostic_materials = {
		"lower": _diagnostic_material(Color("00ff40"), true),
		"upper": _diagnostic_material(Color("ffd000"), true),
		"face": _diagnostic_material(Color("8a2be2"), false),
		"coverage": _diagnostic_material(Color("00d9ff"), false),
		"sidewall": _diagnostic_material(Color("ff304f"), false),
	}
	for chunk in terrain.loaded_chunks.values():
		for layer in chunk.layers:
			layer.material = diagnostic_materials.lower
		for surface_group in chunk.elevated_layers:
			if surface_group != null:
				for layer in surface_group:
					layer.material = diagnostic_materials.upper
		for layer in chunk.organic_cliff_mesh_layers:
			if layer != null:
				layer.material = diagnostic_materials.face
		for layer in chunk.organic_cliff_coverage_mesh_layers:
			if layer != null:
				layer.material = diagnostic_materials.coverage
		for layer in chunk.organic_cliff_sidewall_occlusion_mesh_layers:
			if layer != null:
				layer.material = diagnostic_materials.sidewall
	_set_c4k_visibility(true, true, true, true, true)


func _diagnostic_material(color: Color, sample_texture: bool) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = (
		"shader_type canvas_item;\n"
		+ "uniform vec4 diagnostic_color : source_color;\n"
		+ ("void fragment(){ vec4 s=texture(TEXTURE,UV); COLOR=vec4(diagnostic_color.rgb,s.a*COLOR.a); }\n"
			if sample_texture else
			"void fragment(){ COLOR=vec4(diagnostic_color.rgb,COLOR.a); }\n"))
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("diagnostic_color", color)
	return material


func _set_c4k_visibility(
		lower: bool, upper: bool, face: bool, coverage: bool,
		sidewall: bool) -> void:
	for chunk in terrain.loaded_chunks.values():
		for layer in chunk.layers:
			layer.visible = lower
		for surface_group in chunk.elevated_layers:
			if surface_group != null:
				for layer in surface_group:
					layer.visible = upper
		for layer in chunk.shared_boundary_surface_layers:
			if layer != null:
				layer.visible = false
		for layer in chunk.organic_cliff_mesh_layers:
			if layer != null:
				layer.visible = face and layer.mesh != null
		for layer in chunk.organic_cliff_coverage_mesh_layers:
			if layer != null:
				layer.visible = coverage and layer.mesh != null
		for layer in chunk.organic_cliff_sidewall_occlusion_mesh_layers:
			if layer != null:
				layer.visible = sidewall and layer.mesh != null
		for layer in chunk.organic_cliff_edge_mesh_layers:
			if layer != null:
				layer.visible = false
		for layer in chunk.organic_cliff_shadow_mesh_layers:
			if layer != null:
				layer.visible = false


func _restore_materials_and_visibility() -> void:
	for chunk in terrain.loaded_chunks.values():
		for layer in chunk.layers:
			layer.material = null
		for surface_group in chunk.elevated_layers:
			if surface_group != null:
				for layer in surface_group:
					layer.material = null
		for layer in chunk.organic_cliff_mesh_layers:
			if layer != null:
				layer.material = terrain.organic_cliff_material
		for layer in chunk.organic_cliff_coverage_mesh_layers:
			if layer != null:
				layer.material = terrain.organic_cliff_material
		for layer in chunk.organic_cliff_sidewall_occlusion_mesh_layers:
			if layer != null:
				layer.material = terrain.organic_cliff_material
	_set_c4k_visibility(true, true, true, true, true)

extends "res://tests/phase_c4h_legacy_cliff_coverage_capture.gd"
## Matched C4K before/after captures plus a sidewall-specific pixel metric.
## Only pixels inside the generated lateral occlusion mask may change.

const C4K_OUTPUT_DIR := "res://.artifacts/c4k_sidewall_occlusion"
const C4K_ZOOMS := [1.0, 1.75, 2.5, 3.5]

var before_paths: Dictionary = {}
var measurements: Array[Dictionary] = []


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

	terrain.set_legacy_cliff_sidewall_occlusion_repair_enabled(false)
	await _wait_until_idle()
	for scenario in scenarios:
		for zoom in C4K_ZOOMS:
			await _move_camera(scenario.center, zoom)
			var path: String = await _save_normal(scenario, zoom, "before")
			before_paths[_key(scenario, zoom)] = path

	terrain.set_legacy_cliff_sidewall_occlusion_repair_enabled(true)
	await _wait_until_idle()
	for scenario in scenarios:
		for zoom in C4K_ZOOMS:
			await _move_camera(scenario.center, zoom)
			var after_path: String = await _save_normal(scenario, zoom, "after")
			var after_image: Image = Image.load_from_file(
				ProjectSettings.globalize_path(after_path))
			var before_path: String = String(before_paths[_key(scenario, zoom)])
			var before_image: Image = Image.load_from_file(
				ProjectSettings.globalize_path(before_path))
			var mask_image: Image = await _capture_sidewall_mask()
			var metric: Dictionary = _measure_change(before_image, after_image, mask_image)
			metric.merge({
				"scenario": String(scenario.label),
				"zoom": zoom,
				"before_path": before_path,
				"after_path": after_path,
			}, true)
			measurements.append(metric)
			if is_equal_approx(zoom, 2.5):
				var mask_path := "%s/c4k_mask_%s_250.png" % [
					C4K_OUTPUT_DIR, String(scenario.label)]
				assert(mask_image.save_png(mask_path) == OK)

	var changed_outside: int = 0
	var changed_total: int = 0
	var green_replaced: int = 0
	for measurement in measurements:
		changed_outside += int(measurement.changed_outside_sidewall_mask)
		changed_total += int(measurement.changed_pixels)
		green_replaced += int(measurement.green_dominant_pixels_replaced)
	assert(changed_total > 0, "C4K matrix must reproduce sidewall visibility changes")
	assert(changed_outside == 0,
		"C4K must not alter pixels outside its generated lateral sidewall mask")
	var manifest := {
		"phase": "C4K",
		"engine": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"viewport": [1280, 720],
		"zooms": C4K_ZOOMS,
		"measurements": measurements,
		"totals": {
			"changed_pixels": changed_total,
			"green_dominant_pixels_replaced": green_replaced,
			"changed_outside_sidewall_mask": changed_outside,
		},
	}
	var file := FileAccess.open(
		"%s/c4k_capture_manifest.json" % C4K_OUTPUT_DIR, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("PHASE_C4K_CAPTURE: PASS captures=%d changed=%d green=%d outside=%d" % [
		measurements.size() * 2, changed_total, green_replaced, changed_outside])
	quit(0)


func _save_normal(scenario: Dictionary, zoom: float, label: String) -> String:
	_set_normal_visibility()
	await _wait_frames(2)
	var zoom_label := str(roundi(zoom * 100.0)).pad_zeros(3)
	var path := "%s/c4k_%s_%s_%s.png" % [
		C4K_OUTPUT_DIR, label, String(scenario.label), zoom_label]
	var image: Image = root.get_texture().get_image()
	assert(image != null and image.save_png(path) == OK)
	return path


func _capture_sidewall_mask() -> Image:
	for chunk in terrain.loaded_chunks.values():
		for layer in chunk.layers:
			layer.visible = false
		for surface_group in chunk.elevated_layers:
			if surface_group != null:
				for layer in surface_group:
					layer.visible = false
		for layer in chunk.organic_cliff_mesh_layers:
			if layer != null:
				layer.visible = false
		for layer in chunk.organic_cliff_coverage_mesh_layers:
			if layer != null:
				layer.visible = false
		for layer in chunk.organic_cliff_sidewall_occlusion_mesh_layers:
			if layer != null:
				layer.visible = layer.mesh != null
		for layer in chunk.organic_cliff_edge_mesh_layers:
			if layer != null:
				layer.visible = false
		for layer in chunk.organic_cliff_shadow_mesh_layers:
			if layer != null:
				layer.visible = false
	await _wait_frames(2)
	var image: Image = root.get_texture().get_image()
	_set_normal_visibility()
	return image


func _set_normal_visibility() -> void:
	for chunk in terrain.loaded_chunks.values():
		for layer in chunk.layers:
			layer.visible = true
		for surface_group in chunk.elevated_layers:
			if surface_group != null:
				for layer in surface_group:
					layer.visible = true
		for layer in chunk.shared_boundary_surface_layers:
			if layer != null:
				layer.visible = false
		for layer in chunk.organic_cliff_mesh_layers:
			if layer != null:
				layer.visible = layer.mesh != null
		for layer in chunk.organic_cliff_coverage_mesh_layers:
			if layer != null:
				layer.visible = layer.mesh != null
		for layer in chunk.organic_cliff_sidewall_occlusion_mesh_layers:
			if layer != null:
				layer.visible = layer.mesh != null
		for layer in chunk.organic_cliff_edge_mesh_layers:
			if layer != null:
				layer.visible = false
		for layer in chunk.organic_cliff_shadow_mesh_layers:
			if layer != null:
				layer.visible = false


func _measure_change(before: Image, after: Image, mask: Image) -> Dictionary:
	before.convert(Image.FORMAT_RGBA8)
	after.convert(Image.FORMAT_RGBA8)
	mask.convert(Image.FORMAT_RGBA8)
	var before_data: PackedByteArray = before.get_data()
	var after_data: PackedByteArray = after.get_data()
	var mask_data: PackedByteArray = mask.get_data()
	var changed: int = 0
	var outside: int = 0
	var green_replaced: int = 0
	for offset in range(0, before_data.size(), 4):
		var pixel_changed: bool = (
			before_data[offset] != after_data[offset]
			or before_data[offset + 1] != after_data[offset + 1]
			or before_data[offset + 2] != after_data[offset + 2])
		if not pixel_changed:
			continue
		changed += 1
		if _is_clear_pixel(mask_data, offset):
			outside += 1
		var red: int = before_data[offset]
		var green: int = before_data[offset + 1]
		var blue: int = before_data[offset + 2]
		if green > red * 1.08 and green > blue * 1.10:
			green_replaced += 1
	return {
		"changed_pixels": changed,
		"green_dominant_pixels_replaced": green_replaced,
		"changed_outside_sidewall_mask": outside,
	}


func _is_clear_pixel(data: PackedByteArray, offset: int) -> bool:
	return (data[offset] == 255 and data[offset + 1] == 0
		and data[offset + 2] == 255 and data[offset + 3] == 255)


func _key(scenario: Dictionary, zoom: float) -> String:
	return "%s@%.3f" % [String(scenario.label), zoom]

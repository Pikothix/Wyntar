extends "res://tests/phase_l2_cliff_shader_lod_capture.gd"
## Matched normal and isolated L2 captures with cliff-confined pixel metrics.

const VERIFY_OUTPUT_DIR := "res://.artifacts/l2_visual_verification"
const VERIFY_MANIFEST_PATH := \
	"res://.artifacts/l2_visual_verification/l2_visual_verification_manifest.json"
const VERIFY_ZOOMS := [1.0, 0.5, 0.25, 0.125]


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	RenderingServer.set_default_clear_color(Color.BLACK)
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
	terrain.set_legacy_cliff_sidewall_occlusion_repair_enabled(true)
	terrain.set_cliff_edge_overlays_visible(false)
	terrain.set_cliff_shadows_visible(false)
	assert(DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(VERIFY_OUTPUT_DIR)) == OK)

	var center := Vector2i(10200, 5100)
	_build_l2_fixture(center)
	terrain._invalidate_streamed_chunks()
	var records: Array[Dictionary] = []
	for zoom in VERIFY_ZOOMS:
		demo.camera.apply_state(Vector2(center * terrain.TILE_SIZE) + Vector2(16, 16), zoom)
		demo._update_visible_world_region()
		await _wait_until_idle()
		await _wait_frames(3)
		var zoom_label := str(roundi(zoom * 100.0)).pad_zeros(3)

		terrain.set_cliff_shader_lod_enabled(false)
		await _wait_frames(3)
		var disabled_diagnostic: Dictionary = terrain.get_cliff_shader_lod_diagnostics()
		var disabled: Image = await _capture(
			"%s/l2v_disabled_zoom_%s.png" % [VERIFY_OUTPUT_DIR, zoom_label])

		terrain.set_cliff_shader_lod_enabled(true)
		await _wait_frames(3)
		var enabled_diagnostic: Dictionary = terrain.get_cliff_shader_lod_diagnostics()
		var enabled: Image = await _capture(
			"%s/l2v_enabled_zoom_%s.png" % [VERIFY_OUTPUT_DIR, zoom_label])

		_set_ground_surfaces_visible(false)
		terrain.set_cliff_shader_lod_enabled(false)
		await _wait_frames(2)
		var cliff_disabled: Image = await _capture(
			"%s/l2v_cliff_only_disabled_zoom_%s.png" % [VERIFY_OUTPUT_DIR, zoom_label])
		terrain.set_cliff_shader_lod_enabled(true)
		await _wait_frames(2)
		var cliff_enabled: Image = await _capture(
			"%s/l2v_cliff_only_enabled_zoom_%s.png" % [VERIFY_OUTPUT_DIR, zoom_label])

		var mask_material := _solid_material(Color.WHITE)
		_set_organic_cliff_material(mask_material)
		await _wait_frames(2)
		var mask: Image = await _capture(
			"%s/l2v_cliff_mask_zoom_%s.png" % [VERIFY_OUTPUT_DIR, zoom_label])
		_set_organic_cliff_material(terrain.organic_cliff_material)

		_set_ground_surfaces_visible(true)
		_set_organic_cliffs_visible(false)
		await _wait_frames(2)
		var ground_only: Image = await _capture(
			"%s/l2v_ground_only_zoom_%s.png" % [VERIFY_OUTPUT_DIR, zoom_label])
		_restore_chunk_visibility()

		var metrics: Dictionary = _difference_metrics(disabled, enabled, mask)
		metrics["cliff_only_neighbor_difference_255"] = \
			_region_neighbor_difference(cliff_enabled, mask, true)
		metrics["ground_only_neighbor_difference_255"] = \
			_region_neighbor_difference(ground_only, mask, false)
		metrics["cliff_mask_boundary_fraction"] = _mask_boundary_fraction(mask)
		records.append({
			"zoom": zoom,
			"disabled_path": "%s/l2v_disabled_zoom_%s.png" % [VERIFY_OUTPUT_DIR, zoom_label],
			"enabled_path": "%s/l2v_enabled_zoom_%s.png" % [VERIFY_OUTPUT_DIR, zoom_label],
			"cliff_only_disabled_path": "%s/l2v_cliff_only_disabled_zoom_%s.png" % [VERIFY_OUTPUT_DIR, zoom_label],
			"cliff_only_enabled_path": "%s/l2v_cliff_only_enabled_zoom_%s.png" % [VERIFY_OUTPUT_DIR, zoom_label],
			"mask_path": "%s/l2v_cliff_mask_zoom_%s.png" % [VERIFY_OUTPUT_DIR, zoom_label],
			"ground_only_path": "%s/l2v_ground_only_zoom_%s.png" % [VERIFY_OUTPUT_DIR, zoom_label],
			"disabled_diagnostic": disabled_diagnostic,
			"enabled_diagnostic": enabled_diagnostic,
			"metrics": metrics,
			"geometry": _geometry_totals(),
		})
		assert(int(metrics.changed_pixels_outside_cliff_mask) == 0,
			"L2 changed pixels outside the cliff mask at zoom %.3f" % zoom)

	demo.camera.apply_state(Vector2(center * terrain.TILE_SIZE) + Vector2(16, 16), 0.25)
	demo._update_visible_world_region()
	await _wait_until_idle()
	terrain.set_cliff_shader_lod_enabled(true)
	demo.hud.visible = true
	demo.cliff_lod_diagnostic_label.visible = true
	demo._update_cliff_lod_diagnostic()
	await _capture("%s/l2v_gameplay_diagnostic_zoom_025.png" % VERIFY_OUTPUT_DIR)
	demo.hud.visible = false

	var manifest := {
		"phase": "L2-visual-verification",
		"engine": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"viewport": [1280, 720],
		"world_seed": terrain.world_seed,
		"mode": "LEGACY",
		"c4j_coverage_enabled": terrain.legacy_cliff_coverage_repair_enabled,
		"c4k_sidewall_enabled": terrain.legacy_cliff_sidewall_occlusion_repair_enabled,
		"gameplay_diagnostic_path": \
			"%s/l2v_gameplay_diagnostic_zoom_025.png" % VERIFY_OUTPUT_DIR,
		"records": records,
	}
	var file := FileAccess.open(VERIFY_MANIFEST_PATH, FileAccess.WRITE)
	assert(file != null, "Could not write L2 visual verification manifest")
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("PHASE_L2_VISUAL_VERIFICATION_CAPTURE: PASS captures=%d" % (
		records.size() * 6 + 1))
	quit(0)


func _capture(path: String) -> Image:
	await _wait_frames(2)
	var image: Image = root.get_texture().get_image()
	assert(image != null and image.save_png(path) == OK)
	return image


func _solid_material(color: Color) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; uniform vec4 fill : source_color; void fragment(){ COLOR=fill; }"
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("fill", color)
	return material


func _set_ground_surfaces_visible(visible: bool) -> void:
	for chunk in terrain.loaded_chunks.values():
		for layer in chunk.layers:
			layer.visible = visible
		for group in chunk.elevated_layers:
			if group != null:
				for layer in group:
					layer.visible = visible
		for layer in chunk.shared_boundary_surface_layers:
			if layer != null:
				layer.visible = visible and not layer.get_used_cells().is_empty()


func _set_organic_cliffs_visible(visible: bool) -> void:
	for chunk in terrain.loaded_chunks.values():
		for group in [
				chunk.organic_cliff_mesh_layers,
				chunk.organic_cliff_coverage_mesh_layers,
				chunk.organic_cliff_sidewall_occlusion_mesh_layers]:
			for layer in group:
				if layer != null:
					layer.visible = visible and layer.mesh != null


func _set_organic_cliff_material(material: Material) -> void:
	for chunk in terrain.loaded_chunks.values():
		for group in [
				chunk.organic_cliff_mesh_layers,
				chunk.organic_cliff_coverage_mesh_layers,
				chunk.organic_cliff_sidewall_occlusion_mesh_layers]:
			for layer in group:
				if layer != null:
					layer.material = material


func _restore_chunk_visibility() -> void:
	for chunk in terrain.loaded_chunks.values():
		chunk._update_cliff_component_visibility()


func _difference_metrics(before: Image, after: Image, mask: Image) -> Dictionary:
	var a := before.duplicate()
	var b := after.duplicate()
	var m := mask.duplicate()
	a.convert(Image.FORMAT_RGBA8)
	b.convert(Image.FORMAT_RGBA8)
	m.convert(Image.FORMAT_RGBA8)
	var ad: PackedByteArray = a.get_data()
	var bd: PackedByteArray = b.get_data()
	var md: PackedByteArray = m.get_data()
	var pixels: int = a.get_width() * a.get_height()
	var cliff_pixels := 0
	var changed := 0
	var changed_gt_4 := 0
	var changed_gt_8 := 0
	var outside := 0
	var total_difference := 0.0
	var squared_difference := 0.0
	var maximum_difference := 0.0
	for pixel in range(pixels):
		var index := pixel * 4
		var difference := (
			absf(float(ad[index]) - float(bd[index]))
			+ absf(float(ad[index + 1]) - float(bd[index + 1]))
			+ absf(float(ad[index + 2]) - float(bd[index + 2]))) / 3.0
		var in_mask := md[index] > 127 and md[index + 1] > 127 and md[index + 2] > 127
		if in_mask:
			cliff_pixels += 1
			total_difference += difference
			squared_difference += difference * difference
			maximum_difference = maxf(maximum_difference, difference)
			if difference > 0.5:
				changed += 1
			if difference > 4.0:
				changed_gt_4 += 1
			if difference > 8.0:
				changed_gt_8 += 1
		elif difference > 0.5:
			outside += 1
	return {
		"total_pixels": pixels,
		"cliff_mask_pixels": cliff_pixels,
		"cliff_screen_fraction": float(cliff_pixels) / float(pixels),
		"changed_cliff_pixels": changed,
		"changed_cliff_fraction": float(changed) / float(maxi(cliff_pixels, 1)),
		"changed_cliff_pixels_gt_4_255": changed_gt_4,
		"changed_cliff_pixels_gt_8_255": changed_gt_8,
		"mean_absolute_rgb_difference_255": total_difference / float(maxi(cliff_pixels, 1)),
		"rms_rgb_difference_255": sqrt(squared_difference / float(maxi(cliff_pixels, 1))),
		"maximum_mean_rgb_difference_255": maximum_difference,
		"changed_pixels_outside_cliff_mask": outside,
	}


func _region_neighbor_difference(image: Image, mask: Image, inside_mask: bool) -> float:
	var source := image.duplicate()
	var region := mask.duplicate()
	source.convert(Image.FORMAT_RGBA8)
	region.convert(Image.FORMAT_RGBA8)
	var data: PackedByteArray = source.get_data()
	var mask_data: PackedByteArray = region.get_data()
	var width: int = source.get_width()
	var height: int = source.get_height()
	var total := 0.0
	var pairs := 0
	for y in range(height):
		for x in range(width - 1):
			var index: int = (y * width + x) * 4
			var next: int = index + 4
			var here_inside := mask_data[index] > 127
			var next_inside := mask_data[next] > 127
			if here_inside != inside_mask or next_inside != inside_mask:
				continue
			if not inside_mask:
				var here_brightness := int(data[index]) + int(data[index + 1]) + int(data[index + 2])
				var next_brightness := int(data[next]) + int(data[next + 1]) + int(data[next + 2])
				if here_brightness < 15 or next_brightness < 15:
					continue
			total += (
				absf(float(data[index]) - float(data[next]))
				+ absf(float(data[index + 1]) - float(data[next + 1]))
				+ absf(float(data[index + 2]) - float(data[next + 2]))) / 3.0
			pairs += 1
	return total / float(maxi(pairs, 1))


func _mask_boundary_fraction(mask: Image) -> float:
	var source := mask.duplicate()
	source.convert(Image.FORMAT_RGBA8)
	var data: PackedByteArray = source.get_data()
	var width: int = source.get_width()
	var height: int = source.get_height()
	var inside := 0
	var boundary := 0
	for y in range(1, height - 1):
		for x in range(1, width - 1):
			var index: int = (y * width + x) * 4
			if data[index] <= 127:
				continue
			inside += 1
			if (data[index - 4] <= 127 or data[index + 4] <= 127
					or data[index - width * 4] <= 127
					or data[index + width * 4] <= 127):
				boundary += 1
	return float(boundary) / float(maxi(inside, 1))

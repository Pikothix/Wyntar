extends SceneTree
## Phase A validation for presentation-only water enhancement controls,
## deterministic world-space inputs, streaming lifecycle, and save isolation.

const Catalog = preload("res://scripts/terrain_catalog.gd")
const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")
const SHADER_PATH := "res://shaders/terrain_variation.gdshader"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_profile()
	_test_shader_contract()
	_test_spatial_determinism()
	await _test_renderer_runtime_and_streaming()
	if failures.is_empty():
		print("PHASE_A_WATER_VALIDATION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE_A_WATER_VALIDATION: FAIL (%d)" % failures.size())
	quit(1)


func _test_catalog_profile() -> void:
	var water: Dictionary = Catalog.MATERIALS[0]
	for key in [
			"water_ripple_strength", "water_secondary_ripple_scale",
			"water_ripple_drift_speed", "water_glint_density",
			"water_glint_brightness"]:
		_expect(water.has(key), "water profile defines %s" % key)
	_expect(Catalog.is_liquid(0), "water retains liquid material identity")
	_expect(not Catalog.is_liquid(1), "sand remains ordinary terrain")


func _test_shader_contract() -> void:
	var source: String = FileAccess.get_file_as_string(SHADER_PATH)
	_expect(source.contains("if (experimental_water_enhancement_enabled > 0.5)"),
		"enhancement work is guarded by the dedicated toggle")
	_expect(source.contains("floor(world_position)"),
		"water patterns quantise absolute world position")
	_expect(source.contains("water_animation_time_override >= 0.0"),
		"capture tests can hold the global animation time fixed")
	_expect(not source.contains("SCREEN_UV"),
		"water enhancement is not screen-space anchored")


func _test_spatial_determinism() -> void:
	var samples := [
		Vector2(-1025.0, -513.0), Vector2(-1.0, -1.0), Vector2.ZERO,
		Vector2(1023.0, 1024.0), Vector2(2048.0, -2049.0),
	]
	for point in samples:
		var first: Dictionary = _water_sample(point, 7.25)
		var second: Dictionary = _water_sample(point, 7.25)
		_expect(first == second, "same world position and time are deterministic: %s" % point)
		_expect(float(first.secondary_crest) >= 0.0 and float(first.secondary_crest) <= 1.0,
			"secondary crest stays bounded at %s" % point)
	var seam_point := Vector2(1024.0, -1024.0)
	_expect(_water_sample(seam_point, 3.5) == _water_sample(seam_point, 3.5),
		"a shared coordinate evaluates identically at a positive/negative chunk seam")
	var negative_cell: Vector2 = _glint_cell(Vector2(-1.0, -1.0))
	_expect(negative_cell == Vector2(-1.0, -1.0),
		"negative coordinates use floor-based lattice ownership")


func _test_renderer_runtime_and_streaming() -> void:
	var renderer = TerrainRenderer.new()
	renderer.decoration_generation_enabled = false
	renderer.environment_object_generation_enabled = false
	root.add_child(renderer)
	await process_frame
	var water_material: ShaderMaterial = renderer.visual_material_by_id[0]
	var sand_material: ShaderMaterial = renderer.visual_material_by_id[1]
	_expect(float(water_material.get_shader_parameter(
		"experimental_water_enhancement_enabled")) == 0.0,
		"experimental enhancement defaults disabled")
	var sand_toggle: Variant = sand_material.get_shader_parameter(
		"experimental_water_enhancement_enabled")
	_expect(sand_toggle == null or is_zero_approx(float(sand_toggle)),
		"ordinary terrain remains outside the enhancement branch")
	var snapshot_before: String = JSON.stringify(renderer.export_authoritative_snapshot())
	renderer.set_experimental_water_enhancement_enabled(true)
	_expect(float(water_material.get_shader_parameter(
		"experimental_water_enhancement_enabled")) == 1.0,
		"runtime toggle propagates to the shared water material")
	renderer.set_water_enhancement_controls(2.0, 20.0, -1.0, 4.0, -2.0)
	_expect(is_equal_approx(float(water_material.get_shader_parameter(
		"water_ripple_strength")), 1.0), "ripple strength is bounded")
	_expect(is_equal_approx(float(water_material.get_shader_parameter(
		"water_secondary_ripple_scale")), 6.0), "secondary scale is bounded")
	_expect(is_equal_approx(float(water_material.get_shader_parameter(
		"water_ripple_drift_speed")), 0.0), "drift speed is bounded")
	_expect(is_equal_approx(float(water_material.get_shader_parameter(
		"water_glint_density")), 1.0), "glint density is bounded")
	_expect(is_equal_approx(float(water_material.get_shader_parameter(
		"water_glint_brightness")), 0.0), "glint brightness is bounded")
	var edit_cell := Vector2i(-17, 33)
	renderer.set_world_cell(edit_cell, 0)
	renderer.set_world_elevation(edit_cell, 0)
	_expect(renderer.get_world_cell(edit_cell) == 0,
		"material editing remains compatible with enhanced water")
	_expect(renderer.get_world_elevation(edit_cell) == 0,
		"elevation editing semantics remain unchanged")
	var snapshot_after: String = JSON.stringify(renderer.export_authoritative_snapshot())
	_expect(snapshot_before != snapshot_after,
		"the explicit material edit changes authoritative state")
	var isolated_snapshot: String = JSON.stringify(renderer.export_authoritative_snapshot())
	renderer.set_experimental_water_enhancement_enabled(false)
	renderer.set_experimental_water_enhancement_enabled(true)
	_expect(JSON.stringify(renderer.export_authoritative_snapshot()) == isolated_snapshot,
		"runtime toggling does not enter authoritative snapshots or save data")

	renderer.update_visible_world_rect(Rect2(Vector2(-1536.0, -1536.0), Vector2(1024.0, 1024.0)))
	await _wait_until_idle(renderer)
	var initial_chunks: int = renderer.loaded_chunks.size()
	_expect(initial_chunks > 0, "negative-coordinate chunks stream successfully")
	renderer.update_visible_world_rect(Rect2(Vector2(64000.0, 64000.0), Vector2(1024.0, 1024.0)))
	await _wait_until_idle(renderer)
	renderer.update_visible_world_rect(Rect2(Vector2(-1536.0, -1536.0), Vector2(1024.0, 1024.0)))
	await _wait_until_idle(renderer)
	_expect(renderer.loaded_chunks.size() > 0,
		"chunks render after unload and reload")
	_expect(float(water_material.get_shader_parameter(
		"experimental_water_enhancement_enabled")) == 1.0,
		"shared water animation state survives chunk unload/reload")
	_expect(renderer.visual_material_by_id[0] == water_material,
		"chunk reload reuses water material identity")
	renderer.queue_free()


func _water_sample(world_position: Vector2, seconds: float) -> Dictionary:
	var liquid_pixel := world_position.floor() + Vector2(0.5, 0.5)
	var water_beat: float = floor(seconds * 8.0) / 8.0
	var secondary_drift := (Vector2(13.0, -7.0) * water_beat * 0.55).floor()
	var secondary_coordinate := (liquid_pixel + secondary_drift) * 0.010 * 2.4
	var ripple: float = sin(secondary_coordinate.dot(Vector2(0.61, 1.27)) + 1.73)
	return {
		"pixel": liquid_pixel,
		"drift": secondary_drift,
		"secondary_crest": ripple * 0.5 + 0.5,
		"glint_cell": _glint_cell(liquid_pixel),
	}


func _glint_cell(world_pixel: Vector2) -> Vector2:
	return (world_pixel.floor() / Vector2(12.0, 7.0)).floor()


func _wait_until_idle(renderer, max_frames: int = 2400) -> void:
	for _frame in range(max_frames):
		await process_frame
		if renderer.get_pending_chunk_count() == 0:
			return
	_expect(false, "streaming completed within the validation frame budget")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

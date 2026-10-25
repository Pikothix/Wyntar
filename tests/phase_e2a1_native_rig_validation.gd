extends SceneTree
## Native Sprite2D rig presentation contracts layered on the E2A data model.

const Species = preload("res://scripts/creatures/creature_species.gd")
const Generator = preload("res://scripts/creatures/creature_generator.gd")
const Renderer = preload("res://scripts/creatures/creature_renderer.gd")
const Rig = preload("res://scripts/creatures/creature_rig.gd")
const PoseEvaluator = preload("res://scripts/creatures/creature_pose_evaluator.gd")
const RigVisualCache = preload("res://scripts/creatures/creature_rig_visual_cache.gd")
const RigRenderer = preload("res://scripts/creatures/creature_rig_renderer.gd")
const RigPresenter = preload("res://scripts/creatures/creature_rig_presenter.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var anatomy := Generator.generate_creature(Species.SPECIES_ID, 84521, 0.6, "stocky", true)
	var rig := Rig.build(anatomy)
	var cache := RigVisualCache.new()
	var visual := cache.get_or_generate(anatomy, rig)
	var presenter := RigPresenter.new()
	root.add_child(presenter)
	presenter.configure(rig, visual)
	_expect(presenter.is_configured(), "native presenter must configure every drawable body part")
	_expect(presenter.joint_count() == rig.joints.size(), "native presenter hierarchy must contain every rig joint")
	_test_joint_transforms(presenter, rig, visual)
	_test_texture_stability(presenter, rig, cache)
	await _test_neutral_reference(presenter, rig, visual)
	await _test_pause_and_cleanup(presenter)
	_test_bounded_texture_cache()
	if failures.is_empty():
		print("PHASE_E2A1_NATIVE_VALIDATION: PASS (native hierarchy, textures, pause, cleanup, reference pixels)")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("PHASE_E2A1_NATIVE_VALIDATION: FAIL (%d failures)" % failures.size())
		quit(1)

func _test_joint_transforms(presenter: Node2D, rig: Dictionary, visual: Dictionary) -> void:
	var reference := RigRenderer.new()
	reference.configure(rig, visual)
	for state_time in [["neutral", 0.0], ["idle", 0.47], ["walk", 0.19]]:
		var pose := PoseEvaluator.evaluate_pose(rig, state_time[0], state_time[1])
		presenter.apply_pose(pose)
		for joint_name in rig.joints:
			var expected := reference.transformed_joint_pixel(joint_name, pose) - Renderer.CENTER
			_expect(presenter.joint_position(joint_name).distance_to(expected) <= 0.001, "%s native transform must match reference joint %s" % [state_time[0], joint_name])
		_expect(presenter.ground_contact_position() == rig.ground_contact, "%s must preserve ground alignment" % state_time[0])

func _test_texture_stability(presenter: Node2D, rig: Dictionary, cache: RefCounted) -> void:
	var texture_ids: Array[int] = presenter.texture_instance_ids()
	var generation_count: int = cache.generation_count
	var texture_count: int = cache.texture_creation_count
	for frame in range(240):
		presenter.apply_pose(PoseEvaluator.evaluate_pose(rig, "walk", float(frame) / 60.0))
	_expect(presenter.texture_instance_ids() == texture_ids, "ordinary playback must retain the same texture objects")
	_expect(cache.generation_count == generation_count, "ordinary playback must not regenerate procedural artwork")
	_expect(cache.texture_creation_count == texture_count, "ordinary playback must not recreate native textures")

func _test_neutral_reference(presenter: Node2D, rig: Dictionary, visual: Dictionary) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(Renderer.CANVAS_SIZE, Renderer.CANVAS_SIZE)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	root.add_child(viewport)
	root.remove_child(presenter)
	presenter.position = Renderer.CENTER
	viewport.add_child(presenter)
	var reference := RigRenderer.new()
	reference.configure(rig, visual)
	for state_time in [["neutral", 0.0], ["idle", 0.47], ["walk", 0.19]]:
		var pose := PoseEvaluator.evaluate_pose(rig, state_time[0], state_time[1])
		presenter.apply_pose(pose)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		for _frame in range(2):
			await process_frame
		var native_image := viewport.get_texture().get_image()
		_expect(_opaque_components(native_image) == 1, "%s native pose must remain connected" % state_time[0])
		_expect(not _touches_canvas_edge(native_image), "%s native pose must remain within bounds" % state_time[0])
		if state_time[0] == "neutral":
			var reference_image := reference.compose(pose)
			native_image.save_png("res://.artifacts/phase_e2a1_native_neutral_validation.png")
			reference_image.save_png("res://.artifacts/phase_e2a1_cpu_neutral_reference.png")
			var alpha_mismatches := 0
			var opaque_color_mismatches := 0
			for y in range(Renderer.CANVAS_SIZE):
				for x in range(Renderer.CANVAS_SIZE):
					if native_image.get_pixel(x, y).a8 != reference_image.get_pixel(x, y).a8:
						alpha_mismatches += 1
					if native_image.get_pixel(x, y).a8 > 0 and native_image.get_pixel(x, y) != reference_image.get_pixel(x, y):
						opaque_color_mismatches += 1
			_expect(alpha_mismatches <= 4, "native neutral alpha mask must match CPU reference (mismatches %d)" % alpha_mismatches)
			_expect(opaque_color_mismatches == 0, "native neutral opaque colors must match CPU reference")
	viewport.remove_child(presenter)
	root.add_child(presenter)
	viewport.queue_free()

func _test_pause_and_cleanup(presenter: Node2D) -> void:
	var updates_before: int = presenter.update_count
	for _frame in range(5):
		await process_frame
	_expect(presenter.update_count == updates_before, "paused presenter must perform no autonomous pose updates")
	root.remove_child(presenter)
	_expect(presenter.disposed, "presenter must release scene-tree presentation state when removed")
	presenter.queue_free()
	await process_frame
	_expect(not is_instance_valid(presenter), "removed presenter must clean up completely")

func _test_bounded_texture_cache() -> void:
	var cache := RigVisualCache.new()
	for index in range(RigVisualCache.MAX_ENTRIES + 4):
		var anatomy := Generator.generate_creature(Species.SPECIES_ID, Generator.individual_seed(84521, index), 0.6, Generator.mixed_archetype(84521, index), true)
		cache.get_or_generate(anatomy, Rig.build(anatomy))
	_expect(cache.entry_count() == RigVisualCache.MAX_ENTRIES, "native artwork and texture cache must remain bounded")
	_expect(cache.approximate_memory_bytes() > 0, "native texture cache must report approximate memory use")

func _touches_canvas_edge(image: Image) -> bool:
	for x in range(image.get_width()):
		if image.get_pixel(x, 0).a > 0.0 or image.get_pixel(x, image.get_height() - 1).a > 0.0:
			return true
	for y in range(image.get_height()):
		if image.get_pixel(0, y).a > 0.0 or image.get_pixel(image.get_width() - 1, y).a > 0.0:
			return true
	return false

func _opaque_components(image: Image) -> int:
	var visited: Dictionary = {}
	var components := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var start := Vector2i(x, y)
			if image.get_pixel(x, y).a <= 0.0 or visited.has(start):
				continue
			components += 1
			var pending: Array[Vector2i] = [start]
			visited[start] = true
			while not pending.is_empty():
				var point: Vector2i = pending.pop_back()
				for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var neighbor: Vector2i = point + offset
					if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= image.get_width() or neighbor.y >= image.get_height() or visited.has(neighbor):
						continue
					if image.get_pixelv(neighbor).a > 0.0:
						visited[neighbor] = true
						pending.append(neighbor)
	return components

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

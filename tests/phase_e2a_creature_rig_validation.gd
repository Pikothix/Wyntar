extends SceneTree
## Focused E2A rig, pose, cached-art, and animated-composition contracts.

const Species = preload("res://scripts/creatures/creature_species.gd")
const Generator = preload("res://scripts/creatures/creature_generator.gd")
const Rig = preload("res://scripts/creatures/creature_rig.gd")
const PoseEvaluator = preload("res://scripts/creatures/creature_pose_evaluator.gd")
const RigVisualCache = preload("res://scripts/creatures/creature_rig_visual_cache.gd")
const RigRenderer = preload("res://scripts/creatures/creature_rig_renderer.gd")

var failures: Array[String] = []

func _initialize() -> void:
	_run()

func _run() -> void:
	_test_rig_and_pose_determinism()
	_test_pose_interpolation()
	_test_attachments_and_rendering()
	_test_cached_art_and_reused_output()
	_test_bounded_visual_cache()
	if failures.is_empty():
		print("PHASE_E2A_VALIDATION: PASS (48 rigs, neutral/idle/walk, 240 cached compositions)")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("PHASE_E2A_VALIDATION: FAIL (%d failures)" % failures.size())
		quit(1)

func _test_rig_and_pose_determinism() -> void:
	for index in range(48):
		var anatomy := _anatomy(index)
		var anatomy_before: Dictionary = anatomy.duplicate(true)
		var first := Rig.build(anatomy)
		var second := Rig.build(anatomy)
		_expect(first == second, "rig %d must be deterministic" % index)
		_expect(Rig.is_valid(first), "rig %d must expose the complete valid hierarchy" % index)
		_expect(anatomy == anatomy_before, "rig generation must not mutate anatomy %d" % index)
		for state_name in PoseEvaluator.STATES:
			var pose_a := PoseEvaluator.evaluate_pose(first, state_name, 1.2345, {"speed": 1.1, "intensity": 0.8})
			var pose_b := PoseEvaluator.evaluate_pose(first, state_name, 1.2345, {"speed": 1.1, "intensity": 0.8})
			_expect(pose_a == pose_b, "%s pose %d must be deterministic" % [state_name, index])
			_expect(pose_a.ground_contact == first.ground_contact, "%s pose %d must preserve ground anchor" % [state_name, index])
			_expect(pose_a.transforms.root.translation == Vector2.ZERO, "%s pose %d must keep root anchored" % [state_name, index])
		_expect(anatomy == anatomy_before, "pose evaluation must not mutate anatomy %d" % index)

func _test_pose_interpolation() -> void:
	var rig := Rig.build(_anatomy(2))
	var neutral := PoseEvaluator.evaluate_pose(rig, "neutral", 0.0)
	var walk := PoseEvaluator.evaluate_pose(rig, "walk", 0.17)
	_expect(PoseEvaluator.interpolate_pose(neutral, walk, 0.0) == neutral, "zero-weight interpolation must reproduce source pose")
	_expect(PoseEvaluator.interpolate_pose(neutral, walk, 1.0) == walk, "full-weight interpolation must reproduce target pose")
	var halfway := PoseEvaluator.interpolate_pose(neutral, walk, 0.5)
	_expect(halfway.transforms.body.translation.is_equal_approx(Vector2(neutral.transforms.body.translation).lerp(Vector2(walk.transforms.body.translation), 0.5)), "interpolation must blend translations")
	_expect(halfway.ground_contact == rig.ground_contact, "interpolation must keep ground contact stable")

func _test_attachments_and_rendering() -> void:
	var cache := RigVisualCache.new()
	for index in range(24):
		var anatomy := _anatomy(index)
		var rig := Rig.build(anatomy)
		var visuals := cache.get_or_generate(anatomy, rig)
		var composer := RigRenderer.new()
		composer.configure(rig, visuals)
		for state_time in [["neutral", 0.0], ["idle", 0.47], ["walk", 0.19]]:
			var pose := PoseEvaluator.evaluate_pose(rig, state_time[0], state_time[1])
			var image := composer.compose(pose)
			_expect(not _touches_canvas_edge(image), "%s render %d must remain inside stable bounds" % [state_time[0], index])
			_expect(_opaque_components(image) == 1, "%s render %d must have no disconnected body parts" % [state_time[0], index])
			for joint_name in ["head", "tail", "leg_back_left", "leg_back_right", "leg_front_left", "leg_front_right"]:
				var pivot := Vector2i(composer.transformed_joint_pixel(joint_name, pose).round())
				_expect(image.get_pixelv(pivot).a > 0.0, "%s render %d must cover %s attachment" % [state_time[0], index, joint_name])

func _test_cached_art_and_reused_output() -> void:
	var anatomy := _anatomy(7)
	var rig := Rig.build(anatomy)
	var cache := RigVisualCache.new()
	var visuals := cache.get_or_generate(anatomy, rig)
	var composer := RigRenderer.new()
	composer.configure(rig, visuals)
	var generation_count := cache.generation_count
	var output_id := 0
	for frame in range(240):
		var pose := PoseEvaluator.evaluate_pose(rig, "walk", float(frame) / 60.0)
		composer.compose(pose)
		if frame == 0:
			output_id = composer.output_instance_id()
		_expect(composer.output_instance_id() == output_id, "composition output image must be reused at frame %d" % frame)
	_expect(cache.generation_count == generation_count, "ordinary playback must not regenerate body-part artwork")
	cache.get_or_generate(anatomy, rig)
	_expect(cache.generation_count == generation_count and cache.cache_hit_count == 1, "repeated visual request must hit rig-art cache")

func _test_bounded_visual_cache() -> void:
	var cache := RigVisualCache.new()
	for index in range(RigVisualCache.MAX_ENTRIES + 4):
		var anatomy := _anatomy(index)
		cache.get_or_generate(anatomy, Rig.build(anatomy))
	_expect(cache.entry_count() == RigVisualCache.MAX_ENTRIES, "rig visual cache must remain bounded")

func _anatomy(index: int) -> Dictionary:
	return Generator.generate_creature(Species.SPECIES_ID, Generator.individual_seed(84521, index), 0.6, Generator.mixed_archetype(84521, index), true)

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

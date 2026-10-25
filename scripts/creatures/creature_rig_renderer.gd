extends RefCounted
## Stateful presentation composer. It reuses one output image and cached opaque
## part pixels, applying nearest-neighbour transforms around rig pivots.

const Renderer = preload("res://scripts/creatures/creature_renderer.gd")

const DRAW_ORDER := [
	"tail", "leg_back_left", "leg_back_right", "leg_front_left",
	"leg_front_right", "body", "ear_left", "ear_right", "head",
]

var _rig: Dictionary
var _visual: Dictionary
var _output: Image
var _draw_order: Array[String] = []
var composition_count := 0

func configure(rig: Dictionary, visual: Dictionary) -> void:
	_rig = rig
	_visual = visual
	_draw_order = draw_order_for(visual)
	if _output == null:
		_output = Image.create(Renderer.CANVAS_SIZE, Renderer.CANVAS_SIZE, false, Image.FORMAT_RGBA8)

func compose(pose: Dictionary, draw_joint_overlay: bool = false) -> Image:
	assert(not _rig.is_empty() and not _visual.is_empty(), "Rig renderer must be configured before composition")
	_output.fill(Color.TRANSPARENT)
	for part_name in _draw_order:
		_draw_part(part_name, pose)
	if draw_joint_overlay:
		_draw_overlay(pose)
	composition_count += 1
	return _output

func output_image() -> Image:
	return _output

func output_instance_id() -> int:
	return _output.get_instance_id() if _output != null else 0

static func draw_order_for(visual: Dictionary) -> Array[String]:
	var order: Array[String] = ["tail"]
	for segment_name in ["tail_segment_0", "tail_segment_1"]:
		if visual.layers.has(segment_name):
			order.append(segment_name)
	order.append_array(["leg_back_left", "leg_back_right", "leg_front_left", "leg_front_right", "body", "ear_left", "ear_right", "head"])
	return order

func transformed_joint_pixel(joint_name: String, pose: Dictionary) -> Vector2:
	var joint: Dictionary = _rig.joints[joint_name]
	var point := Renderer.CENTER + Vector2(joint.pivot)
	return _apply_joint_chain(point, joint_name, pose)

func _draw_part(part_name: String, pose: Dictionary) -> void:
	var packed: Dictionary = _visual.layers[part_name]
	var source: Image = packed.image
	var source_bounds: Rect2i = packed.bounds
	var corners := [
		Vector2(source_bounds.position),
		Vector2(source_bounds.end.x - 1, source_bounds.position.y),
		Vector2(source_bounds.position.x, source_bounds.end.y - 1),
		Vector2(source_bounds.end - Vector2i.ONE),
	]
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for corner in corners:
		var transformed := _apply_joint_chain(Vector2(corner), part_name, pose)
		minimum.x = minf(minimum.x, transformed.x)
		minimum.y = minf(minimum.y, transformed.y)
		maximum.x = maxf(maximum.x, transformed.x)
		maximum.y = maxf(maximum.y, transformed.y)
	var start := Vector2i(maxi(0, floori(minimum.x) - 1), maxi(0, floori(minimum.y) - 1))
	var finish := Vector2i(mini(_output.get_width() - 1, ceili(maximum.x) + 1), mini(_output.get_height() - 1, ceili(maximum.y) + 1))
	for y in range(start.y, finish.y + 1):
		for x in range(start.x, finish.x + 1):
			var source_point := Vector2i(_inverse_joint_chain(Vector2(x, y), part_name, pose).round())
			if source_point.x < 0 or source_point.y < 0 or source_point.x >= source.get_width() or source_point.y >= source.get_height():
				continue
			var color := source.get_pixelv(source_point)
			if color.a > 0.0:
				_output.set_pixel(x, y, color)

func _apply_joint_chain(point: Vector2, joint_name: String, pose: Dictionary) -> Vector2:
	var result := point
	var current := joint_name
	while current != "":
		var joint: Dictionary = _rig.joints[current]
		var pivot := Renderer.CENTER + Vector2(joint.pivot)
		result = _apply_transform(result, pivot, pose.transforms[current])
		current = String(joint.parent)
	return result

func _inverse_joint_chain(point: Vector2, joint_name: String, pose: Dictionary) -> Vector2:
	var chain: Array[String] = []
	var current := joint_name
	while current != "":
		chain.append(current)
		current = String(_rig.joints[current].parent)
	chain.reverse()
	var result := point
	for chain_joint in chain:
		var joint: Dictionary = _rig.joints[chain_joint]
		var pivot := Renderer.CENTER + Vector2(joint.pivot)
		result = _inverse_transform(result, pivot, pose.transforms[chain_joint])
	return result

func _apply_transform(point: Vector2, pivot: Vector2, transform: Dictionary) -> Vector2:
	var local: Vector2 = (point - pivot) * Vector2(transform.scale)
	return pivot + local.rotated(float(transform.rotation)) + Vector2(transform.translation)

func _inverse_transform(point: Vector2, pivot: Vector2, transform: Dictionary) -> Vector2:
	var local := (point - pivot - Vector2(transform.translation)).rotated(-float(transform.rotation))
	var scale_value := Vector2(transform.scale)
	return pivot + Vector2(local.x / maxf(scale_value.x, 0.001), local.y / maxf(scale_value.y, 0.001))

func _draw_overlay(pose: Dictionary) -> void:
	for joint_name in _rig.joints:
		if joint_name == "root":
			continue
		var joint: Dictionary = _rig.joints[joint_name]
		var point := transformed_joint_pixel(joint_name, pose)
		var parent_point := transformed_joint_pixel(String(joint.parent), pose)
		_draw_line(parent_point, point, Color("52e0d2"))
		_draw_cross(point, Color("ffcf5a"))
	var ground := Renderer.CENTER + Vector2(_rig.ground_contact)
	_draw_cross(ground, Color("ff6b7a"))

func _draw_line(from: Vector2, to: Vector2, color: Color) -> void:
	var steps := maxi(1, ceili(from.distance_to(to)))
	for index in range(steps + 1):
		var point := Vector2i(from.lerp(to, float(index) / float(steps)).round())
		if point.x >= 0 and point.y >= 0 and point.x < _output.get_width() and point.y < _output.get_height():
			_output.set_pixelv(point, color)

func _draw_cross(point: Vector2, color: Color) -> void:
	var center := Vector2i(point.round())
	for offset in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var pixel: Vector2i = center + Vector2i(offset)
		if pixel.x >= 0 and pixel.y >= 0 and pixel.x < _output.get_width() and pixel.y < _output.get_height():
			_output.set_pixelv(pixel, color)

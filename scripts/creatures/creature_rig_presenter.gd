extends Node2D
## Native E2A.1 presentation path. Cached procedural textures are parented to
## anatomy-derived Node2D pivots; each pose updates transforms only.

const Renderer = preload("res://scripts/creatures/creature_renderer.gd")
const RigRenderer = preload("res://scripts/creatures/creature_rig_renderer.gd")

static var _shared_shader: Shader

var _rig: Dictionary = {}
var _visual: Dictionary = {}
var _joint_nodes: Dictionary = {}
var _sprites: Dictionary = {}
var _draw_order: Array[String] = []
var _rest_positions: Dictionary = {}
var _silhouette_material: ShaderMaterial
var _joint_overlay := false
var _silhouette := false
var _foot_contacts := false
var _inspected_limb := ""
var _last_pose: Dictionary = {}
var update_count := 0
var configured_texture_count := 0
var disposed := false

func configure(rig: Dictionary, visual: Dictionary) -> void:
	_clear_rig()
	_rig = rig
	_visual = visual
	_draw_order = RigRenderer.draw_order_for(visual)
	_silhouette = false
	_build_material()
	_build_joint_nodes()
	_build_sprites()
	queue_redraw()

func apply_pose(pose: Dictionary) -> void:
	assert(not _rig.is_empty(), "Native rig presenter must be configured before applying a pose")
	for joint_name in _joint_nodes:
		var pose_transform: Dictionary = pose.transforms[joint_name]
		var node: Node2D = _joint_nodes[joint_name]
		node.position = Vector2(_rest_positions[joint_name]) + Vector2(pose_transform.translation)
		node.rotation = float(pose_transform.rotation)
		node.scale = Vector2(pose_transform.scale)
	_last_pose = pose
	update_count += 1
	if _joint_overlay or _foot_contacts or _inspected_limb != "":
		queue_redraw()

func set_joint_overlay(enabled: bool) -> void:
	if _joint_overlay == enabled:
		return
	_joint_overlay = enabled
	queue_redraw()

func set_silhouette(enabled: bool) -> void:
	if _silhouette == enabled:
		return
	_silhouette = enabled
	for sprite: Sprite2D in _sprites.values():
		sprite.material = _silhouette_material if enabled else null

func set_foot_contacts(enabled: bool) -> void:
	if _foot_contacts == enabled:
		return
	_foot_contacts = enabled
	queue_redraw()

func set_inspected_limb(limb_name: String) -> void:
	var resolved := limb_name if limb_name in _rig.get("feet", {}) else ""
	if _inspected_limb == resolved:
		return
	_inspected_limb = resolved
	queue_redraw()

func ground_contact_position() -> Vector2:
	return Vector2(_rig.ground_contact) if not _rig.is_empty() else Vector2.ZERO

func joint_position(joint_name: String) -> Vector2:
	if not _joint_nodes.has(joint_name):
		return Vector2.ZERO
	var result := Vector2.ZERO
	var current: Node = _joint_nodes[joint_name]
	while current != self:
		result = (current as Node2D).transform * result
		current = current.get_parent()
	return result

func foot_position(leg_name: String) -> Vector2:
	if not _joint_nodes.has(leg_name) or not _rig.feet.has(leg_name):
		return Vector2.ZERO
	var result := Vector2(_rig.feet[leg_name]) - Vector2(_rig.joints[leg_name].pivot)
	var current: Node = _joint_nodes[leg_name]
	while current != self:
		result = (current as Node2D).transform * result
		current = current.get_parent()
	return result

func texture_instance_ids() -> Array[int]:
	var ids: Array[int] = []
	for part_name in _draw_order:
		var sprite: Sprite2D = _sprites[part_name]
		ids.append(sprite.texture.get_instance_id())
	return ids

func is_configured() -> bool:
	return not _rig.is_empty() and _sprites.size() == _draw_order.size()

func joint_count() -> int:
	return _joint_nodes.size()

func _build_material() -> void:
	if _shared_shader == null:
		_shared_shader = Shader.new()
		_shared_shader.code = "shader_type canvas_item; uniform vec4 silhouette_color : source_color = vec4(0.851, 0.929, 0.949, 1.0); void fragment() { vec4 source = texture(TEXTURE, UV); COLOR = vec4(silhouette_color.rgb, source.a * silhouette_color.a); }"
	_silhouette_material = ShaderMaterial.new()
	_silhouette_material.shader = _shared_shader

func _build_joint_nodes() -> void:
	var pending: Array = _rig.joints.keys()
	while not pending.is_empty():
		var progressed := false
		for index in range(pending.size() - 1, -1, -1):
			var joint_name: String = pending[index]
			var joint: Dictionary = _rig.joints[joint_name]
			var parent_name := String(joint.parent)
			if parent_name != "" and not _joint_nodes.has(parent_name):
				continue
			var node := Node2D.new()
			node.name = StringName(joint_name)
			var parent: Node = self if parent_name == "" else _joint_nodes[parent_name]
			parent.add_child(node)
			var rest_position := Vector2(joint.pivot)
			if parent_name != "":
				rest_position -= Vector2(_rig.joints[parent_name].pivot)
			node.position = rest_position
			_joint_nodes[joint_name] = node
			_rest_positions[joint_name] = rest_position
			pending.remove_at(index)
			progressed = true
		assert(progressed, "Rig hierarchy contains an unresolved parent")

func _build_sprites() -> void:
	for draw_index in range(_draw_order.size()):
		var part_name: String = _draw_order[draw_index]
		var sprite := Sprite2D.new()
		sprite.name = StringName("%s_art" % part_name)
		sprite.texture = _visual.layers[part_name].texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.centered = true
		var texture_center := Vector2(sprite.texture.get_size()) * 0.5
		sprite.position = -Vector2(_rig.joints[part_name].pivot) + texture_center - Renderer.CENTER
		sprite.z_as_relative = false
		sprite.z_index = draw_index
		_joint_nodes[part_name].add_child(sprite)
		_sprites[part_name] = sprite
		configured_texture_count += 1

func _clear_rig() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_joint_nodes.clear()
	_sprites.clear()
	_draw_order.clear()
	_rest_positions.clear()
	_last_pose.clear()
	configured_texture_count = 0

func _draw() -> void:
	if _rig.is_empty():
		return
	if _joint_overlay:
		for joint_name in _rig.joints:
			if joint_name == "root":
				continue
			var joint: Dictionary = _rig.joints[joint_name]
			var point := joint_position(joint_name)
			var parent_point := joint_position(String(joint.parent))
			draw_line(parent_point, point, Color("52e0d2"), 1.0)
			draw_rect(Rect2(point - Vector2.ONE, Vector2(3, 3)), Color("ffcf5a"), true)
		var ground := ground_contact_position()
		draw_line(ground - Vector2(3, 0), ground + Vector2(3, 0), Color("ff6b7a"), 1.0)
		draw_line(ground - Vector2(0, 3), ground + Vector2(0, 3), Color("ff6b7a"), 1.0)
	if (_foot_contacts or _inspected_limb != "") and not _last_pose.is_empty():
		for leg_name in _rig.feet:
			if _inspected_limb != "" and leg_name != _inspected_limb:
				continue
			var foot := foot_position(leg_name)
			var contact: bool = _last_pose.gait.legs[leg_name].contact
			var color := Color("72e39a") if contact else Color("ffad5a")
			var size := 5.0 if leg_name == _inspected_limb else 3.0
			draw_rect(Rect2(foot - Vector2.ONE * size * 0.5, Vector2.ONE * size), color, false, 1.0)
			if leg_name == _inspected_limb:
				draw_line(joint_position(leg_name), foot, Color("f28cff"), 1.0)

func _exit_tree() -> void:
	disposed = true

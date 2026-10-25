extends RefCounted
## Immutable, scene-tree-independent skeletal definition derived from generated
## anatomy. Runtime animation state belongs to poses, never to this definition.

const Generator = preload("res://scripts/creatures/creature_generator.gd")
const Species = preload("res://scripts/creatures/creature_species.gd")

const RIG_VERSION := "e2b-rig-v1"
const JOINT_NAMES := [
	"root", "body", "tail", "leg_back_left", "leg_back_right",
	"leg_front_left", "leg_front_right", "head", "ear_left", "ear_right",
]

static func build(anatomy: Dictionary) -> Dictionary:
	var d: Dictionary = anatomy.dimensions
	var a: Dictionary = anatomy.attachments
	var head_pivot: Vector2 = a.head_root
	var forward_extent: float = head_pivot.y + float(d.neck_length) + float(d.head_size) * 0.92 + float(d.snout_length) * 0.55
	var leg_extent: float = maxf(float(a.leg_front_left.y), float(a.leg_front_right.y)) + float(d.leg_length) * 0.3
	var ground_contact := Vector2(0.0, maxf(forward_extent, leg_extent))
	var feet: Dictionary = {}
	for leg_name in ["leg_front_left", "leg_front_right", "leg_back_left", "leg_back_right"]:
		var leg_root: Vector2 = a[leg_name]
		var side := -1.0 if leg_root.x < 0.0 else 1.0
		var pair_sign := -1.0 if leg_root.y < 0.0 else 1.0
		feet[leg_name] = leg_root + Vector2(side * float(d.leg_length) * float(d.leg_splay), pair_sign * float(d.leg_length) * 0.3)
	var joints := {
		"root": _joint("root", "", Vector2.ZERO),
		"body": _joint("body", "root", Vector2.ZERO),
		"tail": _joint("tail", "root", a.tail_root),
		"leg_back_left": _joint("leg_back_left", "root", a.leg_back_left),
		"leg_back_right": _joint("leg_back_right", "root", a.leg_back_right),
		"leg_front_left": _joint("leg_front_left", "root", a.leg_front_left),
		"leg_front_right": _joint("leg_front_right", "root", a.leg_front_right),
		"head": _joint("head", "root", head_pivot),
		"ear_left": _joint("ear_left", "head", a.ear_left),
		"ear_right": _joint("ear_right", "head", a.ear_right),
	}
	var tail_segments: Array[String] = []
	if float(d.tail_length) >= 13.0:
		for index in range(2):
			var t: float = float([3.0 / 8.0, 6.0 / 8.0][index])
			var segment_name := "tail_segment_%d" % index
			var curve_scale := 0.45 if anatomy.traits.tail_shape == "rounded" else 1.0
			var segment_pivot := Vector2(a.tail_root) + Vector2(float(anatomy.traits.tail_curve) * float(d.tail_length) * t * t * curve_scale, -float(d.tail_length) * t)
			joints[segment_name] = _joint(segment_name, "tail" if index == 0 else "tail_segment_%d" % (index - 1), segment_pivot)
			tail_segments.append(segment_name)
	return {
		"version": RIG_VERSION,
		"generator_version": anatomy.generator_version,
		"species_id": anatomy.species_id,
		"individual_seed": anatomy.individual_seed,
		"archetype": anatomy.archetype,
		"anatomy_signature": Generator.anatomy_signature(anatomy),
		"joints": joints,
		"feet": feet,
		"tail_segments": tail_segments,
		"ground_contact": ground_contact,
		"gait_profile": Species.gait_profile(anatomy.archetype),
	}

static func _joint(joint_name: String, parent_name: String, pivot: Vector2) -> Dictionary:
	return {"name": joint_name, "parent": parent_name, "pivot": pivot}

static func is_valid(rig: Dictionary) -> bool:
	if rig.get("version", "") != RIG_VERSION or not rig.has("joints") or not rig.has("feet") or not rig.has("gait_profile"):
		return false
	var joints: Dictionary = rig.joints
	for joint_name in JOINT_NAMES:
		if not joints.has(joint_name):
			return false
	for joint_name in joints:
		var joint: Dictionary = joints[joint_name]
		if not joint.get("pivot") is Vector2:
			return false
		var parent_name: String = joint.get("parent", "")
		if parent_name != "" and not joints.has(parent_name):
			return false
	for leg_name in ["leg_front_left", "leg_front_right", "leg_back_left", "leg_back_right"]:
		if not rig.feet.get(leg_name) is Vector2:
			return false
	return rig.get("ground_contact") is Vector2

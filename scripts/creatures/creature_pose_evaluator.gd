extends RefCounted
## Pure deterministic E2B pose evaluation. Archetype gait data drives bounded
## joint transforms and explicit foot-contact metadata without mutating the rig.

const Rig = preload("res://scripts/creatures/creature_rig.gd")

const STATES := ["neutral", "idle", "walk"]
const LEG_NAMES := ["leg_front_left", "leg_back_right", "leg_front_right", "leg_back_left"]
const LEG_PHASE_OFFSETS := {
	"leg_front_left": 0.0,
	"leg_back_right": 0.25,
	"leg_front_right": 0.5,
	"leg_back_left": 0.75,
}

static func evaluate_pose(rig: Dictionary, animation_state: String, time: float, movement_parameters: Dictionary = {}) -> Dictionary:
	assert(Rig.is_valid(rig), "Pose evaluation requires a valid creature rig")
	var state := animation_state if animation_state in STATES else "neutral"
	var speed: float = maxf(0.0, float(movement_parameters.get("speed", 1.0)))
	var intensity: float = clampf(float(movement_parameters.get("intensity", 1.0)), 0.0, 1.5)
	var evaluated_time := time * speed
	var transforms: Dictionary = {}
	for joint_name in rig.joints:
		transforms[joint_name] = _identity_transform()
	var gait: Dictionary
	match state:
		"neutral":
			gait = _rest_gait(rig, state)
		"idle":
			gait = _rest_gait(rig, state)
			_apply_idle(transforms, rig, evaluated_time, intensity)
		"walk":
			gait = _apply_walk(transforms, rig, evaluated_time, intensity, movement_parameters)
	return {
		"rig_version": rig.version,
		"anatomy_signature": rig.anatomy_signature,
		"state": state,
		"time": time,
		"transforms": transforms,
		"ground_contact": rig.ground_contact,
		"gait": gait,
	}

static func evaluate_transition(rig: Dictionary, from_state: String, to_state: String, time: float, progress: float, movement_parameters: Dictionary = {}) -> Dictionary:
	var source := evaluate_pose(rig, from_state, time, movement_parameters)
	var target := evaluate_pose(rig, to_state, time, movement_parameters)
	var linear_weight := clampf(progress, 0.0, 1.0)
	var smooth_weight := linear_weight * linear_weight * (3.0 - 2.0 * linear_weight)
	var blended := interpolate_pose(source, target, smooth_weight)
	blended["transition"] = {"from": source.state, "to": target.state, "progress": linear_weight, "weight": smooth_weight}
	return blended

static func interpolate_pose(from_pose: Dictionary, to_pose: Dictionary, weight: float) -> Dictionary:
	var amount := clampf(weight, 0.0, 1.0)
	if amount <= 0.0:
		return from_pose.duplicate(true)
	if amount >= 1.0:
		return to_pose.duplicate(true)
	var transforms: Dictionary = {}
	for joint_name in from_pose.transforms:
		var from_transform: Dictionary = from_pose.transforms.get(joint_name, _identity_transform())
		var to_transform: Dictionary = to_pose.transforms.get(joint_name, _identity_transform())
		transforms[joint_name] = {
			"translation": Vector2(from_transform.translation).lerp(Vector2(to_transform.translation), amount),
			"rotation": lerp_angle(float(from_transform.rotation), float(to_transform.rotation), amount),
			"scale": Vector2(from_transform.scale).lerp(Vector2(to_transform.scale), amount),
		}
	return {
		"rig_version": to_pose.rig_version,
		"anatomy_signature": to_pose.anatomy_signature,
		"state": to_pose.state,
		"time": lerpf(float(from_pose.time), float(to_pose.time), amount),
		"transforms": transforms,
		"ground_contact": Vector2(from_pose.ground_contact).lerp(Vector2(to_pose.ground_contact), amount),
		"gait": to_pose.gait.duplicate(true),
	}

static func _apply_idle(transforms: Dictionary, rig: Dictionary, time: float, intensity: float) -> void:
	var profile: Dictionary = rig.gait_profile
	var breath := sin(time * TAU * 0.72) * intensity * float(profile.breathing)
	transforms.body.scale = Vector2(1.0 + breath * 0.012, 1.0 + breath * 0.018)
	transforms.body.translation = Vector2(0.0, -absf(breath) * 0.16)
	var head_amount := float(profile.head_motion)
	transforms.head.rotation = sin(time * TAU * 0.31 + 0.5) * head_amount * 0.62 * intensity
	transforms.head.translation = Vector2(0.0, breath * 0.1)
	var tail_amount := float(profile.tail_motion)
	transforms.tail.rotation = sin(time * TAU * 0.48) * tail_amount * 0.75 * intensity
	_apply_tail_follow(transforms, rig, time * TAU * 0.48, tail_amount * 0.32 * intensity)
	transforms.ear_left.rotation = sin(time * TAU * 0.37 + 1.2) * 0.032 * intensity
	transforms.ear_right.rotation = -sin(time * TAU * 0.37 + 1.2) * 0.032 * intensity

static func _apply_walk(transforms: Dictionary, rig: Dictionary, time: float, intensity: float, movement_parameters: Dictionary) -> Dictionary:
	var profile: Dictionary = rig.gait_profile
	var cadence: float = float(profile.cadence) * clampf(float(movement_parameters.get("cadence_scale", 1.0)), 0.25, 2.0)
	var stance_ratio: float = clampf(float(profile.stance_ratio), 0.55, 0.8)
	var stride_multiplier: float = clampf(float(movement_parameters.get("stride", 1.0)), 0.25, 1.5)
	var global_phase := fposmod(time * cadence, 1.0)
	var leg_data: Dictionary = {}
	var average_stride := 0.0
	for leg_name in LEG_NAMES:
		var leg_root: Vector2 = rig.joints[leg_name].pivot
		var foot_point: Vector2 = rig.feet[leg_name]
		var reach := foot_point - leg_root
		var stride_distance := reach.length() * float(profile.stride_scale) * stride_multiplier * intensity
		average_stride += stride_distance / float(LEG_NAMES.size())
		var leg_phase := fposmod(global_phase + float(LEG_PHASE_OFFSETS[leg_name]), 1.0)
		var contact := leg_phase < stance_ratio
		var stance_progress := clampf(leg_phase / stance_ratio, 0.0, 1.0) if contact else 1.0
		var swing_progress := 0.0 if contact else clampf((leg_phase - stance_ratio) / (1.0 - stance_ratio), 0.0, 1.0)
		var lift := 0.0
		var stride_offset: float
		if contact:
			stride_offset = lerpf(stride_distance * 0.5, -stride_distance * 0.5, stance_progress)
		else:
			var smooth_swing := swing_progress * swing_progress * (3.0 - 2.0 * swing_progress)
			stride_offset = lerpf(-stride_distance * 0.5, stride_distance * 0.5, smooth_swing)
			lift = sin(swing_progress * PI)
		var lateral_reach := reach.x
		var rotation := stride_offset / lateral_reach if absf(lateral_reach) > 0.1 else 0.0
		rotation = clampf(rotation, -float(profile.max_leg_rotation), float(profile.max_leg_rotation))
		transforms[leg_name].rotation = rotation
		transforms[leg_name].scale = Vector2(1.0 - lift * float(profile.foot_lift), 1.0)
		leg_data[leg_name] = {
			"phase": leg_phase,
			"phase_offset": LEG_PHASE_OFFSETS[leg_name],
			"state": "stance" if contact else "swing",
			"contact": contact,
			"stance_progress": stance_progress,
			"swing_progress": swing_progress,
			"lift": lift,
			"stride_offset": stride_offset,
			"stride_distance": stride_distance,
		}
	var cycle := global_phase * TAU
	var support_wave := sin(cycle * 2.0)
	var body_bob := absf(sin(cycle * 2.0)) * float(profile.body_bob) * intensity
	transforms.body.translation = Vector2(sin(cycle) * float(profile.weight_shift) * intensity, -body_bob)
	transforms.body.rotation = support_wave * float(profile.body_sway) * intensity
	var head_motion := float(profile.head_motion) * intensity
	transforms.head.rotation = -support_wave * head_motion
	transforms.head.translation = Vector2(-sin(cycle) * float(profile.weight_shift) * 0.3 * intensity, body_bob * 0.28)
	var tail_motion := float(profile.tail_motion) * intensity
	transforms.tail.rotation = sin(cycle - 0.55) * tail_motion
	_apply_tail_follow(transforms, rig, cycle - 0.55, tail_motion * 0.48)
	transforms.ear_left.rotation = sin(cycle + 0.35) * head_motion * 0.42
	transforms.ear_right.rotation = -sin(cycle - 0.35) * head_motion * 0.42
	return {
		"state": "walk",
		"archetype": rig.archetype,
		"phase": global_phase,
		"cadence": cadence,
		"stance_ratio": stance_ratio,
		"ground_speed": average_stride * cadence / stance_ratio,
		"legs": leg_data,
	}

static func _apply_tail_follow(transforms: Dictionary, rig: Dictionary, phase: float, amplitude: float) -> void:
	for index in range(rig.tail_segments.size()):
		var segment_name: String = rig.tail_segments[index]
		transforms[segment_name].rotation = sin(phase - float(index + 1) * 0.48) * amplitude * (1.0 + float(index) * 0.28)

static func _rest_gait(rig: Dictionary, state: String) -> Dictionary:
	var legs: Dictionary = {}
	for leg_name in LEG_NAMES:
		legs[leg_name] = {
			"phase": 0.0, "phase_offset": LEG_PHASE_OFFSETS[leg_name],
			"state": "stance", "contact": true, "stance_progress": 0.0,
			"swing_progress": 0.0, "lift": 0.0, "stride_offset": 0.0,
			"stride_distance": 0.0,
		}
	return {
		"state": state, "archetype": rig.archetype, "phase": 0.0,
		"cadence": 0.0, "stance_ratio": float(rig.gait_profile.stance_ratio),
		"ground_speed": 0.0, "legs": legs,
	}

static func _identity_transform() -> Dictionary:
	return {"translation": Vector2.ZERO, "rotation": 0.0, "scale": Vector2.ONE}

extends RefCounted
## Immutable E1 species data. Runtime anatomy is produced by CreatureGenerator;
## this file owns only authored bases, safe sampling ranges, and palette families.

const SPECIES_ID := "wyntar_quadruped"
const ARCHETYPES := ["compact", "elongated", "stocky"]

const GAIT_PROFILES := {
	"compact": {
		"cadence": 1.9, "stance_ratio": 0.64, "stride_scale": 0.64,
		"foot_lift": 0.16, "max_leg_rotation": 0.23, "body_bob": 0.52,
		"body_sway": 0.016, "weight_shift": 0.16, "head_motion": 0.075,
		"tail_motion": 0.14, "breathing": 1.08,
	},
	"elongated": {
		"cadence": 1.35, "stance_ratio": 0.62, "stride_scale": 1.02,
		"foot_lift": 0.14, "max_leg_rotation": 0.31, "body_bob": 0.28,
		"body_sway": 0.034, "weight_shift": 0.11, "head_motion": 0.038,
		"tail_motion": 0.25, "breathing": 0.9,
	},
	"stocky": {
		"cadence": 1.05, "stance_ratio": 0.72, "stride_scale": 0.55,
		"foot_lift": 0.1, "max_leg_rotation": 0.18, "body_bob": 0.18,
		"body_sway": 0.018, "weight_shift": 0.28, "head_motion": 0.052,
		"tail_motion": 0.1, "breathing": 0.82,
	},
}

const PROFILES := {
	"compact": {
		"torso_length": [17.5, 15.0, 20.0], "torso_width": [15.5, 13.5, 18.0],
		"torso_roundness": [0.94, 0.82, 1.0], "torso_taper": [0.05, 0.0, 0.12],
		"shoulder_scale": [0.96, 0.9, 1.02], "hip_scale": [1.02, 0.96, 1.08],
		"head_size": [11.5, 10.0, 13.0], "head_width": [13.0, 11.5, 15.0],
		"snout_length": [3.0, 2.0, 4.2], "snout_width": [0.72, 0.62, 0.82],
		"leg_length": [6.2, 5.0, 7.5], "leg_thickness": [3.2, 2.5, 4.0],
		"leg_splay": [0.9, 0.78, 1.0], "leg_pair_separation": [0.46, 0.38, 0.54],
		"ear_size": [5.4, 4.2, 6.6], "neck_length": [1.2, 0.6, 2.0],
		"tail_length": [7.0, 4.5, 9.5], "tail_thickness": [3.4, 2.8, 4.4],
	},
	"elongated": {
		"torso_length": [28.0, 25.0, 31.0], "torso_width": [11.5, 10.0, 13.0],
		"torso_roundness": [0.46, 0.34, 0.58], "torso_taper": [0.25, 0.16, 0.36],
		"shoulder_scale": [0.94, 0.88, 1.0], "hip_scale": [0.86, 0.8, 0.92],
		"head_size": [8.0, 7.0, 9.2], "head_width": [8.5, 7.4, 9.6],
		"snout_length": [5.8, 4.5, 7.0], "snout_width": [0.44, 0.34, 0.54],
		"leg_length": [9.5, 7.5, 11.5], "leg_thickness": [2.0, 1.6, 2.5],
		"leg_splay": [0.68, 0.56, 0.8], "leg_pair_separation": [0.72, 0.64, 0.8],
		"ear_size": [4.2, 3.2, 5.4], "neck_length": [2.2, 1.4, 3.0],
		"tail_length": [19.0, 16.0, 22.0], "tail_thickness": [2.0, 1.5, 2.6],
	},
	"stocky": {
		"torso_length": [21.0, 18.5, 23.5], "torso_width": [19.0, 17.0, 21.0],
		"torso_roundness": [0.76, 0.64, 0.88], "torso_taper": [0.14, 0.06, 0.22],
		"shoulder_scale": [1.18, 1.1, 1.26], "hip_scale": [0.9, 0.82, 0.98],
		"head_size": [12.0, 10.5, 13.5], "head_width": [15.0, 13.5, 16.5],
		"snout_length": [5.0, 4.0, 6.2], "snout_width": [0.82, 0.72, 0.94],
		"leg_length": [5.8, 4.5, 7.0], "leg_thickness": [4.8, 4.0, 5.6],
		"leg_splay": [0.72, 0.62, 0.82], "leg_pair_separation": [0.5, 0.42, 0.58],
		"ear_size": [3.5, 2.6, 4.5], "neck_length": [0.8, 0.3, 1.4],
		"tail_length": [7.5, 5.0, 10.0], "tail_thickness": [4.8, 4.0, 5.8],
	},
}

const COAT_FAMILIES := [
	[[74, 50, 39], [128, 88, 57], [190, 142, 85]],
	[[48, 57, 67], [91, 105, 112], [157, 171, 164]],
	[[92, 57, 29], [161, 102, 46], [220, 171, 91]],
	[[57, 65, 39], [105, 116, 62], [173, 169, 93]],
	[[72, 45, 63], [124, 76, 99], [190, 133, 137]],
	[[38, 61, 64], [60, 111, 112], [117, 170, 153]],
]

static func is_valid_species(species_id: String) -> bool:
	return species_id == SPECIES_ID

static func resolve_archetype(archetype: String) -> String:
	return archetype if archetype in ARCHETYPES else "compact"

static func profile(archetype: String) -> Dictionary:
	return PROFILES[resolve_archetype(archetype)]

static func gait_profile(archetype: String) -> Dictionary:
	return GAIT_PROFILES[resolve_archetype(archetype)].duplicate(true)

static func head_shapes(archetype: String) -> Array:
	match resolve_archetype(archetype):
		"compact": return ["rounded", "rounded", "broad"]
		"elongated": return ["wedge", "wedge", "rounded"]
		_: return ["broad", "broad", "rounded"]

static func ear_shapes(archetype: String) -> Array:
	match resolve_archetype(archetype):
		"compact": return ["round", "pointed", "round"]
		"elongated": return ["pointed", "long", "pointed"]
		_: return ["round", "outward", "round"]

extends RefCounted
## Versioned JSON persistence for authoritative world state. The service owns
## serialization and filesystem recovery; simulation owners validate/import.

const TerrainWorld = preload("res://scripts/terrain_world.gd")
const ResourceStateManager = preload("res://scripts/resource_state_manager.gd")
const EnvironmentObjectCatalog = preload("res://scripts/environment_object_catalog.gd")

const FORMAT_VERSION: int = 1
const TERRAIN_RULES_ID: String = "universal-mask-terrain-godot47-v1"
const OBJECT_CATALOG_ID: String = "environment-catalog-phase8b-v1"
const SAVE_DIRECTORY: String = "user://saves"
const DEFAULT_SAVE_PATH: String = "user://saves/quicksave.json"


func capture_snapshot(
		terrain, camera: Camera2D,
		world_id: String, display_name: String) -> Dictionary:
	var authoritative: Dictionary = terrain.export_authoritative_snapshot()
	return {
		"format_version": FORMAT_VERSION,
		"compatibility": {
			"terrain_rules": TERRAIN_RULES_ID,
			"object_catalog": OBJECT_CATALOG_ID,
		},
		"world": {
			"id": world_id,
			"display_name": display_name,
			"generation": terrain.export_generation_config(),
			"camera": {
				"x": camera.position.x, "y": camera.position.y,
				"zoom": camera.zoom.x,
			},
		},
		"terrain": authoritative["terrain"],
		"resources": authoritative["resources"],
	}


func validate_snapshot(value: Variant) -> Dictionary:
	var validation_start: int = Time.get_ticks_usec()
	var error: String = _validate_top_level(value)
	if not error.is_empty():
		return _failure(error, validation_start)
	var snapshot: Dictionary = value
	var world: Dictionary = snapshot["world"]
	var generation_result: Dictionary = _validate_generation_config(world["generation"])
	if not bool(generation_result["ok"]):
		return _failure(String(generation_result["error"]), validation_start)
	var terrain_validator = TerrainWorld.new()
	var terrain_result: Dictionary = terrain_validator.validate_override_snapshot(snapshot["terrain"])
	if not bool(terrain_result["ok"]):
		return _failure(String(terrain_result["error"]), validation_start)
	var resource_validator = ResourceStateManager.new()
	resource_validator.configure(
		int(generation_result["config"]["world_seed"]),
		EnvironmentObjectCatalog.build_by_id())
	var resource_result: Dictionary = resource_validator.validate_snapshot(snapshot["resources"])
	if not bool(resource_result["ok"]):
		return _failure(String(resource_result["error"]), validation_start)
	var camera_result: Dictionary = _validate_camera(world.get("camera", {}))
	if not bool(camera_result["ok"]):
		return _failure(String(camera_result["error"]), validation_start)
	var normalized: Dictionary = snapshot.duplicate(true)
	normalized["world"]["generation"] = generation_result["config"]
	normalized["world"]["camera"] = camera_result["camera"]
	return {
		"ok": true, "error": "", "snapshot": normalized,
		"validation_usec": Time.get_ticks_usec() - validation_start,
	}


func save_snapshot(snapshot: Dictionary, path: String = DEFAULT_SAVE_PATH) -> Dictionary:
	var validation: Dictionary = validate_snapshot(snapshot)
	if not bool(validation["ok"]):
		return validation
	var serialization_start: int = Time.get_ticks_usec()
	var json_text: String = JSON.stringify(validation["snapshot"], "  ", false)
	var serialization_usec: int = Time.get_ticks_usec() - serialization_start
	var absolute_path: String = ProjectSettings.globalize_path(path)
	var absolute_directory: String = absolute_path.get_base_dir()
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK:
		return {"ok": false, "error": "Could not create save directory: %s" % error_string(directory_error)}
	var temporary_path: String = absolute_path + ".tmp"
	var backup_path: String = absolute_path + ".bak"
	var backup_candidate_path: String = absolute_path + ".bak.new"
	_remove_if_present(temporary_path)
	_remove_if_present(backup_candidate_path)
	var write_start: int = Time.get_ticks_usec()
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Could not open temporary save: %s" % FileAccess.get_open_error()}
	file.store_string(json_text)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		return {"ok": false, "error": "Temporary save write failed: %s" % error_string(write_error)}
	var temporary_validation: Dictionary = load_snapshot(temporary_path, true)
	if not bool(temporary_validation["ok"]):
		return {"ok": false, "error": "Written temporary save failed validation: %s" % temporary_validation["error"]}
	if FileAccess.file_exists(absolute_path):
		var existing_validation: Dictionary = load_snapshot(absolute_path, true)
		if bool(existing_validation["ok"]):
			var backup_error: Error = DirAccess.copy_absolute(absolute_path, backup_candidate_path)
			if backup_error != OK:
				return {"ok": false, "error": "Could not preserve previous save: %s" % error_string(backup_error)}
			var candidate_validation: Dictionary = load_snapshot(backup_candidate_path, true)
			if not bool(candidate_validation["ok"]):
				return {"ok": false, "error": "Backup copy failed validation"}
			_remove_if_present(backup_path)
			var backup_commit_error: Error = DirAccess.rename_absolute(backup_candidate_path, backup_path)
			if backup_commit_error != OK:
				return {"ok": false, "error": "Could not establish backup: %s" % error_string(backup_commit_error)}
		var remove_error: Error = DirAccess.remove_absolute(absolute_path)
		if remove_error != OK:
			return {"ok": false, "error": "Could not replace existing save: %s" % error_string(remove_error)}
	var replace_error: Error = DirAccess.rename_absolute(temporary_path, absolute_path)
	if replace_error != OK:
		if FileAccess.file_exists(backup_path) and not FileAccess.file_exists(absolute_path):
			DirAccess.copy_absolute(backup_path, absolute_path)
		return {"ok": false, "error": "Could not install new save; backup recovery attempted: %s" % error_string(replace_error)}
	var final_validation: Dictionary = load_snapshot(absolute_path, true)
	if not bool(final_validation["ok"]):
		if FileAccess.file_exists(backup_path):
			_remove_if_present(absolute_path)
			DirAccess.copy_absolute(backup_path, absolute_path)
		return {"ok": false, "error": "Installed save failed validation; backup recovery attempted"}
	return {
		"ok": true, "error": "", "path": path,
		"serialization_usec": serialization_usec,
		"write_usec": Time.get_ticks_usec() - write_start,
		"size_bytes": FileAccess.get_file_as_bytes(absolute_path).size(),
	}


func load_snapshot(path: String = DEFAULT_SAVE_PATH, absolute: bool = false) -> Dictionary:
	var load_start: int = Time.get_ticks_usec()
	var resolved_path: String = path if absolute else ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(resolved_path):
		return {"ok": false, "error": "Save file does not exist: %s" % path}
	var file := FileAccess.open(resolved_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Could not open save file: %s" % FileAccess.get_open_error()}
	var text: String = file.get_as_text()
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK:
		return {"ok": false, "error": "Could not read save file: %s" % error_string(read_error)}
	var parser := JSON.new()
	var parse_error: Error = parser.parse(text)
	if parse_error != OK:
		return {"ok": false, "error": "Corrupt JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]}
	var validation: Dictionary = validate_snapshot(parser.data)
	if not bool(validation["ok"]):
		return validation
	validation["load_usec"] = Time.get_ticks_usec() - load_start
	validation["size_bytes"] = text.to_utf8_buffer().size()
	return validation


func _validate_top_level(value: Variant) -> String:
	if not value is Dictionary:
		return "Save root must be an object"
	var snapshot: Dictionary = value
	var version_result: Dictionary = _exact_integer(snapshot.get("format_version"), "format_version")
	if not bool(version_result["ok"]):
		return String(version_result["error"])
	if int(version_result["value"]) != FORMAT_VERSION:
		return "Unsupported save format version %d" % int(version_result["value"])
	if not snapshot.get("compatibility") is Dictionary:
		return "compatibility must be an object"
	var compatibility: Dictionary = snapshot["compatibility"]
	if String(compatibility.get("terrain_rules", "")) != TERRAIN_RULES_ID:
		return "Incompatible terrain generation rules"
	if String(compatibility.get("object_catalog", "")) != OBJECT_CATALOG_ID:
		return "Incompatible environmental-object catalog"
	if not snapshot.get("world") is Dictionary:
		return "world must be an object"
	var world: Dictionary = snapshot["world"]
	var world_id: Variant = world.get("id")
	if not world_id is String or String(world_id).is_empty() or String(world_id).length() > 64:
		return "World identifier must be a non-empty string of at most 64 characters"
	for character in String(world_id):
		if not (character.is_valid_int() or character.to_lower() != character.to_upper() or character in ["-", "_"]):
			return "World identifier contains unsupported characters"
	var display_name: Variant = world.get("display_name")
	if not display_name is String or String(display_name).is_empty() or String(display_name).length() > 100:
		return "World display name must be 1–100 characters"
	if not world.get("generation") is Dictionary:
		return "world.generation must be an object"
	if not snapshot.has("terrain") or not snapshot.has("resources"):
		return "Save is missing authoritative terrain or resource state"
	return ""


func _validate_generation_config(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "error": "Generation configuration must be an object"}
	var source: Dictionary = value
	var ranges: Dictionary = {
		"world_seed": [-2147483648.0, 2147483647.0, true],
		"biome_frequency": [0.000001, 1.0, false],
		"detail_frequency": [0.000001, 1.0, false],
		"max_generated_elevation": [0.0, 3.0, true],
		"elevation_frequency": [0.000001, 1.0, false],
		"elevation_detail_frequency": [0.000001, 1.0, false],
		"elevation_detail_strength": [0.0, 1.0, false],
		"elevation_threshold_1": [-1.0, 1.0, false],
		"elevation_threshold_2": [-1.0, 1.0, false],
		"elevation_threshold_3": [-1.0, 1.0, false],
		"elevation_flatness_bias": [-1.0, 1.0, false],
		"sea_level": [0.0, 3.0, true],
		"decoration_density": [0.0, 2.0, false],
		"decoration_clustering_strength": [0.0, 1.0, false],
		"decoration_seed_offset": [-2147483648.0, 2147483647.0, true],
		"environment_object_density": [0.0, 2.0, false],
		"environment_object_seed_offset": [-2147483648.0, 2147483647.0, true],
	}
	var normalized: Dictionary = {}
	for key in ranges:
		var result: Dictionary = (
			_exact_integer(source.get(key), key)
			if bool(ranges[key][2]) else _finite_number(source.get(key), key))
		if not bool(result["ok"]):
			return result
		var number: float = float(result["value"])
		if number < float(ranges[key][0]) or number > float(ranges[key][1]):
			return {"ok": false, "error": "%s is outside the supported range" % key}
		normalized[key] = int(result["value"]) if bool(ranges[key][2]) else number
	for key in ["include_origin_demo", "procedural_elevation_enabled",
			"decoration_generation_enabled", "environment_object_generation_enabled"]:
		if not source.get(key) is bool:
			return {"ok": false, "error": "%s must be boolean" % key}
		normalized[key] = bool(source[key])
	if not (float(normalized["elevation_threshold_1"]) < float(normalized["elevation_threshold_2"])
			and float(normalized["elevation_threshold_2"]) < float(normalized["elevation_threshold_3"])):
		return {"ok": false, "error": "Elevation thresholds must be strictly increasing"}
	return {"ok": true, "error": "", "config": normalized}


func _validate_camera(value: Variant) -> Dictionary:
	if value == null or (value is Dictionary and value.is_empty()):
		return {"ok": true, "error": "", "camera": {}}
	if not value is Dictionary:
		return {"ok": false, "error": "Camera state must be an object"}
	var normalized: Dictionary = {}
	for key in ["x", "y", "zoom"]:
		var result: Dictionary = _finite_number(value.get(key), "camera.%s" % key)
		if not bool(result["ok"]):
			return result
		normalized[key] = float(result["value"])
	if absf(float(normalized["x"])) > 10000000000.0 or absf(float(normalized["y"])) > 10000000000.0:
		return {"ok": false, "error": "Camera position exceeds supported range"}
	if float(normalized["zoom"]) < 0.1 or float(normalized["zoom"]) > 10.0:
		return {"ok": false, "error": "Camera zoom exceeds supported range"}
	return {"ok": true, "error": "", "camera": normalized}


static func _exact_integer(value: Variant, label: String) -> Dictionary:
	if not value is int and not value is float:
		return {"ok": false, "error": "%s must be an integer" % label}
	var integer: int = int(value)
	if float(integer) != float(value):
		return {"ok": false, "error": "%s must be an integer" % label}
	return {"ok": true, "error": "", "value": integer}


static func _finite_number(value: Variant, label: String) -> Dictionary:
	if not value is int and not value is float:
		return {"ok": false, "error": "%s must be numeric" % label}
	var number: float = float(value)
	if not is_finite(number):
		return {"ok": false, "error": "%s must be finite" % label}
	return {"ok": true, "error": "", "value": number}


static func _failure(message: String, validation_start: int) -> Dictionary:
	return {
		"ok": false, "error": message,
		"validation_usec": Time.get_ticks_usec() - validation_start,
	}


static func _remove_if_present(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

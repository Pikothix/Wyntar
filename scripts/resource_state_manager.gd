extends RefCounted
## Authoritative runtime owner for sparse deviations from deterministic resource
## placement. Render batches consume snapshots; they never mutate this state.

signal resource_changed(resource_id: String, anchor: Vector2i, definition_id: int, change_kind: String)
signal inventory_changed(totals: Dictionary)

const DEFAULT_BERRY_REGROWTH_SECONDS: float = 120.0
const MAX_INVENTORY_QUANTITY: int = 2147483647

var world_seed: int
var definitions_by_id: Dictionary
var berry_regrowth_seconds: float = DEFAULT_BERRY_REGROWTH_SECONDS
var simulated_time: float = 0.0

var _states: Dictionary = {} # stable resource id -> changed state only
var _inventory: Dictionary = {"wood": 0, "stone": 0, "food": 0}
var _next_regrowth_time: float = INF


func configure(seed: int, definitions: Dictionary, regrowth_seconds: float = DEFAULT_BERRY_REGROWTH_SECONDS) -> void:
	world_seed = seed
	definitions_by_id = definitions
	berry_regrowth_seconds = maxf(0.01, regrowth_seconds)


func make_resource_id(definition_id: int, anchor: Vector2i) -> String:
	return "%d:%d:%d:%d" % [world_seed, anchor.x, anchor.y, definition_id]


func get_snapshot(definition_id: int, anchor: Vector2i) -> Dictionary:
	var resource_id: String = make_resource_id(definition_id, anchor)
	if _states.has(resource_id):
		return _states[resource_id].duplicate(true)
	return _baseline_snapshot(definition_id, anchor)


func get_snapshot_by_id(resource_id: String) -> Dictionary:
	if _states.has(resource_id):
		return _states[resource_id].duplicate(true)
	var parts: PackedStringArray = resource_id.split(":")
	if parts.size() != 4 or int(parts[0]) != world_seed:
		return {}
	return _baseline_snapshot(int(parts[3]), Vector2i(int(parts[1]), int(parts[2])))


func designate(definition_id: int, anchor: Vector2i) -> bool:
	var snapshot: Dictionary = get_snapshot(definition_id, anchor)
	if snapshot.is_empty() or not bool(snapshot["available"]) or bool(snapshot["designated"]):
		return false
	snapshot["designated"] = true
	_states[String(snapshot["resource_id"])] = snapshot
	resource_changed.emit(snapshot["resource_id"], anchor, definition_id, "designation")
	return true


func cancel_designation(definition_id: int, anchor: Vector2i) -> bool:
	var snapshot: Dictionary = get_snapshot(definition_id, anchor)
	if snapshot.is_empty() or not bool(snapshot["designated"]):
		return false
	snapshot["designated"] = false
	_store_if_changed(snapshot)
	resource_changed.emit(snapshot["resource_id"], anchor, definition_id, "designation")
	return true


func complete_designated_harvest(definition_id: int, anchor: Vector2i) -> Dictionary:
	## This is the single completion entry point used by debug interaction and
	## future workers. Invalid or repeated completion never credits inventory.
	var snapshot: Dictionary = get_snapshot(definition_id, anchor)
	if snapshot.is_empty() or not bool(snapshot["designated"]) or not bool(snapshot["available"]):
		return {"success": false, "category": "", "quantity": 0}
	var category: String = String(snapshot["category"])
	var quantity: int = maxi(0, int(snapshot["remaining_quantity"]))
	if quantity <= 0 or not _inventory.has(category):
		return {"success": false, "category": category, "quantity": 0}
	_inventory[category] = maxi(0, int(_inventory[category]) + quantity)
	snapshot["designated"] = false
	snapshot["available"] = false
	snapshot["remaining_quantity"] = 0
	var change_kind: String = "removed"
	if category == "food":
		snapshot["ripe"] = false
		snapshot["regrow_at"] = simulated_time + berry_regrowth_seconds
		_next_regrowth_time = minf(_next_regrowth_time, float(snapshot["regrow_at"]))
		change_kind = "berry_depleted"
	_states[String(snapshot["resource_id"])] = snapshot
	inventory_changed.emit(get_inventory())
	resource_changed.emit(snapshot["resource_id"], anchor, definition_id, change_kind)
	return {"success": true, "category": category, "quantity": quantity}


func advance_simulated_time(delta_seconds: float) -> int:
	if delta_seconds <= 0.0:
		return 0
	simulated_time += delta_seconds
	if simulated_time < _next_regrowth_time:
		return 0
	var regrown: int = 0
	var next_due: float = INF
	for resource_id in _states.keys():
		var snapshot: Dictionary = _states[resource_id]
		var regrow_at: float = float(snapshot.get("regrow_at", INF))
		if regrow_at <= simulated_time:
			var anchor: Vector2i = snapshot["anchor"]
			var definition_id: int = int(snapshot["definition_id"])
			_states.erase(resource_id)
			resource_changed.emit(resource_id, anchor, definition_id, "berry_regrown")
			regrown += 1
		elif regrow_at < next_due:
			next_due = regrow_at
	_next_regrowth_time = next_due
	return regrown


func reconcile_missing_designations(valid_resource_ids: Dictionary, chunk_coord: Vector2i, chunk_size: int) -> int:
	## Terrain edits cancel requests whose procedural anchors cease to exist,
	## while depletion/regrowth records remain so undo cannot resurrect them.
	var cancelled: int = 0
	for resource_id in _states.keys():
		var snapshot: Dictionary = _states[resource_id]
		if not bool(snapshot.get("designated", false)):
			continue
		var anchor: Vector2i = snapshot["anchor"]
		var owner := Vector2i(
			floori(float(anchor.x) / chunk_size),
			floori(float(anchor.y) / chunk_size))
		if owner != chunk_coord or valid_resource_ids.has(resource_id):
			continue
		snapshot["designated"] = false
		_store_if_changed(snapshot)
		resource_changed.emit(resource_id, anchor, int(snapshot["definition_id"]), "designation")
		cancelled += 1
	return cancelled


func get_inventory() -> Dictionary:
	return _inventory.duplicate()


func get_modified_state_count() -> int:
	return _states.size()


func get_memory_estimate_bytes() -> int:
	return var_to_bytes(_states).size() + var_to_bytes(_inventory).size()


func export_snapshot() -> Dictionary:
	var records: Array[Dictionary] = []
	for resource_id in _states.keys():
		var state: Dictionary = _states[resource_id]
		var anchor: Vector2i = state["anchor"]
		var record: Dictionary = {
			"resource_id": String(resource_id),
			"definition_id": int(state["definition_id"]),
			"x": anchor.x, "y": anchor.y,
			"category": String(state["category"]),
			"available": bool(state["available"]),
			"designated": bool(state["designated"]),
			"remaining_quantity": int(state["remaining_quantity"]),
			"ripe": bool(state.get("ripe", true)),
		}
		var regrow_at: float = float(state.get("regrow_at", INF))
		if is_finite(regrow_at):
			record["regrow_at"] = regrow_at
		records.append(record)
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["resource_id"]) < String(b["resource_id"]))
	return {
		"simulated_time": simulated_time,
		"berry_regrowth_seconds": berry_regrowth_seconds,
		"inventory": get_inventory(),
		"state_deviations": records,
	}


func validate_snapshot(snapshot: Variant) -> Dictionary:
	if not snapshot is Dictionary:
		return _validation_error("Resource state must be an object")
	var time_result: Dictionary = _finite_number(snapshot.get("simulated_time"), "simulated_time")
	if not bool(time_result["ok"]) or float(time_result.get("value", -1.0)) < 0.0:
		return _validation_error("simulated_time must be a finite non-negative number")
	var duration_result: Dictionary = _finite_number(
		snapshot.get("berry_regrowth_seconds"), "berry_regrowth_seconds")
	if not bool(duration_result["ok"]) or float(duration_result.get("value", 0.0)) <= 0.0:
		return _validation_error("berry_regrowth_seconds must be a positive finite number")
	var inventory_value: Variant = snapshot.get("inventory")
	if not inventory_value is Dictionary:
		return _validation_error("inventory must be an object")
	var normalized_inventory: Dictionary = {}
	for category in ["wood", "stone", "food"]:
		var quantity_result: Dictionary = _exact_integer(
			inventory_value.get(category), "inventory.%s" % category)
		if not bool(quantity_result["ok"]):
			return quantity_result
		var quantity: int = int(quantity_result["value"])
		if quantity < 0 or quantity > MAX_INVENTORY_QUANTITY:
			return _validation_error("Inventory %s is outside the supported range" % category)
		normalized_inventory[category] = quantity
	var records_value: Variant = snapshot.get("state_deviations")
	if not records_value is Array:
		return _validation_error("state_deviations must be an array")
	var normalized_states: Dictionary = {}
	var seen_anchor_definition: Dictionary = {}
	for record in records_value:
		var record_result: Dictionary = _validate_state_record(record)
		if not bool(record_result["ok"]):
			return record_result
		var state: Dictionary = record_result["state"]
		var resource_id: String = String(state["resource_id"])
		var anchor_key: String = "%d:%d:%d" % [
			state["anchor"].x, state["anchor"].y, state["definition_id"]]
		if normalized_states.has(resource_id) or seen_anchor_definition.has(anchor_key):
			return _validation_error("Duplicate or conflicting resource record %s" % resource_id)
		normalized_states[resource_id] = state
		seen_anchor_definition[anchor_key] = true
	return {
		"ok": true, "error": "",
		"simulated_time": float(time_result["value"]),
		"berry_regrowth_seconds": float(duration_result["value"]),
		"inventory": normalized_inventory,
		"states": normalized_states,
	}


func import_snapshot(snapshot: Variant) -> Dictionary:
	var validation: Dictionary = validate_snapshot(snapshot)
	if not bool(validation["ok"]):
		return validation
	var imported_time: float = float(validation["simulated_time"])
	var imported_states: Dictionary = validation["states"]
	var next_due: float = INF
	for resource_id in imported_states.keys():
		var state: Dictionary = imported_states[resource_id]
		var regrow_at: float = float(state.get("regrow_at", INF))
		if regrow_at <= imported_time:
			imported_states.erase(resource_id)
		elif regrow_at < next_due:
			next_due = regrow_at
	simulated_time = imported_time
	berry_regrowth_seconds = float(validation["berry_regrowth_seconds"])
	_inventory = validation["inventory"]
	_states = imported_states
	_next_regrowth_time = next_due
	return {"ok": true, "error": ""}


func get_remaining_regrowth_time(definition_id: int, anchor: Vector2i) -> float:
	var snapshot: Dictionary = get_snapshot(definition_id, anchor)
	return maxf(0.0, float(snapshot.get("regrow_at", simulated_time)) - simulated_time)


func _baseline_snapshot(definition_id: int, anchor: Vector2i) -> Dictionary:
	if not definitions_by_id.has(definition_id):
		return {}
	var definition: Dictionary = definitions_by_id[definition_id]
	if not definition.has("resource_category"):
		return {}
	return {
		"resource_id": make_resource_id(definition_id, anchor),
		"definition_id": definition_id,
		"anchor": anchor,
		"category": String(definition["resource_category"]),
		"available": true,
		"designated": false,
		"remaining_quantity": maxi(0, int(definition.get("future_yield", 0))),
		"ripe": true,
		"regrow_at": INF,
	}


func _store_if_changed(snapshot: Dictionary) -> void:
	var baseline: Dictionary = _baseline_snapshot(int(snapshot["definition_id"]), snapshot["anchor"])
	var resource_id: String = String(snapshot["resource_id"])
	if snapshot == baseline:
		_states.erase(resource_id)
	else:
		_states[resource_id] = snapshot


func _validate_state_record(record: Variant) -> Dictionary:
	if not record is Dictionary:
		return _validation_error("Resource deviation must be an object")
	for key in ["resource_id", "definition_id", "x", "y", "category", "available",
			"designated", "remaining_quantity", "ripe"]:
		if not record.has(key):
			return _validation_error("Resource deviation missing %s" % key)
	var definition_result: Dictionary = _exact_integer(record["definition_id"], "definition_id")
	var x_result: Dictionary = _exact_integer(record["x"], "resource x")
	var y_result: Dictionary = _exact_integer(record["y"], "resource y")
	var quantity_result: Dictionary = _exact_integer(record["remaining_quantity"], "remaining_quantity")
	for result in [definition_result, x_result, y_result, quantity_result]:
		if not bool(result["ok"]):
			return result
	var definition_id: int = int(definition_result["value"])
	if not definitions_by_id.has(definition_id):
		return _validation_error("Unknown resource definition ID %d" % definition_id)
	var definition: Dictionary = definitions_by_id[definition_id]
	if not definition.has("resource_category"):
		return _validation_error("Definition %d is not a resource" % definition_id)
	var anchor := Vector2i(int(x_result["value"]), int(y_result["value"]))
	if absi(anchor.x) > 100000000 or absi(anchor.y) > 100000000:
		return _validation_error("Resource coordinate exceeds supported range")
	var expected_id: String = make_resource_id(definition_id, anchor)
	if not record["resource_id"] is String or String(record["resource_id"]) != expected_id:
		return _validation_error("Resource ID does not match seed, anchor and definition")
	var category: String = String(record["category"])
	if category != String(definition["resource_category"]):
		return _validation_error("Resource category does not match definition")
	if not record["available"] is bool or not record["designated"] is bool or not record["ripe"] is bool:
		return _validation_error("Resource availability, designation and ripe fields must be booleans")
	var available: bool = bool(record["available"])
	var designated: bool = bool(record["designated"])
	var ripe: bool = bool(record["ripe"])
	var remaining: int = int(quantity_result["value"])
	var maximum_yield: int = maxi(0, int(definition.get("future_yield", 0)))
	if remaining < 0 or remaining > maximum_yield:
		return _validation_error("Resource remaining quantity is invalid")
	if designated and not available:
		return _validation_error("Unavailable resource cannot be designated")
	var state: Dictionary = {
		"resource_id": expected_id, "definition_id": definition_id,
		"anchor": anchor, "category": category,
		"available": available, "designated": designated,
		"remaining_quantity": remaining, "ripe": ripe, "regrow_at": INF,
	}
	if category == "food" and not available:
		if ripe or remaining != 0:
			return _validation_error("Depleted food resource has inconsistent state")
		var regrow_result: Dictionary = _finite_number(record.get("regrow_at"), "regrow_at")
		if not bool(regrow_result["ok"]) or float(regrow_result.get("value", -1.0)) < 0.0:
			return _validation_error("Depleted food resource requires a valid regrowth deadline")
		state["regrow_at"] = float(regrow_result["value"])
	elif category == "food" and (not ripe or remaining != maximum_yield):
		return _validation_error("Available food resource has inconsistent state")
	elif category != "food" and available and (not ripe or remaining != maximum_yield):
		return _validation_error("Available resource has inconsistent state")
	elif category != "food" and not available and (remaining != 0 or ripe == false):
		return _validation_error("Depleted resource has inconsistent state")
	return {"ok": true, "error": "", "state": state}


static func _exact_integer(value: Variant, label: String) -> Dictionary:
	if not value is int and not value is float:
		return _validation_error("%s must be an integer" % label)
	var integer: int = int(value)
	if float(integer) != float(value):
		return _validation_error("%s must be an integer" % label)
	return {"ok": true, "error": "", "value": integer}


static func _finite_number(value: Variant, label: String) -> Dictionary:
	if not value is int and not value is float:
		return _validation_error("%s must be numeric" % label)
	var number: float = float(value)
	if not is_finite(number):
		return _validation_error("%s must be finite" % label)
	return {"ok": true, "error": "", "value": number}


static func _validation_error(message: String) -> Dictionary:
	return {"ok": false, "error": message}

extends RefCounted
## Transient input/selection adapter. It requests authoritative resource actions
## from TerrainRenderer and never owns inventory, depletion or regrowth state.

signal selection_changed(snapshot: Dictionary)

var terrain
var resource_mode: bool = false
var selected: Dictionary = {}


func configure(terrain_renderer) -> void:
	terrain = terrain_renderer


func set_resource_mode(enabled: bool) -> void:
	resource_mode = enabled
	if not resource_mode:
		clear_selection()


func select_at(world_cell: Vector2i) -> bool:
	var snapshot: Dictionary = terrain.get_resource_at_cell(world_cell)
	if snapshot.is_empty():
		clear_selection()
		return false
	selected = snapshot
	terrain.set_selected_resource_id(String(selected["resource_id"]))
	selection_changed.emit(selected.duplicate(true))
	return true


func clear_selection() -> void:
	if selected.is_empty():
		return
	selected.clear()
	terrain.set_selected_resource_id("")
	selection_changed.emit({})


func designate_selected() -> bool:
	if selected.is_empty():
		return false
	var changed: bool = terrain.designate_resource(
		int(selected["definition_id"]), selected["anchor"])
	_refresh_selection()
	return changed


func cancel_selected_designation() -> bool:
	if selected.is_empty():
		return false
	var changed: bool = terrain.cancel_resource_designation(
		int(selected["definition_id"]), selected["anchor"])
	_refresh_selection()
	return changed


func debug_complete_selected() -> Dictionary:
	if selected.is_empty():
		return {"success": false, "category": "", "quantity": 0}
	var definition_id: int = int(selected["definition_id"])
	var anchor: Vector2i = selected["anchor"]
	var result: Dictionary = terrain.complete_designated_resource(definition_id, anchor)
	if bool(result.get("success", false)) and String(result["category"]) != "food":
		clear_selection()
	else:
		_refresh_selection()
	return result


func get_selected() -> Dictionary:
	return selected.duplicate(true)


func refresh_selected() -> void:
	_refresh_selection()


func _refresh_selection() -> void:
	if selected.is_empty():
		return
	var anchor: Vector2i = selected["anchor"]
	var refreshed: Dictionary = terrain.get_resource_at_cell(anchor)
	if refreshed.is_empty():
		clear_selection()
		return
	selected = refreshed
	selection_changed.emit(selected.duplicate(true))

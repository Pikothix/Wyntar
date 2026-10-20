extends Node2D
## Global batched presentation for large environmental objects. Anchors remain
## owned by chunks, while global elevation bands prevent canopy clipping and
## sort roots consistently across chunk boundaries.

const ObjectLayer = preload("res://scripts/environment_object_layer.gd")
const TILE_SIZE := Vector2i(32, 32)
const BASELINE_HEIGHT_STEP: int = 16
const MAX_ELEVATION: int = 3

var _definitions_by_id: Dictionary
var _atlas_texture: Texture2D
var _atlas_by_id: Dictionary
var _unripe_atlas_by_id: Dictionary
var _layers: Array[Node2D] = []
var _objects_by_chunk: Dictionary = {}
var _visible_enabled: bool = true
var _object_count: int = 0
var _category_counts: Dictionary = {}
var _occupied_ground_cells: Dictionary = {}
var last_submission_usec: int = 0
var _batches_dirty: bool = false
var _height_step: int = BASELINE_HEIGHT_STEP


func configure(
        definitions_by_id: Dictionary,
        atlas_texture: Texture2D,
        atlas_by_id: Dictionary,
        unripe_atlas_by_id: Dictionary = {}) -> void:
    _definitions_by_id = definitions_by_id
    _atlas_texture = atlas_texture
    _atlas_by_id = atlas_by_id
    _unripe_atlas_by_id = unripe_atlas_by_id
    for elevation in range(MAX_ELEVATION + 1):
        var layer = ObjectLayer.new()
        layer.name = "EnvironmentalObjectsHeight_%d" % elevation
        layer.z_index = elevation * 8 + 5
        layer.configure(_atlas_texture, _atlas_by_id, _unripe_atlas_by_id, _definitions_by_id)
        add_child(layer)
        _layers.append(layer)


func set_chunk_objects(
        chunk_coord: Vector2i,
        object_ids: PackedInt32Array,
        object_variants: PackedByteArray,
        object_anchor_x: PackedInt32Array,
        object_anchor_y: PackedInt32Array,
        object_heights: PackedByteArray,
        resource_ids: PackedStringArray = PackedStringArray(),
        resource_flags: PackedByteArray = PackedByteArray()) -> void:
    _objects_by_chunk[chunk_coord] = {
        "ids": object_ids,
        "variants": object_variants,
        "anchor_x": object_anchor_x,
        "anchor_y": object_anchor_y,
        "heights": object_heights,
        "resource_ids": resource_ids,
        "resource_flags": resource_flags,
    }
    _batches_dirty = true


func remove_chunk(chunk_coord: Vector2i) -> void:
    if not _objects_by_chunk.erase(chunk_coord):
        return
    _batches_dirty = true


func clear_chunks() -> void:
    if _objects_by_chunk.is_empty():
        return
    _objects_by_chunk.clear()
    _batches_dirty = true


func set_objects_visible(visible_value: bool) -> void:
    _visible_enabled = visible_value
    visible = visible_value


func set_atlas_texture(atlas_texture: Texture2D) -> void:
    _atlas_texture = atlas_texture
    for layer in _layers:
        layer.set_atlas_texture(atlas_texture)


func set_height_step(height_step: int) -> void:
    var value: int = maxi(1, height_step)
    if _height_step == value:
        return
    _height_step = value
    _batches_dirty = true


func get_visible_object_count() -> int:
    return _object_count if _visible_enabled else 0


func get_category_counts() -> Dictionary:
    if not _visible_enabled:
        return {}
    return _category_counts.duplicate()


func get_owned_chunk_count() -> int:
    return _objects_by_chunk.size()


func set_selected_resource_id(resource_id: String) -> void:
    for layer in _layers:
        layer.set_selected_resource_id(resource_id)


func update_resource_state(resource_id: String, designated: bool, ripe: bool) -> bool:
    var flags: int = (1 if designated else 0) | (2 if ripe else 0) | 4
    var found: bool = false
    for chunk_data in _objects_by_chunk.values():
        var resource_ids: PackedStringArray = chunk_data.get("resource_ids", PackedStringArray())
        var index: int = resource_ids.find(resource_id)
        if index < 0:
            continue
        var resource_flags: PackedByteArray = chunk_data["resource_flags"]
        resource_flags[index] = flags
        chunk_data["resource_flags"] = resource_flags
        found = true
        break
    if found:
        for layer in _layers:
            layer.update_resource_flags(resource_id, flags)
    return found


func get_resource_at_cell(world_cell: Vector2i) -> Dictionary:
    for chunk_data in _objects_by_chunk.values():
        var ids: PackedInt32Array = chunk_data["ids"]
        var resource_ids: PackedStringArray = chunk_data.get("resource_ids", PackedStringArray())
        for index in range(ids.size()):
            if index >= resource_ids.size() or resource_ids[index].is_empty():
                continue
            var definition: Dictionary = _definitions_by_id[int(ids[index])]
            var anchor := Vector2i(chunk_data["anchor_x"][index], chunk_data["anchor_y"][index])
            var matches: bool = anchor == world_cell
            if not matches:
                for offset in definition["footprint"]:
                    if anchor + Vector2i(offset) == world_cell:
                        matches = true
                        break
            if matches:
                return {
                    "resource_id": resource_ids[index], "definition_id": int(ids[index]),
                    "anchor": anchor, "height": int(chunk_data["heights"][index]),
                }
    return {}


func get_loaded_resource_entries() -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for chunk_data in _objects_by_chunk.values():
        var ids: PackedInt32Array = chunk_data["ids"]
        var resource_ids: PackedStringArray = chunk_data.get("resource_ids", PackedStringArray())
        for index in range(ids.size()):
            if index >= resource_ids.size() or resource_ids[index].is_empty():
                continue
            result.append({
                "resource_id": resource_ids[index], "definition_id": int(ids[index]),
                "anchor": Vector2i(chunk_data["anchor_x"][index], chunk_data["anchor_y"][index]),
                "height": int(chunk_data["heights"][index]),
            })
    return result


func flush_pending() -> int:
    if not _batches_dirty:
        last_submission_usec = 0
        return 0
    var submission_start: int = Time.get_ticks_usec()
    _rebuild_batches()
    last_submission_usec = Time.get_ticks_usec() - submission_start
    _batches_dirty = false
    return last_submission_usec


func is_ground_cell_occupied(world_pos: Vector2i) -> bool:
    return _occupied_ground_cells.has(world_pos)


func get_occupied_ground_cells() -> Dictionary:
    return _occupied_ground_cells.duplicate()


func _rebuild_batches() -> void:
    var items_by_elevation: Array = [[], [], [], []]
    _category_counts.clear()
    _occupied_ground_cells.clear()
    _object_count = 0
    for chunk_data in _objects_by_chunk.values():
        var ids: PackedInt32Array = chunk_data["ids"]
        var variants: PackedByteArray = chunk_data["variants"]
        var anchor_x: PackedInt32Array = chunk_data["anchor_x"]
        var anchor_y: PackedInt32Array = chunk_data["anchor_y"]
        var heights: PackedByteArray = chunk_data["heights"]
        var resource_ids: PackedStringArray = chunk_data.get("resource_ids", PackedStringArray())
        var resource_flags: PackedByteArray = chunk_data.get("resource_flags", PackedByteArray())
        for index in range(ids.size()):
            var object_id: int = ids[index]
            var definition: Dictionary = _definitions_by_id[object_id]
            var elevation: int = clampi(int(heights[index]), 0, MAX_ELEVATION)
            var anchor := Vector2i(anchor_x[index], anchor_y[index])
            for footprint_offset in definition["footprint"]:
                _occupied_ground_cells[anchor + Vector2i(footprint_offset)] = true
            var root_position := Vector2(
                anchor.x * TILE_SIZE.x + TILE_SIZE.x * 0.5,
                (anchor.y + 1) * TILE_SIZE.y - elevation * _height_step)
            items_by_elevation[elevation].append({
                "id": object_id,
                "variant": int(variants[index]),
                "anchor": anchor,
                "root_position": root_position,
                "sort_y": root_position.y + float(definition.get("render_sort_bias", 0)),
                "resource_id": resource_ids[index] if index < resource_ids.size() else "",
                "resource_flags": int(resource_flags[index]) if index < resource_flags.size() else 2,
            })
            var category: String = String(definition["category"])
            _category_counts[category] = int(_category_counts.get(category, 0)) + 1
            _object_count += 1
    for elevation in range(_layers.size()):
        items_by_elevation[elevation].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
            if not is_equal_approx(float(a["sort_y"]), float(b["sort_y"])):
                return float(a["sort_y"]) < float(b["sort_y"])
            var a_anchor: Vector2i = a["anchor"]
            var b_anchor: Vector2i = b["anchor"]
            if a_anchor.x != b_anchor.x:
                return a_anchor.x < b_anchor.x
            return int(a["id"]) < int(b["id"])
        )
        _layers[elevation].set_draw_items(items_by_elevation[elevation])

extends RefCounted
## Authoritative material and ground-elevation lookup. Procedural data is
## regenerated on demand; separate sparse dictionaries own mutable player
## edits. Liquid surface height is a derived presentation query so painting
## water never destroys the authoritative ground-height value beneath it.

const Catalog = preload("res://scripts/terrain_catalog.gd")

const MIN_ELEVATION: int = 0
const MAX_ELEVATION: int = 3
const MAX_SERIALIZED_COORDINATE: int = 100000000

var generator # TerrainGenerator instance; intentionally dynamically typed.
var overrides: Dictionary = {} # Vector2i -> terrain id (int)
var height_overrides: Dictionary = {} # Vector2i -> elevation (int)


func configure(terrain_generator) -> void:
    generator = terrain_generator


func get_cell(world_pos: Vector2i) -> int:
    if overrides.has(world_pos):
        return int(overrides[world_pos])
    return generator.get_cell(world_pos)


func set_override(world_pos: Vector2i, terrain_id: int) -> bool:
    var previous_id: int = get_cell(world_pos)
    var generated_id: int = generator.get_cell(world_pos)
    if terrain_id == generated_id:
        overrides.erase(world_pos)
    else:
        overrides[world_pos] = terrain_id
    return previous_id != terrain_id


func get_material_override_state(world_pos: Vector2i) -> Dictionary:
    return {
        "has_override": overrides.has(world_pos),
        "value": int(overrides.get(world_pos, generator.get_cell(world_pos))),
    }


func apply_material_override_state(world_pos: Vector2i, state: Dictionary) -> bool:
    var previous: Dictionary = get_material_override_state(world_pos)
    if bool(state.get("has_override", false)):
        overrides[world_pos] = int(state["value"])
    else:
        overrides.erase(world_pos)
    return previous != get_material_override_state(world_pos)


func get_elevation(world_pos: Vector2i) -> int:
    if height_overrides.has(world_pos):
        return int(height_overrides[world_pos])
    return int(generator.get_elevation(world_pos))


func get_surface_elevation(world_pos: Vector2i, sea_level: int = 0) -> int:
    if is_liquid_visible(world_pos, sea_level):
        return clampi(sea_level, MIN_ELEVATION, MAX_ELEVATION)
    return get_elevation(world_pos)


func is_liquid_visible(world_pos: Vector2i, sea_level: int = 0) -> bool:
    return (
        Catalog.is_liquid(get_cell(world_pos))
        and (not height_overrides.has(world_pos)
            or get_elevation(world_pos) <= clampi(sea_level, MIN_ELEVATION, MAX_ELEVATION)))


func get_visible_material(world_pos: Vector2i, sea_level: int = 0) -> int:
    ## Presentation-only material query. Authoritative material and elevation
    ## remain independently editable and retain their existing save schema.
    var terrain_id: int = get_cell(world_pos)
    if not Catalog.is_liquid(terrain_id) or is_liquid_visible(world_pos, sea_level):
        return terrain_id
    for material in Catalog.MATERIALS:
        if int(material["id"]) == terrain_id:
            return int(material.get("exposed_ground_material_id", Catalog.DEFAULT_MATERIAL_ID))
    return Catalog.DEFAULT_MATERIAL_ID


func get_visible_liquid_elevation(world_pos: Vector2i, sea_level: int = 0) -> int:
    return clampi(sea_level, MIN_ELEVATION, MAX_ELEVATION) if is_liquid_visible(
        world_pos, sea_level) else -1


func set_elevation_override(world_pos: Vector2i, elevation: int) -> bool:
    var clamped_elevation: int = clampi(elevation, MIN_ELEVATION, MAX_ELEVATION)
    var previous_elevation: int = get_elevation(world_pos)
    var generated_elevation: int = int(generator.get_elevation(world_pos))
    if clamped_elevation == generated_elevation:
        height_overrides.erase(world_pos)
    else:
        height_overrides[world_pos] = clamped_elevation
    return previous_elevation != clamped_elevation


func get_elevation_override_state(world_pos: Vector2i) -> Dictionary:
    return {
        "has_override": height_overrides.has(world_pos),
        "value": int(height_overrides.get(world_pos, generator.get_elevation(world_pos))),
    }


func apply_elevation_override_state(world_pos: Vector2i, state: Dictionary) -> bool:
    var previous: Dictionary = get_elevation_override_state(world_pos)
    if bool(state.get("has_override", false)):
        height_overrides[world_pos] = clampi(
            int(state["value"]), MIN_ELEVATION, MAX_ELEVATION)
    else:
        height_overrides.erase(world_pos)
    return previous != get_elevation_override_state(world_pos)


func get_all_override_cells() -> Array[Vector2i]:
    var cells: Dictionary = {}
    for world_pos in overrides:
        cells[world_pos] = true
    for world_pos in height_overrides:
        cells[world_pos] = true
    var result: Array[Vector2i] = []
    result.assign(cells.keys())
    return result


func clear_elevation_override(world_pos: Vector2i) -> bool:
    if not height_overrides.has(world_pos):
        return false
    height_overrides.erase(world_pos)
    return true


func clear_overrides() -> bool:
    if overrides.is_empty() and height_overrides.is_empty():
        return false
    overrides.clear()
    height_overrides.clear()
    return true


func get_override_count() -> int:
    return overrides.size()


func get_height_override_count() -> int:
    return height_overrides.size()


func export_override_snapshot() -> Dictionary:
    var material_records: Array[Dictionary] = []
    for cell in overrides:
        material_records.append({
            "x": cell.x, "y": cell.y, "material_id": int(overrides[cell]),
        })
    var elevation_records: Array[Dictionary] = []
    for cell in height_overrides:
        elevation_records.append({
            "x": cell.x, "y": cell.y, "elevation": int(height_overrides[cell]),
        })
    material_records.sort_custom(_coordinate_record_precedes)
    elevation_records.sort_custom(_coordinate_record_precedes)
    return {
        "material_overrides": material_records,
        "elevation_overrides": elevation_records,
    }


func validate_override_snapshot(snapshot: Variant) -> Dictionary:
    if not snapshot is Dictionary:
        return _validation_error("Terrain state must be an object")
    if not snapshot.has("material_overrides") or not snapshot["material_overrides"] is Array:
        return _validation_error("material_overrides must be an array")
    if not snapshot.has("elevation_overrides") or not snapshot["elevation_overrides"] is Array:
        return _validation_error("elevation_overrides must be an array")
    var valid_materials: Dictionary = {}
    for material in Catalog.MATERIALS:
        valid_materials[int(material["id"])] = true
    var normalized_materials: Dictionary = {}
    for record in snapshot["material_overrides"]:
        var result: Dictionary = _validate_coordinate_record(record, "material override")
        if not bool(result["ok"]):
            return result
        var material_id: int = int(record.get("material_id", -1))
        if not valid_materials.has(material_id):
            return _validation_error("Invalid material ID %d" % material_id)
        var cell: Vector2i = result["cell"]
        if normalized_materials.has(cell):
            return _validation_error("Duplicate material override at %s" % cell)
        normalized_materials[cell] = material_id
    var normalized_elevations: Dictionary = {}
    for record in snapshot["elevation_overrides"]:
        var result: Dictionary = _validate_coordinate_record(record, "elevation override")
        if not bool(result["ok"]):
            return result
        var elevation: int = int(record.get("elevation", -1))
        if elevation < MIN_ELEVATION or elevation > MAX_ELEVATION:
            return _validation_error("Invalid elevation %d" % elevation)
        var cell: Vector2i = result["cell"]
        if normalized_elevations.has(cell):
            return _validation_error("Duplicate elevation override at %s" % cell)
        normalized_elevations[cell] = elevation
    return {
        "ok": true, "error": "",
        "material_overrides": normalized_materials,
        "elevation_overrides": normalized_elevations,
    }


func import_override_snapshot(snapshot: Variant) -> Dictionary:
    var validation: Dictionary = validate_override_snapshot(snapshot)
    if not bool(validation["ok"]):
        return validation
    overrides = validation["material_overrides"]
    height_overrides = validation["elevation_overrides"]
    return {"ok": true, "error": ""}


static func _coordinate_record_precedes(a: Dictionary, b: Dictionary) -> bool:
    return int(a["y"]) < int(b["y"]) or (
        int(a["y"]) == int(b["y"]) and int(a["x"]) < int(b["x"]))


static func _validate_coordinate_record(record: Variant, label: String) -> Dictionary:
    if not record is Dictionary or not record.has("x") or not record.has("y"):
        return _validation_error("Malformed %s coordinate" % label)
    if not record["x"] is float and not record["x"] is int:
        return _validation_error("Non-numeric %s x coordinate" % label)
    if not record["y"] is float and not record["y"] is int:
        return _validation_error("Non-numeric %s y coordinate" % label)
    var x: int = int(record["x"])
    var y: int = int(record["y"])
    if float(x) != float(record["x"]) or float(y) != float(record["y"]):
        return _validation_error("Fractional %s coordinate" % label)
    if absi(x) > MAX_SERIALIZED_COORDINATE or absi(y) > MAX_SERIALIZED_COORDINATE:
        return _validation_error("%s coordinate exceeds supported range" % label.capitalize())
    return {"ok": true, "error": "", "cell": Vector2i(x, y)}


static func _validation_error(message: String) -> Dictionary:
    return {"ok": false, "error": message}

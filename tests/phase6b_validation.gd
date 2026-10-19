extends SceneTree
## Deterministic Phase 6B placement and chunk-ownership validation. Large
## objects remain derived presentation data; TerrainWorld is never mutated.

const TerrainCatalog = preload("res://scripts/terrain_catalog.gd")
const DecorationCatalog = preload("res://scripts/decoration_catalog.gd")
const EnvironmentObjectCatalog = preload("res://scripts/environment_object_catalog.gd")
const EnvironmentObjectPlacement = preload("res://scripts/environment_object_placement.gd")
const TerrainChunkBuildJob = preload("res://scripts/terrain_chunk_build_job.gd")

var _failures: Array[String] = []
var _priorities: Dictionary = {}
var _liquids: Dictionary = {}
var _definitions_by_id: Dictionary = {}
var _decoration_context: Dictionary
var _environment_context: Dictionary
var _material_overrides: Dictionary = {}


func _initialize() -> void:
    for material in TerrainCatalog.MATERIALS:
        var terrain_id: int = int(material["id"])
        _priorities[terrain_id] = int(material["priority"])
        _liquids[terrain_id] = bool(material.get("liquid", false))
    _definitions_by_id = EnvironmentObjectCatalog.build_by_id()
    _decoration_context = {
        "definitions": DecorationCatalog.DEFINITIONS,
        "indices_by_material": DecorationCatalog.build_indices_by_material(),
        "max_density_by_material": DecorationCatalog.build_max_density_by_material(),
        "seed": 84521 + 63017,
        "density": 1.0,
        "clustering": 0.72,
        "generation_enabled": true,
    }
    _environment_context = {
        "definitions": EnvironmentObjectCatalog.DEFINITIONS,
        "definitions_by_id": _definitions_by_id,
        "indices_by_material": EnvironmentObjectCatalog.build_indices_by_material(),
        "max_density_by_material": EnvironmentObjectCatalog.build_max_density_by_material(),
        "liquid_by_id": _liquids,
        "seed": 84521 + 91423,
        "density": 2.0,
        "generation_enabled": true,
    }

    _test_registry()
    _test_deterministic_selection()
    _test_material_edit_reactivity()
    _test_chunk_reload_ownership_and_seams()
    _test_environment_rules_and_decoration_exclusion()

    if _failures.is_empty():
        print("PHASE6B_VALIDATION PASS")
        quit(0)
        return
    for failure in _failures:
        push_error(failure)
    print("PHASE6B_VALIDATION FAIL count=%d" % _failures.size())
    quit(1)


func _test_registry() -> void:
    var ids: Dictionary = {}
    var categories: Dictionary = {}
    for definition in EnvironmentObjectCatalog.DEFINITIONS:
        var object_id: int = int(definition["id"])
        _check(not ids.has(object_id), "Environmental object IDs must be unique")
        ids[object_id] = true
        categories[String(definition["category"])] = true
        for required_key in [
                "name", "kind", "materials", "density", "variants",
                "visual_size", "root_anchor", "footprint", "exclusion_radius",
                "render_sort_bias", "future_collision_footprint"]:
            _check(definition.has(required_key),
                "Object %d missing registry key %s" % [object_id, required_key])
    for category in ["trees", "bushes", "rocks", "debris"]:
        _check(categories.has(category), "Missing environmental category %s" % category)


func _test_deterministic_selection() -> void:
    for pos in [Vector2i(4, 9), Vector2i(-41, 17), Vector2i(-1, -1), Vector2i(32, 31)]:
        var first: Vector2i = _choose(pos)
        var second: Vector2i = _choose(pos)
        _check(first == second, "Environmental selection must be stable at %s" % pos)
    var water_pos := Vector2i(-34, -17)
    _check(_fixture_material(water_pos) == 0, "Water fixture must be liquid")
    _check(_choose(water_pos) == EnvironmentObjectPlacement.EMPTY,
        "Open water must never contain an environmental object")


func _test_material_edit_reactivity() -> void:
    var anchor := Vector2i.ZERO
    var original := EnvironmentObjectPlacement.EMPTY
    var found: bool = false
    for y in range(-64, 65):
        for x in range(-64, 65):
            anchor = Vector2i(x, y)
            original = EnvironmentObjectPlacement.choose(
                anchor, _environment_context,
                _fixture_material_with_override,
                _fixture_ground_height, _fixture_surface_height_with_override)
            if original.x >= 0:
                found = true
                break
        if found:
            break
    _check(found, "Edit-reactivity fixture should contain an environmental object")
    if not found:
        return
    _material_overrides[anchor] = 0
    var after_water_paint: Vector2i = EnvironmentObjectPlacement.choose(
        anchor, _environment_context,
        _fixture_material_with_override,
        _fixture_ground_height, _fixture_surface_height_with_override)
    _check(after_water_paint == EnvironmentObjectPlacement.EMPTY,
        "Painting an object anchor to water must remove its placement")
    _material_overrides.erase(anchor)
    var after_restore: Vector2i = EnvironmentObjectPlacement.choose(
        anchor, _environment_context,
        _fixture_material_with_override,
        _fixture_ground_height, _fixture_surface_height_with_override)
    _check(after_restore == original,
        "Restoring terrain must restore the deterministic object selection")


func _test_chunk_reload_ownership_and_seams() -> void:
    var anchors: Dictionary = {}
    for chunk_coord in [Vector2i(-1, 0), Vector2i.ZERO, Vector2i(0, -1)]:
        var first = _build_job(chunk_coord)
        var second = _build_job(chunk_coord)
        _check(first.environment_object_ids == second.environment_object_ids,
            "Reloaded object IDs must match for %s" % chunk_coord)
        _check(first.environment_object_variants == second.environment_object_variants,
            "Reloaded variants must match for %s" % chunk_coord)
        _check(first.environment_object_anchor_x == second.environment_object_anchor_x,
            "Reloaded anchor X values must match for %s" % chunk_coord)
        _check(first.environment_object_anchor_y == second.environment_object_anchor_y,
            "Reloaded anchor Y values must match for %s" % chunk_coord)
        for index in range(first.environment_object_ids.size()):
            var anchor := Vector2i(
                first.environment_object_anchor_x[index],
                first.environment_object_anchor_y[index])
            _check(_world_to_chunk(anchor) == chunk_coord,
                "Anchor %s must be owned by chunk %s" % [anchor, chunk_coord])
            _check(not anchors.has(anchor), "Duplicate cross-chunk anchor %s" % anchor)
            anchors[anchor] = true
    _check(not anchors.is_empty(), "Validation chunks should contain environmental objects")


func _test_environment_rules_and_decoration_exclusion() -> void:
    for chunk_coord in [Vector2i(-1, 0), Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1)]:
        var job = _build_job(chunk_coord)
        for index in range(job.environment_object_ids.size()):
            var object_id: int = job.environment_object_ids[index]
            var definition: Dictionary = _definitions_by_id[object_id]
            var anchor := Vector2i(
                job.environment_object_anchor_x[index],
                job.environment_object_anchor_y[index])
            var height: int = job.environment_object_heights[index]
            _check(_fixture_material(anchor) != 0, "Object rooted in water at %s" % anchor)
            _check(_fixture_material(anchor) in definition["materials"],
                "Object %d has invalid root material at %s" % [object_id, anchor])
            _check(height == _fixture_surface_height(anchor),
                "Object root height must match liquid-aware surface at %s" % anchor)
            for footprint_offset in definition["footprint"]:
                var footprint_pos: Vector2i = anchor + Vector2i(footprint_offset)
                _check(_fixture_material(footprint_pos) != 0,
                    "Object footprint intersects water at %s" % footprint_pos)
                _check(_fixture_surface_height(footprint_pos) == height,
                    "Object footprint floats across elevation at %s" % footprint_pos)
                if _world_to_chunk(footprint_pos) == chunk_coord:
                    var local: Vector2i = footprint_pos - chunk_coord * TerrainChunkBuildJob.CHUNK_SIZE
                    var cell_index: int = local.y * TerrainChunkBuildJob.CHUNK_SIZE + local.x
                    _check(job.decoration_ids[cell_index] < 0,
                        "Ground decoration protrudes through object footprint at %s" % footprint_pos)


func _build_job(chunk_coord: Vector2i):
    var job = TerrainChunkBuildJob.new(chunk_coord)
    while not job.is_data_ready():
        job.process_data_quantum(
            _fixture_material, _fixture_surface_height, _fixture_ground_height,
            _priorities, _liquids, _decoration_context,
            _environment_context, 4096)
    return job


func _choose(pos: Vector2i) -> Vector2i:
    return EnvironmentObjectPlacement.choose(
        pos, _environment_context,
        _fixture_material, _fixture_ground_height, _fixture_surface_height)


func _fixture_material(pos: Vector2i) -> int:
    if posmod(pos.x + 34, 37) < 5:
        return 0
    return 1 + posmod(floori(float(pos.x) / 11.0) + floori(float(pos.y) / 13.0), 7)


func _fixture_ground_height(pos: Vector2i) -> int:
    return posmod(floori(float(pos.x) / 19.0) + floori(float(pos.y) / 23.0), 4)


func _fixture_surface_height(pos: Vector2i) -> int:
    return 0 if _fixture_material(pos) == 0 else _fixture_ground_height(pos)


func _fixture_material_with_override(pos: Vector2i) -> int:
    return int(_material_overrides.get(pos, _fixture_material(pos)))


func _fixture_surface_height_with_override(pos: Vector2i) -> int:
    return 0 if _fixture_material_with_override(pos) == 0 else _fixture_ground_height(pos)


func _world_to_chunk(world_pos: Vector2i) -> Vector2i:
    return Vector2i(
        floori(float(world_pos.x) / TerrainChunkBuildJob.CHUNK_SIZE),
        floori(float(world_pos.y) / TerrainChunkBuildJob.CHUNK_SIZE))


func _check(condition: bool, message: String) -> void:
    if not condition:
        _failures.append(message)

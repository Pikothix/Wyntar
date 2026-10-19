extends SceneTree
## Deterministic Phase 6A placement checks. These tests validate derived
## presentation data only; TerrainWorld remains unmodified.

const TerrainCatalog = preload("res://scripts/terrain_catalog.gd")
const DecorationCatalog = preload("res://scripts/decoration_catalog.gd")
const DecorationPlacement = preload("res://scripts/decoration_placement.gd")
const TerrainChunkBuildJob = preload("res://scripts/terrain_chunk_build_job.gd")

var _failures: Array[String] = []
var _priorities: Dictionary = {}
var _liquids: Dictionary = {}
var _definition_by_id: Dictionary = {}
var _context: Dictionary = {}


func _initialize() -> void:
    for material in TerrainCatalog.MATERIALS:
        var terrain_id: int = int(material["id"])
        _priorities[terrain_id] = int(material["priority"])
        _liquids[terrain_id] = bool(material.get("liquid", false))
    for definition in DecorationCatalog.DEFINITIONS:
        var decoration_id: int = int(definition["id"])
        _check(not _definition_by_id.has(decoration_id), "Decoration IDs must be unique")
        _definition_by_id[decoration_id] = definition
    _context = {
        "definitions": DecorationCatalog.DEFINITIONS,
        "indices_by_material": DecorationCatalog.build_indices_by_material(),
        "max_density_by_material": DecorationCatalog.build_max_density_by_material(),
        "seed": 84521 + 63017,
        "density": 2.0,
        "clustering": 0.72,
    }

    _test_registry_coverage()
    _test_deterministic_selection()
    _test_cluster_cache_equivalence()
    _test_chunk_reload_and_negative_coordinates()
    _test_material_height_and_water_rules()
    _test_paint_reactivity()

    if _failures.is_empty():
        print("PHASE6A_VALIDATION PASS")
        quit(0)
        return
    for failure in _failures:
        push_error(failure)
    print("PHASE6A_VALIDATION FAIL count=%d" % _failures.size())
    quit(1)


func _test_registry_coverage() -> void:
    var covered_materials: Dictionary = {}
    for definition in DecorationCatalog.DEFINITIONS:
        for terrain_id in definition["materials"]:
            covered_materials[int(terrain_id)] = true
    for terrain_id in range(1, 8):
        _check(covered_materials.has(terrain_id),
            "Every non-water material needs a decoration definition: %d" % terrain_id)
    _check(not covered_materials.has(0), "Open water must have no ordinary decoration definition")


func _test_deterministic_selection() -> void:
    for pos in [Vector2i(4, 9), Vector2i(-41, 17), Vector2i(-1, -1), Vector2i(32, 31)]:
        var first: Vector2i = _choose_fixture(pos)
        var second: Vector2i = _choose_fixture(pos)
        _check(first == second, "Selection must be stable at %s" % pos)
    var water_selection: Vector2i = _choose(
        Vector2i(-7, -13), 0, 3, 0,
        0, 1, 0, 1, 0, 0, 0, 0)
    _check(water_selection == DecorationPlacement.EMPTY,
        "Water must never receive ordinary ground decoration")


func _test_cluster_cache_equivalence() -> void:
    for chunk_coord in [Vector2i.ZERO, Vector2i(-2, -1), Vector2i(3, 2)]:
        var origin: Vector2i = chunk_coord * TerrainChunkBuildJob.CHUNK_SIZE
        var cache: Dictionary = DecorationPlacement.build_cluster_cache(
            origin, TerrainChunkBuildJob.CHUNK_SIZE, int(_context["seed"]))
        for local_pos in [Vector2i.ZERO, Vector2i(8, 8), Vector2i(17, 23), Vector2i(31, 31)]:
            var pos: Vector2i = origin + local_pos
            var direct: Vector2i = _choose_fixture(pos)
            var cached: Vector2i = DecorationPlacement.choose(
                pos, _fixture_material(pos), _fixture_ground_height(pos),
                _fixture_surface_height(pos),
                _fixture_material(pos + Vector2i.UP),
                _fixture_material(pos + Vector2i.RIGHT),
                _fixture_material(pos + Vector2i.DOWN),
                _fixture_material(pos + Vector2i.LEFT),
                _fixture_surface_height(pos + Vector2i.UP),
                _fixture_surface_height(pos + Vector2i.RIGHT),
                _fixture_surface_height(pos + Vector2i.DOWN),
                _fixture_surface_height(pos + Vector2i.LEFT),
                _context["definitions"], _context["indices_by_material"],
                _context["max_density_by_material"], _liquids,
                int(_context["seed"]), float(_context["density"]),
                float(_context["clustering"]), false,
                DecorationPlacement.cluster_value_from_cache(pos, cache))
            _check(cached == direct,
                "Cached cluster samples must preserve selection at %s" % pos)


func _test_chunk_reload_and_negative_coordinates() -> void:
    for chunk_coord in [Vector2i.ZERO, Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(0, -1)]:
        var first = _build_job(chunk_coord)
        var second = _build_job(chunk_coord)
        _check(first.decoration_ids == second.decoration_ids,
            "Reloaded decoration IDs must match for chunk %s" % chunk_coord)
        _check(first.decoration_variants == second.decoration_variants,
            "Reloaded decoration variants must match for chunk %s" % chunk_coord)
        _check(first.decoration_heights == second.decoration_heights,
            "Reloaded decoration heights must match for chunk %s" % chunk_coord)

    var anchors: Dictionary = {}
    for chunk_coord in [Vector2i(-1, 0), Vector2i.ZERO]:
        var job = _build_job(chunk_coord)
        for cell_index in range(TerrainChunkBuildJob.CELL_COUNT):
            if int(job.decoration_ids[cell_index]) < 0:
                continue
            var local := Vector2i(
                cell_index % TerrainChunkBuildJob.CHUNK_SIZE,
                floori(float(cell_index) / TerrainChunkBuildJob.CHUNK_SIZE))
            var world_pos: Vector2i = chunk_coord * TerrainChunkBuildJob.CHUNK_SIZE + local
            _check(not anchors.has(world_pos), "Decoration anchor duplicated across seam: %s" % world_pos)
            anchors[world_pos] = true
    _check(not anchors.is_empty(), "Negative and seam chunks should produce decoration anchors")


func _test_material_height_and_water_rules() -> void:
    var seen_materials: Dictionary = {}
    for chunk_x in range(-2, 3):
        var chunk_coord := Vector2i(chunk_x, 1)
        var job = _build_job(chunk_coord)
        for cell_index in range(TerrainChunkBuildJob.CELL_COUNT):
            var decoration_id: int = int(job.decoration_ids[cell_index])
            if decoration_id < 0:
                continue
            var x: int = cell_index % TerrainChunkBuildJob.CHUNK_SIZE
            var y: int = floori(float(cell_index) / TerrainChunkBuildJob.CHUNK_SIZE)
            var world_pos: Vector2i = chunk_coord * TerrainChunkBuildJob.CHUNK_SIZE + Vector2i(x, y)
            var terrain_id: int = _fixture_material(world_pos)
            var definition: Dictionary = _definition_by_id[decoration_id]
            seen_materials[terrain_id] = true
            _check(terrain_id != 0, "Open water decoration at %s" % world_pos)
            _check(terrain_id in definition["materials"],
                "Decoration %d is invalid for material %d" % [decoration_id, terrain_id])
            _check(int(job.decoration_heights[cell_index]) == _fixture_surface_height(world_pos),
                "Decoration must follow visible surface height at %s" % world_pos)
            var ground_height: int = _fixture_ground_height(world_pos)
            _check(ground_height >= int(definition.get("min_elevation", 0)),
                "Decoration below allowed elevation at %s" % world_pos)
            _check(ground_height <= int(definition.get("max_elevation", 3)),
                "Decoration above allowed elevation at %s" % world_pos)
    for terrain_id in range(1, 8):
        _check(seen_materials.has(terrain_id),
            "Validation fixture should place at least one decoration on material %d" % terrain_id)


func _test_paint_reactivity() -> void:
    var decorated_pos: Variant = null
    var original_selection := DecorationPlacement.EMPTY
    for y in range(-64, 65):
        for x in range(-64, 65):
            var pos := Vector2i(x, y)
            if _fixture_material(pos) != 3:
                continue
            var selection: Vector2i = _choose_fixture(pos)
            if selection != DecorationPlacement.EMPTY:
                decorated_pos = pos
                original_selection = selection
                break
        if decorated_pos != null:
            break
    _check(decorated_pos != null, "Paint reactivity needs a deterministic grass anchor")
    if decorated_pos == null:
        return
    var pos: Vector2i = decorated_pos
    var water_selection: Vector2i = _choose(
        pos, 0, _fixture_ground_height(pos), 0,
        _fixture_material(pos + Vector2i.UP),
        _fixture_material(pos + Vector2i.RIGHT),
        _fixture_material(pos + Vector2i.DOWN),
        _fixture_material(pos + Vector2i.LEFT),
        _fixture_surface_height(pos + Vector2i.UP),
        _fixture_surface_height(pos + Vector2i.RIGHT),
        _fixture_surface_height(pos + Vector2i.DOWN),
        _fixture_surface_height(pos + Vector2i.LEFT))
    _check(water_selection == DecorationPlacement.EMPTY,
        "Painting an anchor to water must remove its decoration")
    _check(_choose_fixture(pos) == original_selection,
        "Restoring the material must restore the deterministic decoration")


func _build_job(chunk_coord: Vector2i):
    var job = TerrainChunkBuildJob.new(chunk_coord)
    while not job.is_data_ready():
        job.process_data_quantum(
            _fixture_material, _fixture_surface_height, _fixture_ground_height,
            _priorities, _liquids, _context,
            {"generation_enabled": false}, 4096)
    return job


func _choose_fixture(pos: Vector2i) -> Vector2i:
    return _choose(
        pos, _fixture_material(pos), _fixture_ground_height(pos),
        _fixture_surface_height(pos),
        _fixture_material(pos + Vector2i.UP),
        _fixture_material(pos + Vector2i.RIGHT),
        _fixture_material(pos + Vector2i.DOWN),
        _fixture_material(pos + Vector2i.LEFT),
        _fixture_surface_height(pos + Vector2i.UP),
        _fixture_surface_height(pos + Vector2i.RIGHT),
        _fixture_surface_height(pos + Vector2i.DOWN),
        _fixture_surface_height(pos + Vector2i.LEFT))


func _choose(
        pos: Vector2i, terrain_id: int, ground_height: int, surface_height: int,
        north_id: int, east_id: int, south_id: int, west_id: int,
        north_height: int, east_height: int, south_height: int, west_height: int) -> Vector2i:
    return DecorationPlacement.choose(
        pos, terrain_id, ground_height, surface_height,
        north_id, east_id, south_id, west_id,
        north_height, east_height, south_height, west_height,
        _context["definitions"], _context["indices_by_material"],
        _context["max_density_by_material"], _liquids,
        int(_context["seed"]), float(_context["density"]), float(_context["clustering"]))


func _fixture_material(pos: Vector2i) -> int:
    if pos.y < 0 and posmod(pos.x, 11) < 2:
        return 0
    return 1 + posmod(pos.x + floori(float(pos.y) / 7.0), 7)


func _fixture_ground_height(pos: Vector2i) -> int:
    return posmod(floori(float(pos.x) / 13.0) + floori(float(pos.y) / 17.0), 4)


func _fixture_surface_height(pos: Vector2i) -> int:
    if _fixture_material(pos) == 0:
        return 0
    return _fixture_ground_height(pos)


func _check(condition: bool, message: String) -> void:
    if not condition:
        _failures.append(message)

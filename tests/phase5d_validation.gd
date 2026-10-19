extends SceneTree
## Focused Phase 5D regression checks. TerrainWorld remains authoritative for
## stored ground heights; chunk preparation consumes the derived surface field.

const Catalog = preload("res://scripts/terrain_catalog.gd")
const TerrainGenerator = preload("res://scripts/terrain_generator.gd")
const TerrainWorld = preload("res://scripts/terrain_world.gd")
const TerrainChunkBuildJob = preload("res://scripts/terrain_chunk_build_job.gd")
const DecorationCatalog = preload("res://scripts/decoration_catalog.gd")

var _failures: Array[String] = []
var _priorities: Dictionary = {}
var _liquids: Dictionary = {}
var _decoration_context: Dictionary = {}


func _initialize() -> void:
    for material in Catalog.MATERIALS:
        var terrain_id: int = int(material["id"])
        _priorities[terrain_id] = int(material["priority"])
        _liquids[terrain_id] = bool(material.get("liquid", false))
    _decoration_context = {
        "definitions": DecorationCatalog.DEFINITIONS,
        "indices_by_material": DecorationCatalog.build_indices_by_material(),
        "max_density_by_material": DecorationCatalog.build_max_density_by_material(),
        "seed": 84521 + 63017,
        "density": 1.0,
        "clustering": 0.72,
    }

    _test_liquid_metadata_and_height_ownership()
    _test_directional_edges_and_shoreline_sources()
    _benchmark_chunk_preparation()

    if _failures.is_empty():
        print("PHASE5D_VALIDATION PASS")
        quit(0)
        return
    for failure in _failures:
        push_error(failure)
    print("PHASE5D_VALIDATION FAIL count=%d" % _failures.size())
    quit(1)


func _test_liquid_metadata_and_height_ownership() -> void:
    _check(Catalog.is_liquid(0), "Water must be identified by catalog metadata")
    _check(not Catalog.is_liquid(3), "Grass must not be identified as liquid")

    var generator := TerrainGenerator.new()
    generator.configure(84521, 0.012, 0.055, true)
    generator.configure_elevation(true, 3, 0.006, 0.021, 0.14, -0.12, 0.16, 0.43, 0.02)
    var world := TerrainWorld.new()
    world.configure(generator)

    var generated_water_with_height: Variant = null
    for y in range(-128, 129):
        for x in range(-128, 129):
            var pos := Vector2i(x, y)
            if generator.get_cell(pos) == 0 and generator.get_elevation(pos) > 0:
                generated_water_with_height = pos
                break
        if generated_water_with_height != null:
            break
    _check(generated_water_with_height != null,
        "Seed 84521 should expose the former independent water/height mismatch")
    if generated_water_with_height != null:
        var water_pos: Vector2i = generated_water_with_height
        var stored_height: int = world.get_elevation(water_pos)
        _check(stored_height > 0, "Fixture water should retain its generated ground height")
        _check(world.get_surface_elevation(water_pos, 0) == 0,
            "Ordinary water must render at sea level 0")
        _check(world.get_elevation(water_pos) == stored_height,
            "Surface-height lookup must not flatten authoritative ground data")

    var manual_pos := Vector2i(7, 7)
    world.set_elevation_override(manual_pos, 3)
    world.set_override(manual_pos, 0)
    _check(world.get_elevation(manual_pos) == 3,
        "Painting water must preserve the manual ground-height override")
    _check(world.get_surface_elevation(manual_pos, 0) == 3,
        "Explicitly raised water ground must become visibly exposed")
    _check(world.get_visible_liquid_elevation(manual_pos, 0) == -1,
        "Explicitly raised ground must not lift the liquid surface")
    world.set_override(manual_pos, 3)
    _check(world.get_surface_elevation(manual_pos, 0) == 3,
        "Restoring land must reveal the preserved ground height")


func _test_directional_edges_and_shoreline_sources() -> void:
    var job = TerrainChunkBuildJob.new(Vector2i.ZERO)
    while not job.is_data_ready():
        job.process_data_quantum(
            _fixture_material, _fixture_surface_height, _fixture_surface_height,
            _priorities, _liquids, _decoration_context,
            {"generation_enabled": false}, 4096)

    var center_index: int = 10 * TerrainChunkBuildJob.CHUNK_SIZE + 10
    _check(int(job.cliff_edge_masks[center_index]) == 15,
        "Raised shoreline corner must classify N/W/E plus south-wall context")
    _check(int(job.cliff_edge_sources[center_index]) == 2,
        "Grass shoreline rim must use the liquid-contact atlas source")
    _check(int(job.cliff_owner_heights[center_index]) == 2,
        "South-facing shoreline wall must retain the raised land owner height")
    _check(int(job.cliff_sources[center_index]) == 2,
        "Shoreline wall must use the liquid-contact dirt source at level 0")

    var open_water_index: int = 9 * TerrainChunkBuildJob.CHUNK_SIZE + 10
    _check(int(job.cliff_owner_heights[open_water_index]) == 0,
        "Open water must not own cliff walls")
    _check(int(job.cliff_edge_sources[open_water_index]) == -1,
        "Open water must not own dark rim geometry")

    var west_seam_index: int = 10 * TerrainChunkBuildJob.CHUNK_SIZE + 31
    _check((int(job.cliff_edge_masks[west_seam_index]) & 4) == 0,
        "A plateau continuing across a chunk seam must not emit an east edge")
    var east_job = TerrainChunkBuildJob.new(Vector2i(1, 0))
    while not east_job.is_data_ready():
        east_job.process_data_quantum(
            _fixture_material, _fixture_surface_height, _fixture_surface_height,
            _priorities, _liquids, _decoration_context,
            {"generation_enabled": false}, 4096)
    var east_seam_index: int = 10 * TerrainChunkBuildJob.CHUNK_SIZE
    _check((int(east_job.cliff_edge_masks[east_seam_index]) & 2) == 0,
        "A plateau continuing across a chunk seam must not emit a west edge")

    for cell_index in range(TerrainChunkBuildJob.CELL_COUNT):
        if int(job.cliff_owner_heights[cell_index]) <= 0:
            continue
        var x: int = cell_index % TerrainChunkBuildJob.CHUNK_SIZE
        var y: int = floori(float(cell_index) / TerrainChunkBuildJob.CHUNK_SIZE)
        var pos := Vector2i(x, y)
        _check(_fixture_surface_height(pos) > _fixture_surface_height(pos + Vector2i.DOWN),
            "Every prepared wall must match an authoritative surface-height drop at %s" % pos)
        _check(not Catalog.is_liquid(_fixture_material(pos)),
            "Liquid cells must never own prepared wall geometry at %s" % pos)


func _benchmark_chunk_preparation() -> void:
    var totals: Array[int] = []
    var cliff_totals: Array[int] = []
    var decoration_totals: Array[int] = []
    var sampling_totals: Array[int] = []
    for chunk_y in range(-2, 3):
        for chunk_x in range(-2, 3):
            var job = TerrainChunkBuildJob.new(Vector2i(chunk_x, chunk_y))
            var start_usec: int = Time.get_ticks_usec()
            while not job.is_data_ready():
                job.process_data_quantum(
                    _fixture_material, _fixture_surface_height, _fixture_surface_height,
                    _priorities, _liquids, _decoration_context,
                    {"generation_enabled": false}, 4096)
            totals.append(Time.get_ticks_usec() - start_usec)
            cliff_totals.append(job.cliff_usec)
            decoration_totals.append(job.decoration_usec)
            sampling_totals.append(job.sampling_usec)
    totals.sort()
    cliff_totals.sort()
    var sum_usec: int = 0
    var cliff_sum_usec: int = 0
    var decoration_sum_usec: int = 0
    var sampling_sum_usec: int = 0
    for value in totals:
        sum_usec += value
    for value in cliff_totals:
        cliff_sum_usec += value
    for value in decoration_totals:
        decoration_sum_usec += value
    for value in sampling_totals:
        sampling_sum_usec += value
    var p95_index: int = mini(totals.size() - 1, ceili(totals.size() * 0.95) - 1)
    var p99_index: int = mini(totals.size() - 1, ceili(totals.size() * 0.99) - 1)
    print("PHASE5D_CHUNK_BENCHMARK chunks=%d avg_ms=%.3f p95_ms=%.3f p99_ms=%.3f worst_ms=%.3f sampling_avg_ms=%.3f cliff_avg_ms=%.3f decoration_avg_ms=%.3f" % [
        totals.size(), float(sum_usec) / totals.size() / 1000.0,
        float(totals[p95_index]) / 1000.0,
        float(totals[p99_index]) / 1000.0,
        float(totals[-1]) / 1000.0,
        float(sampling_sum_usec) / sampling_totals.size() / 1000.0,
        float(cliff_sum_usec) / cliff_totals.size() / 1000.0,
        float(decoration_sum_usec) / decoration_totals.size() / 1000.0,
    ])


func _fixture_material(pos: Vector2i) -> int:
    if pos in [Vector2i(10, 9), Vector2i(9, 10), Vector2i(10, 11)]:
        return 0
    return 3


func _fixture_surface_height(pos: Vector2i) -> int:
    if pos == Vector2i(10, 10):
        return 2
    if pos == Vector2i(11, 10):
        return 1
    if pos.y == 10 and pos.x in [31, 32]:
        return 2
    return 0


func _check(condition: bool, message: String) -> void:
    if not condition:
        _failures.append(message)

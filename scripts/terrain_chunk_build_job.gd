extends RefCounted
## Plain-data, resumable preparation for one terrain chunk. It caches material
## and elevation halos once, then derives ground, raised-surface and cliff slots
## without scene-tree access.

const TerrainWorld = preload("res://scripts/terrain_world.gd")
const DecorationPlacement = preload("res://scripts/decoration_placement.gd")
const EnvironmentObjectPlacement = preload("res://scripts/environment_object_placement.gd")
const OrganicCliffMeshBuilder = preload("res://scripts/organic_cliff_mesh_builder.gd")

const CHUNK_SIZE: int = 32
const HALO_MARGIN: int = 1
const HALO_SIZE: int = CHUNK_SIZE + HALO_MARGIN * 2
const CELL_COUNT: int = CHUNK_SIZE * CHUNK_SIZE
const SLOT_COUNT: int = 4
const MAX_ELEVATION: int = TerrainWorld.MAX_ELEVATION
const ENVIRONMENT_MARGIN: int = EnvironmentObjectPlacement.GROUND_DECORATION_MARGIN
const ENVIRONMENT_SIDE: int = CHUNK_SIZE + ENVIRONMENT_MARGIN * 2
const ENVIRONMENT_CELL_COUNT: int = ENVIRONMENT_SIDE * ENVIRONMENT_SIDE

const EDGE_STYLE_STANDARD: int = 0
const EDGE_STYLE_WALL_CONNECTED: int = 1
const EDGE_STYLE_SIMPLIFIED: int = 2

const EDGE_FLAG_SOUTH_WALL: int = 1
const EDGE_FLAG_NORTH_LIP: int = 2
const EDGE_FLAG_SIDE_RETURN: int = 4
const EDGE_FLAG_CONNECTED_CORNER: int = 8
const EDGE_FLAG_SUPPRESSED_SECONDARY: int = 16
const EDGE_FLAG_WATER_CONTACT: int = 32
const EDGE_FLAG_MULTI_LEVEL: int = 64
const EDGE_FLAG_SMALL_SHAPE: int = 128

var chunk_coord: Vector2i
var sample_index: int = 0
var prepare_index: int = 0
var decoration_index: int = 0
var environment_index: int = 0
var populate_index: int = 0
var decoration_populate_index: int = 0
var halo_ids := PackedInt32Array()
var halo_heights := PackedByteArray()
var halo_ground_heights := PackedByteArray()
var slot_sources := PackedInt32Array()
var slot_masks := PackedByteArray()
var elevated_slot_sources := PackedInt32Array()
var elevated_slot_masks := PackedByteArray()
var cliff_sources := PackedInt32Array()
var cliff_variants := PackedByteArray()
var cliff_owner_heights := PackedByteArray()
var cliff_edge_sources := PackedInt32Array()
var cliff_edge_masks := PackedByteArray() # N/W/E exposure plus S-wall context.
var cliff_edge_heights := PackedByteArray()
var cliff_edge_styles := PackedByteArray()
var cliff_edge_flags := PackedByteArray()
var cliff_edge_drops := PackedByteArray()
var decoration_ids := PackedInt32Array()
var decoration_variants := PackedByteArray()
var decoration_heights := PackedByteArray()
var environment_object_ids := PackedInt32Array()
var environment_object_variants := PackedByteArray()
var environment_object_anchor_x := PackedInt32Array()
var environment_object_anchor_y := PackedInt32Array()
var environment_object_heights := PackedByteArray()
var renderer # TerrainChunkRenderer while incremental population is in progress.
var max_elevation_present: int = 0
var organic_geometry_enabled: bool = false
var organic_geometry_revision: int = 0
var organic_geometry_state: Dictionary = {}
var organic_geometry_result: Dictionary = {}
var organic_geometry_usec: int = 0
var organic_face_construction_usec: int = 0
var organic_contour_generation_usec: int = 0
var organic_vertex_assembly_usec: int = 0
var organic_mesh_resource_usec: int = 0
var organic_scene_attachment_usec: int = 0
var organic_sampling_query_count: int = 0
var organic_halo_seeded: bool = false
var _organic_world_seed: int = 0
var _organic_liquid_by_id: Dictionary = {}
var _organic_unified_components_enabled: bool = false
var _organic_refined_silhouettes_enabled: bool = false
var _organic_connected_contours_enabled: bool = false
var _organic_unified_contours_enabled: bool = false
var _organic_profiling_enabled: bool = false
var _organic_height_step: int = OrganicCliffMeshBuilder.BASELINE_HEIGHT_STEP
var _directional_projection_enabled: bool = false

var sampling_usec: int = 0
var mask_usec: int = 0
var cliff_usec: int = 0 # Included in mask_usec; exposed for focused profiling.
var liquid_surface_usec: int = 0 # Included in mask_usec.
var cliff_edge_usec: int = 0 # Included in cliff_usec and mask_usec.
var decoration_usec: int = 0 # Included in mask_usec; presentation preparation only.
var tile_placement_usec: int = 0
var decoration_submission_usec: int = 0
var environment_usec: int = 0
var environment_submission_usec: int = 0
var layer_creation_usec: int = 0
var scene_insertion_usec: int = 0
var _decoration_cluster_cache: Dictionary = {}
var _decoration_context_cached: bool = false
var _decoration_definitions: Array = []
var _decoration_indices_by_material: Dictionary = {}
var _decoration_max_density_by_material: Dictionary = {}
var _decoration_seed: int = 0
var _decoration_density: float = 0.0
var _decoration_clustering: float = 0.0
var _environment_context: Dictionary = {}
var _object_world_lookup: Callable
var _object_height_lookup: Callable
var _object_ground_height_lookup: Callable
var _object_material_cache: Dictionary = {}
var _object_surface_height_cache: Dictionary = {}
var _object_ground_height_cache: Dictionary = {}
var _object_candidate_cache: Dictionary = {}


func _init(coord: Vector2i) -> void:
    chunk_coord = coord
    halo_ids.resize(HALO_SIZE * HALO_SIZE)
    halo_heights.resize(HALO_SIZE * HALO_SIZE)
    halo_ground_heights.resize(HALO_SIZE * HALO_SIZE)
    slot_sources.resize(CELL_COUNT * SLOT_COUNT)
    slot_sources.fill(-1)
    slot_masks.resize(CELL_COUNT * SLOT_COUNT)
    elevated_slot_sources.resize(CELL_COUNT * SLOT_COUNT * MAX_ELEVATION)
    elevated_slot_sources.fill(-1)
    elevated_slot_masks.resize(CELL_COUNT * SLOT_COUNT * MAX_ELEVATION)
    cliff_sources.resize(CELL_COUNT * MAX_ELEVATION)
    cliff_sources.fill(-1)
    cliff_variants.resize(CELL_COUNT * MAX_ELEVATION)
    cliff_owner_heights.resize(CELL_COUNT)
    cliff_edge_sources.resize(CELL_COUNT)
    cliff_edge_sources.fill(-1)
    cliff_edge_masks.resize(CELL_COUNT)
    cliff_edge_heights.resize(CELL_COUNT)
    cliff_edge_styles.resize(CELL_COUNT)
    cliff_edge_flags.resize(CELL_COUNT)
    cliff_edge_drops.resize(CELL_COUNT)
    decoration_ids.resize(CELL_COUNT)
    decoration_ids.fill(-1)
    decoration_variants.resize(CELL_COUNT)
    decoration_heights.resize(CELL_COUNT)


func is_data_ready() -> bool:
    return (prepare_index >= CELL_COUNT
        and decoration_index >= CELL_COUNT
        and environment_index >= ENVIRONMENT_CELL_COUNT
        and is_organic_geometry_ready())


func configure_organic_geometry(
        enabled: bool, world_seed: int, liquid_by_id: Dictionary,
        unified_components_enabled: bool, refined_silhouettes_enabled: bool,
        connected_contours_enabled: bool = false,
        unified_contours_enabled: bool = false,
        revision: int = 0, profiling_enabled: bool = false,
        height_step: int = OrganicCliffMeshBuilder.BASELINE_HEIGHT_STEP,
        directional_projection_enabled: bool = false) -> void:
    organic_geometry_enabled = enabled
    organic_geometry_revision = revision
    _organic_world_seed = world_seed
    _organic_liquid_by_id = liquid_by_id
    _organic_unified_components_enabled = unified_components_enabled
    _organic_refined_silhouettes_enabled = refined_silhouettes_enabled
    _organic_connected_contours_enabled = connected_contours_enabled
    _organic_unified_contours_enabled = unified_contours_enabled
    _organic_profiling_enabled = profiling_enabled
    _organic_height_step = maxi(1, height_step)
    _directional_projection_enabled = directional_projection_enabled


func seed_organic_halo(ids: PackedInt32Array, heights: PackedByteArray) -> bool:
    ## Reuses a completed presentation snapshot for geometry-only mode changes.
    ## Packed arrays are copy-on-write and this job never mutates a seeded halo.
    if ids.size() != halo_ids.size() or heights.size() != halo_heights.size():
        return false
    halo_ids = ids
    halo_heights = heights
    sample_index = halo_ids.size()
    organic_halo_seeded = true
    return true


func is_organic_geometry_ready() -> bool:
    return (not organic_geometry_enabled or (
        not organic_geometry_state.is_empty()
        and OrganicCliffMeshBuilder.is_incremental_ready(organic_geometry_state)))


func is_processing_organic_geometry() -> bool:
    return (organic_geometry_enabled and sample_index >= halo_ids.size()
        and prepare_index >= CELL_COUNT and decoration_index >= CELL_COUNT
        and environment_index >= ENVIRONMENT_CELL_COUNT
        and not is_organic_geometry_ready())


func is_complete() -> bool:
    return populate_index >= CELL_COUNT and decoration_populate_index >= CELL_COUNT


func is_terrain_populated() -> bool:
    return populate_index >= CELL_COUNT


func process_data_quantum(
        world_lookup: Callable,
        height_lookup: Callable,
        ground_height_lookup: Callable,
        priority_by_id: Dictionary,
        liquid_by_id: Dictionary,
        decoration_context: Dictionary,
        environment_context: Dictionary,
        max_cells: int) -> int:
    var processed: int = 0
    if sample_index < halo_ids.size():
        var phase_start: int = Time.get_ticks_usec()
        while sample_index < halo_ids.size() and processed < max_cells:
            var halo_x: int = sample_index % HALO_SIZE
            var halo_y: int = floori(float(sample_index) / HALO_SIZE)
            var world_pos: Vector2i = (
                chunk_coord * CHUNK_SIZE
                + Vector2i(halo_x - HALO_MARGIN, halo_y - HALO_MARGIN))
            halo_ids[sample_index] = int(world_lookup.call(world_pos))
            halo_heights[sample_index] = int(height_lookup.call(world_pos))
            halo_ground_heights[sample_index] = int(ground_height_lookup.call(world_pos))
            max_elevation_present = maxi(
                max_elevation_present, int(halo_heights[sample_index]))
            sample_index += 1
            processed += 1
        sampling_usec += Time.get_ticks_usec() - phase_start
        return processed

    if prepare_index < CELL_COUNT:
        var phase_start: int = Time.get_ticks_usec()
        while prepare_index < CELL_COUNT and processed < max_cells:
            _prepare_cell(prepare_index, priority_by_id, liquid_by_id)
            prepare_index += 1
            processed += 1
        mask_usec += Time.get_ticks_usec() - phase_start
        return processed

    if decoration_index < CELL_COUNT:
        if not bool(decoration_context.get("generation_enabled", true)):
            decoration_index = CELL_COUNT
            decoration_populate_index = CELL_COUNT
            return processed
        if not _decoration_context_cached:
            _cache_decoration_context(decoration_context)
        if _decoration_cluster_cache.is_empty():
            _decoration_cluster_cache = DecorationPlacement.build_cluster_cache(
                chunk_coord * CHUNK_SIZE, CHUNK_SIZE, _decoration_seed)
        var decoration_start: int = Time.get_ticks_usec()
        while decoration_index < CELL_COUNT and processed < max_cells:
            _prepare_decoration(
                decoration_index,
                decoration_index % CHUNK_SIZE,
                floori(float(decoration_index) / CHUNK_SIZE),
                liquid_by_id)
            decoration_index += 1
            processed += 1
        decoration_usec += Time.get_ticks_usec() - decoration_start
        return processed

    if (environment_index < ENVIRONMENT_CELL_COUNT
            and not bool(environment_context.get("generation_enabled", true))):
        environment_index = ENVIRONMENT_CELL_COUNT
        return processed
    if _environment_context.is_empty():
        _environment_context = environment_context
        _object_world_lookup = world_lookup
        _object_height_lookup = height_lookup
        _object_ground_height_lookup = ground_height_lookup
    var environment_start: int = Time.get_ticks_usec()
    while environment_index < ENVIRONMENT_CELL_COUNT and processed < max_cells:
        _prepare_environment_anchor(environment_index)
        environment_index += 1
        processed += 1
    environment_usec += Time.get_ticks_usec() - environment_start
    if environment_index >= ENVIRONMENT_CELL_COUNT and processed < max_cells:
        processed += process_organic_geometry_quantum(max_cells - processed)
    return processed


func process_organic_geometry_quantum(max_cells: int) -> int:
    if not organic_geometry_enabled or max_cells <= 0:
        return 0
    if organic_geometry_state.is_empty():
        organic_geometry_state = OrganicCliffMeshBuilder.create_incremental(
            chunk_coord, MAX_ELEVATION, _organic_world_seed,
            halo_ids, halo_heights, _organic_liquid_by_id,
            _organic_unified_components_enabled,
            _organic_refined_silhouettes_enabled,
            _organic_connected_contours_enabled,
            _organic_unified_contours_enabled,
            _organic_profiling_enabled, _organic_height_step,
            _directional_projection_enabled)
    var started_usec: int = Time.get_ticks_usec()
    var processed: int = OrganicCliffMeshBuilder.process_incremental(
        organic_geometry_state, max_cells)
    organic_geometry_usec += Time.get_ticks_usec() - started_usec
    return processed


func process_organic_rebuild_quantum(
        world_lookup: Callable, height_lookup: Callable, max_cells: int) -> int:
    ## Organic-only replacement jobs use the same bounded 34x34 snapshot as
    ## streaming jobs, but do not rebuild unrelated terrain or decoration data.
    var processed: int = 0
    if sample_index < halo_ids.size():
        var started_usec: int = Time.get_ticks_usec()
        while sample_index < halo_ids.size() and processed < max_cells:
            var halo_x: int = sample_index % HALO_SIZE
            var halo_y: int = floori(float(sample_index) / HALO_SIZE)
            var world_pos: Vector2i = (
                chunk_coord * CHUNK_SIZE
                + Vector2i(halo_x - HALO_MARGIN, halo_y - HALO_MARGIN))
            halo_ids[sample_index] = int(world_lookup.call(world_pos))
            halo_heights[sample_index] = int(height_lookup.call(world_pos))
            organic_sampling_query_count += 1
            sample_index += 1
            processed += 1
        sampling_usec += Time.get_ticks_usec() - started_usec
        return processed
    return process_organic_geometry_quantum(max_cells)


func finalize_organic_geometry() -> Dictionary:
    if not organic_geometry_enabled:
        return {}
    if organic_geometry_result.is_empty():
        organic_geometry_result = OrganicCliffMeshBuilder.finalize_incremental(
            organic_geometry_state)
        organic_mesh_resource_usec = int(organic_geometry_result.mesh_resource_usec)
        organic_face_construction_usec = int(organic_geometry_result.face_construction_usec)
        organic_contour_generation_usec = int(organic_geometry_result.contour_generation_usec)
        organic_vertex_assembly_usec = int(organic_geometry_result.vertex_assembly_usec)
        organic_geometry_result.sampling_usec = sampling_usec
        var query_count: int = (0 if organic_halo_seeded
            else maxi(organic_sampling_query_count, HALO_SIZE * HALO_SIZE))
        organic_geometry_result.height_query_count = query_count
        organic_geometry_result.material_query_count = query_count
        # Streaming jobs share sampling with terrain preparation, so build_usec
        # intentionally excludes it. sampling_usec remains separately visible.
        organic_geometry_result.build_usec = organic_geometry_usec + organic_mesh_resource_usec
    return organic_geometry_result


func _prepare_cell(
        cell_index: int, priority_by_id: Dictionary,
        liquid_by_id: Dictionary) -> void:
    var x: int = cell_index % CHUNK_SIZE
    var y: int = floori(float(cell_index) / CHUNK_SIZE)
    var top_left_index: int = y * HALO_SIZE + x
    var corners: Array[int] = [
        halo_ids[top_left_index],
        halo_ids[top_left_index + 1],
        halo_ids[top_left_index + HALO_SIZE],
        halo_ids[top_left_index + HALO_SIZE + 1],
    ]
    var corner_heights: Array[int] = [
        halo_heights[top_left_index],
        halo_heights[top_left_index + 1],
        halo_heights[top_left_index + HALO_SIZE],
        halo_heights[top_left_index + HALO_SIZE + 1],
    ]
    var liquid_start: int = Time.get_ticks_usec()
    _prepare_ground_surface(cell_index, corners, corner_heights, priority_by_id)
    if _contains_liquid(corners, liquid_by_id):
        liquid_surface_usec += Time.get_ticks_usec() - liquid_start
    if max_elevation_present == 0:
        return
    _prepare_elevated_surfaces(cell_index, corners, corner_heights, priority_by_id)
    var cliff_start: int = Time.get_ticks_usec()
    _prepare_cliff(cell_index, x, y, liquid_by_id)
    var cliff_edge_start: int = Time.get_ticks_usec()
    _prepare_cliff_edges(cell_index, x, y, liquid_by_id)
    cliff_edge_usec += Time.get_ticks_usec() - cliff_edge_start
    cliff_usec += Time.get_ticks_usec() - cliff_start


func _prepare_decoration(
        cell_index: int, x: int, y: int,
        liquid_by_id: Dictionary) -> void:
    var center_index: int = (y + HALO_MARGIN) * HALO_SIZE + x + HALO_MARGIN
    var north_index: int = center_index - HALO_SIZE
    var east_index: int = center_index + 1
    var south_index: int = center_index + HALO_SIZE
    var west_index: int = center_index - 1
    var world_pos: Vector2i = chunk_coord * CHUNK_SIZE + Vector2i(x, y)
    if not DecorationPlacement.is_candidate_anchor(world_pos, _decoration_seed):
        return
    var selection: Vector2i = DecorationPlacement.choose(
        world_pos,
        int(halo_ids[center_index]),
        int(halo_ground_heights[center_index]),
        int(halo_heights[center_index]),
        int(halo_ids[north_index]),
        int(halo_ids[east_index]),
        int(halo_ids[south_index]),
        int(halo_ids[west_index]),
        int(halo_heights[north_index]),
        int(halo_heights[east_index]),
        int(halo_heights[south_index]),
        int(halo_heights[west_index]),
        _decoration_definitions,
        _decoration_indices_by_material,
        _decoration_max_density_by_material,
        liquid_by_id,
        _decoration_seed,
        _decoration_density,
        _decoration_clustering,
        true,
        DecorationPlacement.cluster_value_from_cache(
            world_pos, _decoration_cluster_cache))
    if selection.x < 0:
        return
    decoration_ids[cell_index] = selection.x
    decoration_variants[cell_index] = selection.y
    decoration_heights[cell_index] = halo_heights[center_index]


func _cache_decoration_context(decoration_context: Dictionary) -> void:
    _decoration_definitions = decoration_context["definitions"]
    _decoration_indices_by_material = decoration_context["indices_by_material"]
    _decoration_max_density_by_material = decoration_context["max_density_by_material"]
    _decoration_seed = int(decoration_context["seed"])
    _decoration_density = float(decoration_context["density"])
    _decoration_clustering = float(decoration_context["clustering"])
    _decoration_context_cached = true


func _prepare_environment_anchor(expanded_index: int) -> void:
    var local_pos := Vector2i(
        expanded_index % ENVIRONMENT_SIDE - ENVIRONMENT_MARGIN,
        floori(float(expanded_index) / ENVIRONMENT_SIDE) - ENVIRONMENT_MARGIN)
    var world_pos: Vector2i = chunk_coord * CHUNK_SIZE + local_pos
    var selection: Vector2i = EnvironmentObjectPlacement.choose(
        world_pos, _environment_context,
        _cached_object_material,
        _cached_object_ground_height,
        _cached_object_surface_height,
        _object_candidate_cache)
    if selection.x < 0:
        return
    var definition: Dictionary = _environment_context["definitions_by_id"][selection.x]
    for footprint_offset in definition["footprint"]:
        var decoration_local: Vector2i = local_pos + Vector2i(footprint_offset)
        if (decoration_local.x >= 0 and decoration_local.y >= 0
                and decoration_local.x < CHUNK_SIZE and decoration_local.y < CHUNK_SIZE):
            decoration_ids[decoration_local.y * CHUNK_SIZE + decoration_local.x] = -1
    if (local_pos.x < 0 or local_pos.y < 0
            or local_pos.x >= CHUNK_SIZE or local_pos.y >= CHUNK_SIZE):
        return
    environment_object_ids.append(selection.x)
    environment_object_variants.append(selection.y)
    environment_object_anchor_x.append(world_pos.x)
    environment_object_anchor_y.append(world_pos.y)
    environment_object_heights.append(_cached_object_surface_height(world_pos))


func _cached_object_material(world_pos: Vector2i) -> int:
    if not _object_material_cache.has(world_pos):
        _object_material_cache[world_pos] = int(_object_world_lookup.call(world_pos))
    return int(_object_material_cache[world_pos])


func _cached_object_surface_height(world_pos: Vector2i) -> int:
    if not _object_surface_height_cache.has(world_pos):
        _object_surface_height_cache[world_pos] = int(_object_height_lookup.call(world_pos))
    return int(_object_surface_height_cache[world_pos])


func _cached_object_ground_height(world_pos: Vector2i) -> int:
    if not _object_ground_height_cache.has(world_pos):
        _object_ground_height_cache[world_pos] = int(_object_ground_height_lookup.call(world_pos))
    return int(_object_ground_height_cache[world_pos])


func _prepare_ground_surface(
        cell_index: int, corners: Array[int], corner_heights: Array[int],
        priority_by_id: Dictionary) -> void:
    # Height is part of surface identity. A material at a raised corner must
    # never enter the sea-level stack merely because it has higher priority.
    var unique_ids: Array[int] = []
    for corner_index in range(4):
        if corner_heights[corner_index] == 0 and not unique_ids.has(corners[corner_index]):
            unique_ids.append(corners[corner_index])
    unique_ids.sort_custom(func(a: int, b: int) -> bool:
        return int(priority_by_id[a]) < int(priority_by_id[b]))
    for depth in range(unique_ids.size()):
        var terrain_id: int = unique_ids[depth]
        var cutoff_priority: int = int(priority_by_id[terrain_id])
        var bitmask: int = 0
        for corner_index in range(4):
            if (corner_heights[corner_index] == 0
                    and int(priority_by_id[corners[corner_index]]) >= cutoff_priority):
                bitmask |= (8 >> corner_index)
        var slot_index: int = depth * CELL_COUNT + cell_index
        slot_sources[slot_index] = terrain_id
        slot_masks[slot_index] = bitmask


func _prepare_elevated_surfaces(
        cell_index: int,
        corners: Array[int],
        corner_heights: Array[int],
        priority_by_id: Dictionary) -> void:
    if (corner_heights[0] == 0 and corner_heights[1] == 0
            and corner_heights[2] == 0 and corner_heights[3] == 0):
        return
    for elevation in range(1, MAX_ELEVATION + 1):
        var ids_at_height: Array[int] = []
        for corner_index in range(4):
            if corner_heights[corner_index] == elevation:
                var terrain_id: int = corners[corner_index]
                if not ids_at_height.has(terrain_id):
                    ids_at_height.append(terrain_id)
        if ids_at_height.is_empty():
            continue
        ids_at_height.sort_custom(func(a: int, b: int) -> bool:
            return int(priority_by_id[a]) < int(priority_by_id[b]))
        for depth in range(ids_at_height.size()):
            var terrain_id: int = ids_at_height[depth]
            var cutoff_priority: int = int(priority_by_id[terrain_id])
            var bitmask: int = 0
            for corner_index in range(4):
                if (corner_heights[corner_index] == elevation
                        and int(priority_by_id[corners[corner_index]]) >= cutoff_priority):
                    bitmask |= (8 >> corner_index)
            var slot_index: int = (
                ((elevation - 1) * SLOT_COUNT + depth) * CELL_COUNT + cell_index)
            elevated_slot_sources[slot_index] = terrain_id
            elevated_slot_masks[slot_index] = bitmask


func _prepare_cliff(
        cell_index: int, x: int, y: int,
        liquid_by_id: Dictionary) -> void:
    var center_index: int = (y + HALO_MARGIN) * HALO_SIZE + x + HALO_MARGIN
    var south_index: int = center_index + HALO_SIZE
    var elevation: int = int(halo_heights[center_index])
    var south_elevation: int = int(halo_heights[south_index])
    var terrain_id: int = int(halo_ids[center_index])
    if bool(liquid_by_id.get(terrain_id, false)):
        return
    if elevation <= south_elevation:
        return

    cliff_owner_heights[cell_index] = elevation
    var south_terrain_id: int = int(halo_ids[south_index])
    var shoreline: bool = bool(liquid_by_id.get(south_terrain_id, false))
    var cliff_source: int = _cliff_source_for(terrain_id, shoreline)
    for level in range(south_elevation, elevation):
        var left_exposed: bool = _neighbor_has_cliff_at(center_index - 1, level)
        var right_exposed: bool = _neighbor_has_cliff_at(center_index + 1, level)
        var cap_mask: int = (0 if left_exposed else 1) | (0 if right_exposed else 2)
        var world_pos: Vector2i = chunk_coord * CHUNK_SIZE + Vector2i(x, y)
        var top_step: bool = level == elevation - 1
        var variant: int = (
            _cliff_style(world_pos) * 8
            + (4 if top_step else 0)
            + cap_mask)
        var slot_index: int = level * CELL_COUNT + cell_index
        cliff_sources[slot_index] = cliff_source
        cliff_variants[slot_index] = variant


func _prepare_cliff_edges(
        cell_index: int, x: int, y: int,
        liquid_by_id: Dictionary) -> void:
    var center_index: int = (y + HALO_MARGIN) * HALO_SIZE + x + HALO_MARGIN
    var elevation: int = int(halo_heights[center_index])
    var terrain_id: int = int(halo_ids[center_index])
    if elevation <= 0 or bool(liquid_by_id.get(terrain_id, false)):
        return
    var north_index: int = center_index - HALO_SIZE
    var west_index: int = center_index - 1
    var east_index: int = center_index + 1
    var south_index: int = center_index + HALO_SIZE
    # South-only cells are owned entirely by the primary wall layer. Skip the
    # richer classifier for interiors and wall faces that have no lip/return.
    if (int(halo_heights[north_index]) >= elevation
            and int(halo_heights[west_index]) >= elevation
            and int(halo_heights[east_index]) >= elevation):
        return
    var classification: Vector4i = classify_cliff_edge_values(
        elevation, terrain_id,
        int(halo_heights[north_index]), int(halo_heights[east_index]),
        int(halo_heights[south_index]), int(halo_heights[west_index]),
        int(halo_heights[north_index + 1]), int(halo_heights[south_index + 1]),
        int(halo_heights[south_index - 1]), int(halo_heights[north_index - 1]),
        int(halo_ids[north_index]), int(halo_ids[east_index]),
        int(halo_ids[south_index]), int(halo_ids[west_index]),
        liquid_by_id)
    var edge_mask: int = classification.x
    if (edge_mask & 7) == 0:
        return
    cliff_edge_sources[cell_index] = _cliff_source_for(
        terrain_id, (classification.z & EDGE_FLAG_WATER_CONTACT) != 0)
    cliff_edge_masks[cell_index] = edge_mask
    cliff_edge_heights[cell_index] = elevation
    cliff_edge_styles[cell_index] = classification.y
    cliff_edge_flags[cell_index] = classification.z
    cliff_edge_drops[cell_index] = classification.w


static func classify_cliff_edge_samples(
        center_height: int, center_id: int,
        north_height: int, east_height: int,
        south_height: int, west_height: int,
        north_east_height: int, south_east_height: int,
        south_west_height: int, north_west_height: int,
        north_id: int, east_id: int, south_id: int, west_id: int,
        liquid_by_id: Dictionary) -> Dictionary:
    ## Deterministic local presentation classification. The 3x3 sample is
    ## deliberately bounded so resumable chunk preparation stays seam-safe.
    var values: Vector4i = classify_cliff_edge_values(
        center_height, center_id,
        north_height, east_height, south_height, west_height,
        north_east_height, south_east_height,
        south_west_height, north_west_height,
        north_id, east_id, south_id, west_id, liquid_by_id)
    return {
        "edge_mask": values.x,
        "style": values.y,
        "flags": values.z,
        "max_drop": values.w,
        "water_contact": (values.z & EDGE_FLAG_WATER_CONTACT) != 0,
    }


static func classify_cliff_edge_values(
        center_height: int, center_id: int,
        north_height: int, east_height: int,
        south_height: int, west_height: int,
        north_east_height: int, south_east_height: int,
        south_west_height: int, north_west_height: int,
        north_id: int, east_id: int, south_id: int, west_id: int,
        liquid_by_id: Dictionary) -> Vector4i:
    ## Compact hot-path form: x=mask, y=style, z=flags, w=max drop.
    if center_height <= 0 or bool(liquid_by_id.get(center_id, false)):
        return Vector4i.ZERO
    var edge_mask: int = 0
    var exposed_count: int = 0
    var support_count: int = 0
    var max_drop: int = 0
    var water_contact: bool = false
    if north_height < center_height:
        edge_mask |= 1
        exposed_count += 1
        max_drop = maxi(max_drop, center_height - north_height)
        water_contact = bool(liquid_by_id.get(north_id, false))
    else:
        support_count += 1
    if west_height < center_height:
        edge_mask |= 2
        exposed_count += 1
        max_drop = maxi(max_drop, center_height - west_height)
        water_contact = water_contact or bool(liquid_by_id.get(west_id, false))
    else:
        support_count += 1
    if east_height < center_height:
        edge_mask |= 4
        exposed_count += 1
        max_drop = maxi(max_drop, center_height - east_height)
        water_contact = water_contact or bool(liquid_by_id.get(east_id, false))
    else:
        support_count += 1
    if south_height < center_height:
        edge_mask |= 8
        exposed_count += 1
        max_drop = maxi(max_drop, center_height - south_height)
        water_contact = water_contact or bool(liquid_by_id.get(south_id, false))
    else:
        support_count += 1
    var diagonal_support: int = (
        int(north_east_height >= center_height)
        + int(south_east_height >= center_height)
        + int(south_west_height >= center_height)
        + int(north_west_height >= center_height))
    var has_south_wall: bool = (edge_mask & 8) != 0
    var has_north_lip: bool = (edge_mask & 1) != 0
    var has_side_exposure: bool = (edge_mask & 6) != 0
    var connected_corner: bool = has_south_wall and has_side_exposure
    var narrow_shape: bool = (
        (west_height < center_height and east_height < center_height)
        or (north_height < center_height and south_height < center_height))
    var small_shape: bool = (
        support_count <= 1
        or exposed_count >= 3
        or (support_count == 2 and diagonal_support <= 1))
    var style: int = EDGE_STYLE_STANDARD
    if small_shape or narrow_shape:
        style = EDGE_STYLE_SIMPLIFIED
    elif connected_corner:
        style = EDGE_STYLE_WALL_CONNECTED
    elif water_contact and has_side_exposure and not has_south_wall:
        # A side-only liquid boundary is the main source of detached grey
        # strips. Preserve the true height boundary but omit that secondary
        # strip until it can connect to a northern lip or southern wall.
        style = EDGE_STYLE_SIMPLIFIED
    var suppressed_secondary: bool = (
        has_side_exposure
        and (style == EDGE_STYLE_SIMPLIFIED
            or (water_contact and not has_south_wall)))
    var flags: int = 0
    flags |= EDGE_FLAG_SOUTH_WALL if has_south_wall else 0
    flags |= EDGE_FLAG_NORTH_LIP if has_north_lip else 0
    flags |= EDGE_FLAG_SIDE_RETURN if has_side_exposure else 0
    flags |= EDGE_FLAG_CONNECTED_CORNER if connected_corner else 0
    flags |= EDGE_FLAG_SUPPRESSED_SECONDARY if suppressed_secondary else 0
    flags |= EDGE_FLAG_WATER_CONTACT if water_contact else 0
    flags |= EDGE_FLAG_MULTI_LEVEL if max_drop > 1 else 0
    flags |= EDGE_FLAG_SMALL_SHAPE if small_shape else 0
    return Vector4i(edge_mask, style, flags, max_drop)


static func edge_diagnostic_labels(flags: int) -> PackedStringArray:
    var labels := PackedStringArray()
    if (flags & EDGE_FLAG_SOUTH_WALL) != 0:
        labels.append("southern_wall")
    if (flags & EDGE_FLAG_NORTH_LIP) != 0:
        labels.append("northern_lip")
    if (flags & EDGE_FLAG_SIDE_RETURN) != 0:
        labels.append("east_west_return")
    if (flags & EDGE_FLAG_CONNECTED_CORNER) != 0:
        labels.append("connected_corner")
    if (flags & EDGE_FLAG_SUPPRESSED_SECONDARY) != 0:
        labels.append("suppressed_secondary_cue")
    if (flags & EDGE_FLAG_WATER_CONTACT) != 0:
        labels.append("water_contact_edge")
    if (flags & EDGE_FLAG_MULTI_LEVEL) != 0:
        labels.append("multi_level_drop")
    if (flags & EDGE_FLAG_SMALL_SHAPE) != 0:
        labels.append("small_shape")
    return labels


static func cliff_edge_variant(style: int, max_drop: int) -> int:
    ## Packs the existing edge treatment and a bounded physical drop into the
    ## shared atlas row. Presentation gains height-aware returns without
    ## changing authoritative elevation or adding per-cell nodes.
    return clampi(style, 0, 2) * 3 + clampi(max_drop, 1, 3) - 1


static func _cliff_source_for(terrain_id: int, shoreline: bool) -> int:
    var stone_style: bool = terrain_id in [4, 5, 7]
    return (2 if shoreline else 0) + (1 if stone_style else 0)


func _neighbor_has_cliff_at(center_index: int, level: int) -> bool:
    var neighbor_height: int = int(halo_heights[center_index])
    var neighbor_south_height: int = int(halo_heights[center_index + HALO_SIZE])
    return neighbor_south_height <= level and neighbor_height > level


static func _cliff_style(world_pos: Vector2i) -> int:
    # One profile per logical southern face. Reusing it through every stacked
    # level prevents the silhouette changing at internal step boundaries.
    return posmod(world_pos.x * 17 + world_pos.y * 31, 4)


static func _contains_liquid(corners: Array[int], liquid_by_id: Dictionary) -> bool:
    for terrain_id in corners:
        if bool(liquid_by_id.get(terrain_id, false)):
            return true
    return false


func _sorted_unique_ids(corners: Array[int], priority_by_id: Dictionary) -> Array[int]:
    var unique_ids: Array[int] = []
    for terrain_id in corners:
        if not unique_ids.has(terrain_id):
            unique_ids.append(terrain_id)
    unique_ids.sort_custom(func(a: int, b: int) -> bool:
        return int(priority_by_id[a]) < int(priority_by_id[b]))
    return unique_ids

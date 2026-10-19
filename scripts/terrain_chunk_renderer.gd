extends Node2D
## Visual-only renderer for one 32x32 chunk. Four original ground-composition
## layers remain intact; batched layers add raised surfaces and cliff faces.

const TerrainWorld = preload("res://scripts/terrain_world.gd")
const TerrainChunkBuildJob = preload("res://scripts/terrain_chunk_build_job.gd")
const OrganicCliffMeshBuilder = preload("res://scripts/organic_cliff_mesh_builder.gd")
const DecorationPlacement = preload("res://scripts/decoration_placement.gd")

const CHUNK_SIZE: int = 32
const TILE_SIZE: Vector2i = Vector2i(32, 32)
const HEIGHT_STEP: int = 16
const SLOT_COUNT: int = 4
const MAX_ELEVATION: int = TerrainWorld.MAX_ELEVATION
const CORNER_OFFSETS = [
    Vector2i(-1, -1), # TL -> bit 8
    Vector2i( 0, -1), # TR -> bit 4
    Vector2i(-1,  0), # BL -> bit 2
    Vector2i( 0,  0), # BR -> bit 1
]

var chunk_coord: Vector2i
var priority_by_id: Dictionary
var liquid_by_id: Dictionary
var layers: Array[TileMapLayer] = [] # Original height-zero composition.
var elevated_layers: Array = [] # elevation - 1 -> four TileMapLayers.
var cliff_layers: Array[TileMapLayer] = [] # elevation - 1 -> one TileMapLayer.
var cliff_shadow_layers: Array[TileMapLayer] = [] # elevation - 1 -> cast shadows.
var cliff_edge_layers: Array[TileMapLayer] = [] # elevation - 1 -> side ledge cues.
var decoration_layers: Array[TileMapLayer] = [] # visible elevation -> batched details.
var organic_cliff_mesh_layers: Array[MeshInstance2D] = [] # One mesh per elevation.
var organic_cliff_edge_mesh_layers: Array[MeshInstance2D] = [] # Unified lips/returns.
var organic_cliff_shadow_mesh_layers: Array[MeshInstance2D] = [] # Contour-following shadows.
var _world_lookup: Callable
var _height_lookup: Callable
var _ground_height_lookup: Callable
var _environment_occupancy_lookup: Callable
var _surface_tileset: TileSet
var _cliff_tileset: TileSet
var _cliff_edge_tileset: TileSet
var _decoration_tileset: TileSet
var _decoration_atlas_by_id: Dictionary
var _decoration_context: Dictionary
var _decorations_visible: bool = true
var _organic_cliff_geometry_enabled: bool = false
var _unified_cliff_components_enabled: bool = false
var _refined_cliff_silhouettes_enabled: bool = false
var _connected_cliff_contours_enabled: bool = false
var _cliff_edge_overlays_visible: bool = true
var _cliff_shadows_visible: bool = true
var _organic_cliff_world_seed: int = 0
var _organic_cliff_material: Material
var _organic_geometry_ready: bool = false
var _active_max_elevation: int = 0
var profiling_enabled: bool = false
var profile_layer_creation_usec: int = 0
var profile_sampling_usec: int = 0
var profile_mask_usec: int = 0
var profile_tile_placement_usec: int = 0
var organic_cliff_geometry_usec: int = 0
var organic_cliff_face_count: int = 0
var organic_cliff_vertex_count: int = 0
var organic_cliff_triangle_count: int = 0
var organic_cliff_edge_component_count: int = 0
var organic_cliff_shadow_count: int = 0
var organic_cliff_height_query_count: int = 0
var organic_cliff_material_query_count: int = 0
var organic_cliff_sampling_usec: int = 0
var organic_cliff_face_construction_usec: int = 0
var organic_cliff_contour_generation_usec: int = 0
var organic_cliff_vertex_assembly_usec: int = 0
var organic_cliff_mesh_resource_usec: int = 0
var organic_cliff_scene_attachment_usec: int = 0


func configure(
        coord: Vector2i,
        shared_surface_tileset: TileSet,
        shared_cliff_tileset: TileSet,
        shared_cliff_edge_tileset: TileSet,
        shared_decoration_tileset: TileSet,
        decoration_atlas_by_id: Dictionary,
        decoration_context: Dictionary,
        priorities: Dictionary,
        liquids: Dictionary,
        world_lookup: Callable,
        height_lookup: Callable,
        ground_height_lookup: Callable,
        environment_occupancy_lookup: Callable,
        decorations_visible: bool,
        organic_cliff_geometry_enabled: bool,
        unified_cliff_components_enabled: bool,
        refined_cliff_silhouettes_enabled: bool,
        connected_cliff_contours_enabled: bool,
        organic_cliff_world_seed: int,
        organic_cliff_material: Material,
        initial_max_elevation: int = 0) -> void:
    var profile_start: int = Time.get_ticks_usec() if profiling_enabled else 0
    chunk_coord = coord
    priority_by_id = priorities
    liquid_by_id = liquids
    _world_lookup = world_lookup
    _height_lookup = height_lookup
    _ground_height_lookup = ground_height_lookup
    _environment_occupancy_lookup = environment_occupancy_lookup
    _surface_tileset = shared_surface_tileset
    _cliff_tileset = shared_cliff_tileset
    _cliff_edge_tileset = shared_cliff_edge_tileset
    _decoration_tileset = shared_decoration_tileset
    _decoration_atlas_by_id = decoration_atlas_by_id
    _decoration_context = decoration_context
    _decorations_visible = decorations_visible
    _organic_cliff_geometry_enabled = organic_cliff_geometry_enabled
    _unified_cliff_components_enabled = unified_cliff_components_enabled
    _refined_cliff_silhouettes_enabled = refined_cliff_silhouettes_enabled
    _connected_cliff_contours_enabled = connected_cliff_contours_enabled
    _organic_cliff_world_seed = organic_cliff_world_seed
    _organic_cliff_material = organic_cliff_material
    position = Vector2(coord * CHUNK_SIZE * TILE_SIZE)
    name = "TerrainChunk_%d_%d" % [coord.x, coord.y]

    for depth in range(SLOT_COUNT):
        var layer := _create_layer("DisplayDepth_%d" % depth, shared_surface_tileset)
        layer.position = Vector2(-TILE_SIZE.x / 2.0, -TILE_SIZE.y / 2.0)
        layer.z_index = depth
        layers.append(layer)

    cliff_layers.resize(MAX_ELEVATION)
    cliff_shadow_layers.resize(MAX_ELEVATION)
    cliff_edge_layers.resize(MAX_ELEVATION)
    elevated_layers.resize(MAX_ELEVATION)
    decoration_layers.resize(MAX_ELEVATION + 1)
    organic_cliff_mesh_layers.resize(MAX_ELEVATION)
    organic_cliff_edge_mesh_layers.resize(MAX_ELEVATION)
    organic_cliff_shadow_mesh_layers.resize(MAX_ELEVATION)
    _active_max_elevation = clampi(initial_max_elevation, 0, MAX_ELEVATION)
    for elevation in range(1, _active_max_elevation + 1):
        _ensure_height_layers(elevation)
    if profiling_enabled:
        profile_layer_creation_usec = Time.get_ticks_usec() - profile_start


func rebuild() -> void:
    profile_sampling_usec = 0
    profile_mask_usec = 0
    profile_tile_placement_usec = 0
    for local_y in range(CHUNK_SIZE):
        for local_x in range(CHUNK_SIZE):
            var local_pos := Vector2i(local_x, local_y)
            _refresh_local_dual_cell(local_pos)
            _refresh_local_cliff_cell(local_pos)
            _refresh_local_decoration_cell(local_pos)


func populate_prepared_quantum(
        slot_sources: PackedInt32Array,
        slot_masks: PackedByteArray,
        elevated_slot_sources: PackedInt32Array,
        elevated_slot_masks: PackedByteArray,
        cliff_sources: PackedInt32Array,
        cliff_variants: PackedByteArray,
        cliff_owner_heights: PackedByteArray,
        cliff_edge_sources: PackedInt32Array,
        cliff_edge_masks: PackedByteArray,
        cliff_edge_heights: PackedByteArray,
        cliff_edge_styles: PackedByteArray,
        cliff_edge_drops: PackedByteArray,
        start_index: int,
        max_cells: int) -> int:
    var cell_count: int = CHUNK_SIZE * CHUNK_SIZE
    var end_index: int = mini(start_index + max_cells, cell_count)
    for cell_index in range(start_index, end_index):
        var local_pos := Vector2i(cell_index % CHUNK_SIZE, floori(float(cell_index) / CHUNK_SIZE))
        for depth in range(SLOT_COUNT):
            var slot_index: int = depth * cell_count + cell_index
            var source_id: int = slot_sources[slot_index]
            if source_id >= 0:
                layers[depth].set_cell(local_pos, source_id, _atlas_pos(slot_masks[slot_index]))
        for elevation in range(1, _active_max_elevation + 1):
            for depth in range(SLOT_COUNT):
                var slot_index: int = (
                    ((elevation - 1) * SLOT_COUNT + depth) * cell_count + cell_index)
                var source_id: int = elevated_slot_sources[slot_index]
                if source_id >= 0:
                    _ensure_height_layers(elevation)
                    var surface_group: Array = elevated_layers[elevation - 1]
                    surface_group[depth].set_cell(
                        local_pos, source_id, _atlas_pos(elevated_slot_masks[slot_index]))
        var owner_height: int = int(cliff_owner_heights[cell_index])
        if owner_height > 0:
            _ensure_height_layers(owner_height)
            for level in range(MAX_ELEVATION):
                var cliff_index: int = level * cell_count + cell_index
                var cliff_source: int = cliff_sources[cliff_index]
                if cliff_source >= 0:
                    var cliff_pos := Vector2i(local_pos.x, local_pos.y * 2 + 1 - level)
                    cliff_layers[owner_height - 1].set_cell(
                        cliff_pos, cliff_source, Vector2i(cliff_variants[cliff_index], 0))
            var south_height: int = owner_height
            for level in range(MAX_ELEVATION):
                if cliff_sources[level * cell_count + cell_index] >= 0:
                    south_height = mini(south_height, level)
            var global_pos: Vector2i = chunk_coord * CHUNK_SIZE + local_pos
            var south_is_liquid: bool = bool(liquid_by_id.get(
                int(_world_lookup.call(global_pos + Vector2i.DOWN)), false))
            if south_height < owner_height and not south_is_liquid:
                var shadow_index: int = south_height * cell_count + cell_index
                var shadow_pos := Vector2i(local_pos.x, local_pos.y * 2 + 2 - south_height)
                cliff_shadow_layers[owner_height - 1].set_cell(
                    shadow_pos, cliff_sources[shadow_index],
                    Vector2i(cliff_variants[shadow_index], 1))
        var edge_height: int = int(cliff_edge_heights[cell_index])
        if edge_height > 0:
            _ensure_height_layers(edge_height)
            cliff_edge_layers[edge_height - 1].set_cell(
                local_pos, cliff_edge_sources[cell_index],
                Vector2i(
                    cliff_edge_masks[cell_index],
                    TerrainChunkBuildJob.cliff_edge_variant(
                        int(cliff_edge_styles[cell_index]),
                        int(cliff_edge_drops[cell_index]))))
    return end_index - start_index


func populate_prepared_decoration_quantum(
        decoration_ids: PackedInt32Array,
        decoration_variants: PackedByteArray,
        decoration_heights: PackedByteArray,
        start_index: int,
        max_cells: int) -> int:
    var cell_count: int = CHUNK_SIZE * CHUNK_SIZE
    var end_index: int = mini(start_index + max_cells, cell_count)
    for cell_index in range(start_index, end_index):
        var decoration_id: int = int(decoration_ids[cell_index])
        if decoration_id < 0:
            continue
        var decoration_height: int = int(decoration_heights[cell_index])
        _ensure_decoration_layer(decoration_height)
        decoration_layers[decoration_height].set_cell(
            Vector2i(cell_index % CHUNK_SIZE, floori(float(cell_index) / CHUNK_SIZE)),
            0,
            Vector2i(
                int(_decoration_atlas_by_id[decoration_id])
                    + int(decoration_variants[cell_index]),
                0))
    return end_index - start_index


func refresh_global_dual_cell(global_dual_pos: Vector2i) -> void:
    var local_pos: Vector2i = global_dual_pos - chunk_coord * CHUNK_SIZE
    if _contains_local(local_pos):
        _refresh_local_dual_cell(local_pos)


func refresh_global_cliff_cell(global_cell: Vector2i) -> void:
    var local_pos: Vector2i = global_cell - chunk_coord * CHUNK_SIZE
    if _contains_local(local_pos):
        _refresh_local_cliff_cell(local_pos)


func refresh_global_decoration_cell(
        global_cell: Vector2i, sample_cache: Dictionary = {}) -> void:
    var local_pos: Vector2i = global_cell - chunk_coord * CHUNK_SIZE
    if _contains_local(local_pos):
        _refresh_local_decoration_cell(local_pos, sample_cache)


func set_decorations_visible(visible_value: bool) -> void:
    _decorations_visible = visible_value
    for layer in decoration_layers:
        if layer != null:
            layer.visible = visible_value


func get_decoration_count() -> int:
    var count: int = 0
    for layer in decoration_layers:
        if layer != null:
            count += layer.get_used_cells().size()
    return count


func rebuild_organic_cliffs() -> void:
    ## Rebuilds at chunk granularity. This keeps edit invalidation simple and
    ## guarantees that no cell or cliff segment owns an individual node.
    organic_cliff_geometry_usec = 0
    organic_cliff_face_count = 0
    organic_cliff_vertex_count = 0
    organic_cliff_triangle_count = 0
    organic_cliff_edge_component_count = 0
    organic_cliff_shadow_count = 0
    organic_cliff_height_query_count = 0
    organic_cliff_material_query_count = 0
    for mesh_layers in [
            organic_cliff_mesh_layers,
            organic_cliff_edge_mesh_layers,
            organic_cliff_shadow_mesh_layers]:
        for layer in mesh_layers:
            if layer != null:
                layer.mesh = null
                layer.visible = false
    _set_legacy_cliff_faces_visible(not _organic_cliff_geometry_enabled)
    _update_cliff_component_visibility()
    if not _organic_cliff_geometry_enabled:
        return
    # Synchronous rebuilds are retained for direct/test callers and use the
    # same Phase 3D mode as scheduled builds.
    var result: Dictionary = OrganicCliffMeshBuilder.build(
        chunk_coord, MAX_ELEVATION, _organic_cliff_world_seed,
        _world_lookup, _height_lookup, liquid_by_id,
        _unified_cliff_components_enabled, _refined_cliff_silhouettes_enabled,
        _connected_cliff_contours_enabled)
    organic_cliff_geometry_usec = int(result.build_usec)
    organic_cliff_face_count = int(result.face_count)
    organic_cliff_vertex_count = int(result.vertex_count)
    organic_cliff_triangle_count = int(result.triangle_count)
    organic_cliff_edge_component_count = int(result.edge_component_count)
    organic_cliff_shadow_count = int(result.shadow_count)
    organic_cliff_height_query_count = int(result.height_query_count)
    organic_cliff_material_query_count = int(result.material_query_count)
    _assign_organic_meshes(result.meshes, organic_cliff_mesh_layers, -2, "OrganicCliffsHeight")
    if _unified_cliff_components_enabled:
        _assign_organic_meshes(
            result.edge_meshes, organic_cliff_edge_mesh_layers, 4,
            "OrganicCliffEdgesHeight")
        _assign_organic_meshes(
            result.shadow_meshes, organic_cliff_shadow_mesh_layers, -3,
            "OrganicCliffShadowsHeight")
    _organic_geometry_ready = true
    _set_legacy_cliff_faces_visible(false)
    _update_cliff_component_visibility()


func apply_prepared_organic_cliffs(result: Dictionary) -> int:
    ## Commits a complete replacement batch atomically on the main thread.
    ## Existing meshes remain visible while preparation is pending.
    var started_usec: int = Time.get_ticks_usec()
    _organic_geometry_ready = false
    for mesh_layers in [
            organic_cliff_mesh_layers,
            organic_cliff_edge_mesh_layers,
            organic_cliff_shadow_mesh_layers]:
        for layer in mesh_layers:
            if layer != null:
                layer.visible = false
                layer.mesh = null
    organic_cliff_geometry_usec = int(result.get("build_usec", 0))
    organic_cliff_face_count = int(result.get("face_count", 0))
    organic_cliff_vertex_count = int(result.get("vertex_count", 0))
    organic_cliff_triangle_count = int(result.get("triangle_count", 0))
    organic_cliff_edge_component_count = int(result.get("edge_component_count", 0))
    organic_cliff_shadow_count = int(result.get("shadow_count", 0))
    organic_cliff_height_query_count = int(result.get("height_query_count", 0))
    organic_cliff_material_query_count = int(result.get("material_query_count", 0))
    organic_cliff_sampling_usec = int(result.get("sampling_usec", 0))
    organic_cliff_face_construction_usec = int(result.get("face_construction_usec", 0))
    organic_cliff_contour_generation_usec = int(result.get("contour_generation_usec", 0))
    organic_cliff_vertex_assembly_usec = int(result.get("vertex_assembly_usec", 0))
    organic_cliff_mesh_resource_usec = int(result.get("mesh_resource_usec", 0))
    _assign_organic_meshes(
        result.get("meshes", []), organic_cliff_mesh_layers, -2,
        "OrganicCliffsHeight")
    if _unified_cliff_components_enabled:
        _assign_organic_meshes(
            result.get("edge_meshes", []), organic_cliff_edge_mesh_layers, 4,
            "OrganicCliffEdgesHeight")
        _assign_organic_meshes(
            result.get("shadow_meshes", []), organic_cliff_shadow_mesh_layers, -3,
            "OrganicCliffShadowsHeight")
    _organic_geometry_ready = true
    _set_legacy_cliff_faces_visible(not _organic_cliff_geometry_enabled)
    _update_cliff_component_visibility()
    organic_cliff_scene_attachment_usec = Time.get_ticks_usec() - started_usec
    return organic_cliff_scene_attachment_usec


func mark_organic_cliff_geometry_pending() -> void:
    ## A setting change cannot display a batch prepared for a different mode.
    ## Legacy batched cliff art remains available until the new batch commits.
    _organic_geometry_ready = false
    _set_legacy_cliff_faces_visible(true)
    _update_cliff_component_visibility()


func set_organic_cliff_geometry_enabled(enabled: bool) -> void:
    if _organic_cliff_geometry_enabled == enabled:
        return
    _organic_cliff_geometry_enabled = enabled
    if not enabled:
        _set_legacy_cliff_faces_visible(true)
    _update_cliff_component_visibility()


func set_unified_cliff_components_enabled(enabled: bool) -> void:
    if _unified_cliff_components_enabled == enabled:
        return
    _unified_cliff_components_enabled = enabled
    mark_organic_cliff_geometry_pending()


func set_refined_cliff_silhouettes_enabled(enabled: bool) -> void:
    if _refined_cliff_silhouettes_enabled == enabled:
        return
    _refined_cliff_silhouettes_enabled = enabled
    mark_organic_cliff_geometry_pending()


func set_connected_cliff_contours_enabled(enabled: bool) -> void:
    if _connected_cliff_contours_enabled == enabled:
        return
    _connected_cliff_contours_enabled = enabled
    mark_organic_cliff_geometry_pending()


func set_cliff_edge_overlays_visible(visible_value: bool) -> void:
    _cliff_edge_overlays_visible = visible_value
    _update_cliff_component_visibility()


func set_cliff_shadows_visible(visible_value: bool) -> void:
    _cliff_shadows_visible = visible_value
    _update_cliff_component_visibility()


func is_organic_cliff_geometry_enabled() -> bool:
    return _organic_cliff_geometry_enabled


func is_unified_cliff_components_enabled() -> bool:
    return _unified_cliff_components_enabled


func is_refined_cliff_silhouettes_enabled() -> bool:
    return _refined_cliff_silhouettes_enabled


func is_connected_cliff_contours_enabled() -> bool:
    return _connected_cliff_contours_enabled


func get_organic_cliff_geometry_stats() -> Dictionary:
    var mesh_count: int = 0
    for layer in organic_cliff_mesh_layers:
        if layer != null and layer.mesh != null:
            mesh_count += 1
    return {
        "build_usec": organic_cliff_geometry_usec,
        "face_count": organic_cliff_face_count,
        "vertex_count": organic_cliff_vertex_count,
        "triangle_count": organic_cliff_triangle_count,
        "mesh_count": mesh_count,
        "edge_component_count": organic_cliff_edge_component_count,
        "shadow_count": organic_cliff_shadow_count,
        "edge_mesh_count": _mesh_count(organic_cliff_edge_mesh_layers),
        "shadow_mesh_count": _mesh_count(organic_cliff_shadow_mesh_layers),
        "height_query_count": organic_cliff_height_query_count,
        "material_query_count": organic_cliff_material_query_count,
        "sampling_usec": organic_cliff_sampling_usec,
        "face_construction_usec": organic_cliff_face_construction_usec,
        "contour_generation_usec": organic_cliff_contour_generation_usec,
        "vertex_assembly_usec": organic_cliff_vertex_assembly_usec,
        "mesh_resource_usec": organic_cliff_mesh_resource_usec,
        "scene_attachment_usec": organic_cliff_scene_attachment_usec,
    }


func _refresh_local_dual_cell(local_pos: Vector2i) -> void:
    var global_pos: Vector2i = chunk_coord * CHUNK_SIZE + local_pos
    var corners: Array[int] = []
    var corner_heights: Array[int] = []
    var phase_start: int = Time.get_ticks_usec() if profiling_enabled else 0
    for offset in CORNER_OFFSETS:
        corners.append(int(_world_lookup.call(global_pos + offset)))
        corner_heights.append(int(_height_lookup.call(global_pos + offset)))
    if profiling_enabled:
        profile_sampling_usec += Time.get_ticks_usec() - phase_start
        phase_start = Time.get_ticks_usec()

    _erase_surface_cell(local_pos)
    _place_ground_surface(local_pos, corners, corner_heights)
    _place_elevated_surfaces(local_pos, corners, corner_heights)
    if profiling_enabled:
        profile_mask_usec += Time.get_ticks_usec() - phase_start


func _place_ground_surface(
        local_pos: Vector2i, corners: Array[int], corner_heights: Array[int]) -> void:
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
        layers[depth].set_cell(local_pos, terrain_id, _atlas_pos(bitmask))


func _place_elevated_surfaces(
        local_pos: Vector2i, corners: Array[int], corner_heights: Array[int]) -> void:
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
        _ensure_height_layers(elevation)
        var surface_group: Array = elevated_layers[elevation - 1]
        for depth in range(ids_at_height.size()):
            var terrain_id: int = ids_at_height[depth]
            var cutoff_priority: int = int(priority_by_id[terrain_id])
            var bitmask: int = 0
            for corner_index in range(4):
                if (corner_heights[corner_index] == elevation
                        and int(priority_by_id[corners[corner_index]]) >= cutoff_priority):
                    bitmask |= (8 >> corner_index)
            surface_group[depth].set_cell(local_pos, terrain_id, _atlas_pos(bitmask))


func _refresh_local_cliff_cell(local_pos: Vector2i) -> void:
    for elevation_index in range(MAX_ELEVATION):
        var cliff_layer = cliff_layers[elevation_index]
        var shadow_layer = cliff_shadow_layers[elevation_index]
        var edge_layer = cliff_edge_layers[elevation_index]
        if edge_layer != null:
            edge_layer.erase_cell(local_pos)
        if cliff_layer == null:
            continue
        for level in range(MAX_ELEVATION):
            cliff_layer.erase_cell(Vector2i(local_pos.x, local_pos.y * 2 + 1 - level))
            shadow_layer.erase_cell(Vector2i(local_pos.x, local_pos.y * 2 + 2 - level))

    var global_pos: Vector2i = chunk_coord * CHUNK_SIZE + local_pos
    var elevation: int = int(_height_lookup.call(global_pos))
    var owner_is_liquid: bool = _is_liquid_at(global_pos)
    if elevation > 0 and not owner_is_liquid:
        var north_pos: Vector2i = global_pos + Vector2i.UP
        var west_pos: Vector2i = global_pos + Vector2i.LEFT
        var east_pos: Vector2i = global_pos + Vector2i.RIGHT
        var south_pos: Vector2i = global_pos + Vector2i.DOWN
        var classification: Vector4i = TerrainChunkBuildJob.classify_cliff_edge_values(
            elevation, int(_world_lookup.call(global_pos)),
            int(_height_lookup.call(north_pos)), int(_height_lookup.call(east_pos)),
            int(_height_lookup.call(south_pos)), int(_height_lookup.call(west_pos)),
            int(_height_lookup.call(global_pos + Vector2i(1, -1))),
            int(_height_lookup.call(global_pos + Vector2i(1, 1))),
            int(_height_lookup.call(global_pos + Vector2i(-1, 1))),
            int(_height_lookup.call(global_pos + Vector2i(-1, -1))),
            int(_world_lookup.call(north_pos)), int(_world_lookup.call(east_pos)),
            int(_world_lookup.call(south_pos)), int(_world_lookup.call(west_pos)),
            liquid_by_id)
        var edge_mask: int = classification.x
        if (edge_mask & 7) != 0:
            _ensure_height_layers(elevation)
            var edge_terrain_id: int = int(_world_lookup.call(global_pos))
            var edge_source: int = _cliff_source_for(
                edge_terrain_id,
                (classification.z & TerrainChunkBuildJob.EDGE_FLAG_WATER_CONTACT) != 0)
            cliff_edge_layers[elevation - 1].set_cell(
                local_pos, edge_source,
                Vector2i(
                    edge_mask,
                    TerrainChunkBuildJob.cliff_edge_variant(
                        classification.y, classification.w)))
    var south_elevation: int = int(_height_lookup.call(global_pos + Vector2i.DOWN))
    if owner_is_liquid or elevation <= south_elevation:
        return
    _ensure_height_layers(elevation)
    var terrain_id: int = int(_world_lookup.call(global_pos))
    var south_is_liquid: bool = _is_liquid_at(global_pos + Vector2i.DOWN)
    var cliff_source: int = _cliff_source_for(terrain_id, south_is_liquid)
    for level in range(south_elevation, elevation):
        var left_exposed: bool = _global_neighbor_has_cliff(global_pos + Vector2i.LEFT, level)
        var right_exposed: bool = _global_neighbor_has_cliff(global_pos + Vector2i.RIGHT, level)
        var cap_mask: int = (0 if left_exposed else 1) | (0 if right_exposed else 2)
        var top_step: bool = level == elevation - 1
        var variant: int = (
            _cliff_style(global_pos) * 8
            + (4 if top_step else 0)
            + cap_mask)
        var cliff_pos := Vector2i(local_pos.x, local_pos.y * 2 + 1 - level)
        cliff_layers[elevation - 1].set_cell(cliff_pos, cliff_source, Vector2i(variant, 0))
    var shadow_cap_mask: int = (
        (0 if _global_neighbor_has_cliff(global_pos + Vector2i.LEFT, south_elevation) else 1)
        | (0 if _global_neighbor_has_cliff(global_pos + Vector2i.RIGHT, south_elevation) else 2))
    var shadow_variant: int = _cliff_style(global_pos) * 8 + shadow_cap_mask
    var shadow_pos := Vector2i(local_pos.x, local_pos.y * 2 + 2 - south_elevation)
    if not south_is_liquid:
        cliff_shadow_layers[elevation - 1].set_cell(
            shadow_pos, cliff_source, Vector2i(shadow_variant, 1))


func _refresh_local_decoration_cell(
        local_pos: Vector2i, sample_cache: Dictionary = {}) -> void:
    for layer in decoration_layers:
        if layer != null:
            layer.erase_cell(local_pos)
    var global_pos: Vector2i = chunk_coord * CHUNK_SIZE + local_pos
    if not bool(_decoration_context.get("generation_enabled", true)):
        return
    if _environment_occupancy_lookup.is_valid() and bool(
            _environment_occupancy_lookup.call(global_pos)):
        return
    var material_samples: Dictionary = sample_cache.get("materials", {})
    var ground_samples: Dictionary = sample_cache.get("ground", {})
    var surface_samples: Dictionary = sample_cache.get("surface", {})
    var north_pos := global_pos + Vector2i.UP
    var east_pos := global_pos + Vector2i.RIGHT
    var south_pos := global_pos + Vector2i.DOWN
    var west_pos := global_pos + Vector2i.LEFT
    var terrain_id: int
    var ground_height: int
    var surface_height: int
    var north_id: int
    var east_id: int
    var south_id: int
    var west_id: int
    var north_height: int
    var east_height: int
    var south_height: int
    var west_height: int
    if sample_cache.is_empty():
        terrain_id = int(_world_lookup.call(global_pos))
        ground_height = int(_ground_height_lookup.call(global_pos))
        surface_height = int(_height_lookup.call(global_pos))
        north_id = int(_world_lookup.call(north_pos))
        east_id = int(_world_lookup.call(east_pos))
        south_id = int(_world_lookup.call(south_pos))
        west_id = int(_world_lookup.call(west_pos))
        north_height = int(_height_lookup.call(north_pos))
        east_height = int(_height_lookup.call(east_pos))
        south_height = int(_height_lookup.call(south_pos))
        west_height = int(_height_lookup.call(west_pos))
    else:
        terrain_id = int(material_samples[global_pos])
        ground_height = int(ground_samples[global_pos])
        surface_height = int(surface_samples[global_pos])
        north_id = int(material_samples[north_pos])
        east_id = int(material_samples[east_pos])
        south_id = int(material_samples[south_pos])
        west_id = int(material_samples[west_pos])
        north_height = int(surface_samples[north_pos])
        east_height = int(surface_samples[east_pos])
        south_height = int(surface_samples[south_pos])
        west_height = int(surface_samples[west_pos])
    var selection: Vector2i = DecorationPlacement.choose(
        global_pos,
        terrain_id,
        ground_height,
        surface_height,
        north_id, east_id, south_id, west_id,
        north_height, east_height, south_height, west_height,
        _decoration_context["definitions"],
        _decoration_context["indices_by_material"],
        _decoration_context["max_density_by_material"],
        liquid_by_id,
        int(_decoration_context["seed"]),
        float(_decoration_context["density"]),
        float(_decoration_context["clustering"]))
    if selection.x < 0:
        return
    _ensure_decoration_layer(surface_height)
    decoration_layers[surface_height].set_cell(
        local_pos, 0,
        Vector2i(
            int(_decoration_atlas_by_id[selection.x]) + selection.y,
            0))


func _global_neighbor_has_cliff(world_pos: Vector2i, level: int) -> bool:
    var elevation: int = int(_height_lookup.call(world_pos))
    var south_elevation: int = int(_height_lookup.call(world_pos + Vector2i.DOWN))
    return south_elevation <= level and elevation > level


func _is_liquid_at(world_pos: Vector2i) -> bool:
    return bool(liquid_by_id.get(int(_world_lookup.call(world_pos)), false))


static func _cliff_source_for(terrain_id: int, shoreline: bool) -> int:
    var stone_style: bool = terrain_id in [4, 5, 7]
    return (2 if shoreline else 0) + (1 if stone_style else 0)


func _erase_surface_cell(local_pos: Vector2i) -> void:
    for layer in layers:
        layer.erase_cell(local_pos)
    for surface_group in elevated_layers:
        if surface_group == null:
            continue
        for layer in surface_group:
            layer.erase_cell(local_pos)


func _sorted_unique_ids(corners: Array[int]) -> Array[int]:
    var unique_ids: Array[int] = []
    for terrain_id in corners:
        if not unique_ids.has(terrain_id):
            unique_ids.append(terrain_id)
    unique_ids.sort_custom(func(a: int, b: int) -> bool:
        return int(priority_by_id[a]) < int(priority_by_id[b]))
    return unique_ids


func _create_layer(layer_name: String, shared_tileset: TileSet) -> TileMapLayer:
    var layer := TileMapLayer.new()
    layer.name = layer_name
    layer.tile_set = shared_tileset
    layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    add_child(layer)
    return layer


func _ensure_height_layers(elevation: int) -> void:
    var index: int = elevation - 1
    if index < 0 or index >= MAX_ELEVATION or cliff_layers[index] != null:
        return
    _active_max_elevation = maxi(_active_max_elevation, elevation)
    var shadow_layer := _create_layer("CliffShadowsHeight_%d" % elevation, _cliff_tileset)
    shadow_layer.z_index = elevation * 8 - 3
    shadow_layer.visible = _legacy_cliff_components_visible() and _cliff_shadows_visible
    cliff_shadow_layers[index] = shadow_layer
    var cliff_layer := _create_layer("CliffsHeight_%d" % elevation, _cliff_tileset)
    cliff_layer.z_index = elevation * 8 - 2
    cliff_layer.visible = not _organic_cliff_geometry_enabled
    cliff_layers[index] = cliff_layer
    var edge_layer := _create_layer("CliffEdgesHeight_%d" % elevation, _cliff_edge_tileset)
    edge_layer.position = Vector2(0.0, -elevation * HEIGHT_STEP)
    # Crisp ledge lips sit above this elevation's four surface layers. The next
    # elevation band still occludes them where projected surfaces overlap.
    edge_layer.z_index = elevation * 8 + 4
    edge_layer.visible = _legacy_cliff_components_visible() and _cliff_edge_overlays_visible
    cliff_edge_layers[index] = edge_layer
    var surface_group: Array[TileMapLayer] = []
    for depth in range(SLOT_COUNT):
        var surface_layer := _create_layer(
            "SurfaceHeight_%dDepth_%d" % [elevation, depth], _surface_tileset)
        surface_layer.position = Vector2(
            -TILE_SIZE.x / 2.0,
            -TILE_SIZE.y / 2.0 - elevation * HEIGHT_STEP)
        surface_layer.z_index = elevation * 8 + depth
        surface_group.append(surface_layer)
    elevated_layers[index] = surface_group
    _ensure_decoration_layer(elevation)


func _ensure_organic_cliff_mesh_layer(elevation: int) -> MeshInstance2D:
    var index: int = elevation - 1
    if organic_cliff_mesh_layers[index] != null:
        return organic_cliff_mesh_layers[index]
    var layer := MeshInstance2D.new()
    layer.name = "OrganicCliffsHeight_%d" % elevation
    layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    layer.z_index = elevation * 8 - 2
    layer.material = _organic_cliff_material
    add_child(layer)
    organic_cliff_mesh_layers[index] = layer
    return layer


func _assign_organic_meshes(
        meshes: Array, mesh_layers: Array, z_offset: int,
        layer_prefix: String) -> void:
    for index in range(meshes.size()):
        if meshes[index] == null:
            continue
        var layer: MeshInstance2D = _ensure_organic_component_mesh_layer(
            mesh_layers, index, z_offset, layer_prefix)
        layer.mesh = meshes[index]
        layer.visible = false


func _ensure_organic_component_mesh_layer(
        mesh_layers: Array, index: int, z_offset: int,
        layer_prefix: String) -> MeshInstance2D:
    if mesh_layers[index] != null:
        return mesh_layers[index]
    var layer := MeshInstance2D.new()
    layer.name = "%s_%d" % [layer_prefix, index + 1]
    layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    layer.z_index = (index + 1) * 8 + z_offset
    layer.material = _organic_cliff_material
    add_child(layer)
    mesh_layers[index] = layer
    return layer


func _mesh_count(mesh_layers: Array) -> int:
    var count: int = 0
    for layer in mesh_layers:
        if layer != null and layer.mesh != null:
            count += 1
    return count


func _legacy_cliff_components_visible() -> bool:
    return not (_organic_cliff_geometry_enabled and _organic_geometry_ready
        and _unified_cliff_components_enabled)


func _update_cliff_component_visibility() -> void:
    var show_legacy: bool = _legacy_cliff_components_visible()
    for layer in cliff_edge_layers:
        if layer != null:
            layer.visible = show_legacy and _cliff_edge_overlays_visible
    for layer in cliff_shadow_layers:
        if layer != null:
            layer.visible = show_legacy and _cliff_shadows_visible
    var show_organic: bool = _organic_cliff_geometry_enabled and _organic_geometry_ready
    for layer in organic_cliff_mesh_layers:
        if layer != null:
            layer.visible = show_organic and layer.mesh != null
    for layer in organic_cliff_edge_mesh_layers:
        if layer != null:
            layer.visible = (show_organic and _unified_cliff_components_enabled
                and _cliff_edge_overlays_visible and layer.mesh != null)
    for layer in organic_cliff_shadow_mesh_layers:
        if layer != null:
            layer.visible = (show_organic and _unified_cliff_components_enabled
                and _cliff_shadows_visible and layer.mesh != null)


func _set_legacy_cliff_faces_visible(visible_value: bool) -> void:
    for layer in cliff_layers:
        if layer != null:
            layer.visible = visible_value


func _ensure_decoration_layer(elevation: int) -> void:
    if elevation < 0 or elevation > MAX_ELEVATION:
        return
    if decoration_layers[elevation] != null:
        return
    var layer := _create_layer(
        "DecorationsHeight_%d" % elevation, _decoration_tileset)
    layer.position = Vector2(0.0, -elevation * HEIGHT_STEP)
    layer.z_index = 4 if elevation == 0 else elevation * 8 + 5
    layer.visible = _decorations_visible
    decoration_layers[elevation] = layer


func _contains_local(local_pos: Vector2i) -> bool:
    return (local_pos.x >= 0 and local_pos.y >= 0
        and local_pos.x < CHUNK_SIZE and local_pos.y < CHUNK_SIZE)


static func _atlas_pos(mask: int) -> Vector2i:
    return Vector2i(mask & 3, mask >> 2)


static func _cliff_style(world_pos: Vector2i) -> int:
    return posmod(world_pos.x * 17 + world_pos.y * 31, 4)

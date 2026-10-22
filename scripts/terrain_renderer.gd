extends Node2D
## Streams visual chunks around a supplied visible world rectangle. This node
## owns the shared masked atlases; TerrainWorld owns authoritative mutable data.

signal authoritative_state_changed
signal cliff_height_profile_changed(height_step: int)

const Catalog = preload("res://scripts/terrain_catalog.gd")
const TerrainGenerator = preload("res://scripts/terrain_generator.gd")
const TerrainWorld = preload("res://scripts/terrain_world.gd")
const TerrainChunkRenderer = preload("res://scripts/terrain_chunk_renderer.gd")
const TerrainChunkBuildJob = preload("res://scripts/terrain_chunk_build_job.gd")
const DecorationCatalog = preload("res://scripts/decoration_catalog.gd")
const EnvironmentObjectCatalog = preload("res://scripts/environment_object_catalog.gd")
const EnvironmentObjectPlacement = preload("res://scripts/environment_object_placement.gd")
const EnvironmentObjectRenderer = preload("res://scripts/environment_object_renderer.gd")
const ResourceStateManager = preload("res://scripts/resource_state_manager.gd")
const TerrainSurfaceFactory = preload("res://scripts/terrain_surface_factory.gd")
const CliffResourceFactory = preload("res://scripts/cliff_resource_factory.gd")
const TerrainDetailAtlasFactory = preload("res://scripts/terrain_detail_atlas_factory.gd")

const TILE_SIZE: Vector2i = Vector2i(32, 32)
const CHUNK_SIZE: int = 32
const HEIGHT_STEP: int = 16
const MODERATE_HEIGHT_STEP: int = 24
const PROMINENT_HEIGHT_STEP: int = 32
const MAX_ELEVATION: int = TerrainWorld.MAX_ELEVATION
const STAGED_EDIT_THRESHOLD: int = 96
const STAGED_EDIT_CELLS_PER_FRAME: int = 32

enum CliffHeightProfile {
	BASELINE,
	MODERATE,
	PROMINENT,
}

var world_seed: int = 84521
var biome_frequency: float = 0.012
var detail_frequency: float = 0.055
var include_origin_demo: bool = true
var procedural_elevation_enabled: bool = true
var max_generated_elevation: int = 3
var elevation_frequency: float = 0.006
var elevation_detail_frequency: float = 0.021
var elevation_detail_strength: float = 0.14
var elevation_threshold_1: float = -0.12
var elevation_threshold_2: float = 0.16
var elevation_threshold_3: float = 0.43
var elevation_flatness_bias: float = 0.02
var sea_level: int = 0
var load_margin_chunks: int = 1
var unload_margin_chunks: int = 2
var chunks_created_per_frame: int = 2
var max_chunk_processing_ms: float = 2.5
var chunk_work_quantum_cells: int = 24
var max_tile_cells_per_frame: int = 256
var max_chunk_retirements_per_frame: int = 1
var max_chunk_retirement_nodes_per_frame: int = 8
var incremental_chunk_retirement_enabled: bool = true
var texture_variation_enabled: bool = true
var texture_variation_strength: float = 0.65
var texture_variation_frequency: float = 0.0025
var clustered_grass_detail_enabled: bool = true
var grass_clear_area_coverage: float = 0.70
var grass_detail_density: float = 0.35
var grass_cluster_scale: float = 0.004
var grass_transition_softness: float = 0.12
var grass_clear_area_residual_density: float = 0.04
var grass_detail_seed_offset: int = 48131
var organic_grass_color_variation_enabled: bool = true
var grass_broad_variation_scale: float = 0.0015
var grass_color_variation_strength: float = 0.055
var grass_fine_variation_strength: float = 0.018
var grass_texture_repetition_correction_enabled: bool = true
var terrain_texture_repetition_correction_enabled: bool = true
var terrain_texture_repetition_material_settings: Dictionary = {
	1: {"enabled": true, "strength": 0.55},
	2: {"enabled": true, "strength": 0.65},
	4: {"enabled": true, "strength": 0.55},
	5: {"enabled": false, "strength": 0.35},
	6: {"enabled": true, "strength": 0.65},
	7: {"enabled": false, "strength": 0.35},
}
var stochastic_terrain_detail_enabled: bool = true
var stochastic_terrain_detail_material_settings: Dictionary = {
	1: {"enabled": true, "intensity": 0.95},
	2: {"enabled": true, "intensity": 1.0},
	4: {"enabled": true, "intensity": 1.0},
	6: {"enabled": true, "intensity": 1.0},
}
var remaining_terrain_detail_enabled: bool = true
var remaining_terrain_detail_material_settings: Dictionary = {
	5: {"enabled": true, "strength": 0.90},
	7: {"enabled": true, "strength": 1.0},
}
var water_repetition_correction_enabled: bool = true
var water_repetition_correction_strength: float = 1.0
var cliff_repetition_correction_enabled: bool = true
var cliff_repetition_correction_strength: float = 0.95
var organic_boundaries_enabled: bool = true
var organic_edge_strength: float = 0.08
var organic_edge_frequency: float = 0.035
var experimental_water_enhancement_enabled: bool = false
var water_ripple_strength: float = 0.32
var water_secondary_ripple_scale: float = 2.4
var water_ripple_drift_speed: float = 0.55
var water_glint_density: float = 0.14
var water_glint_brightness: float = 0.38
var procedural_cliff_materials_enabled: bool = true
var organic_cliff_geometry_enabled: bool = false
var unified_cliff_components_enabled: bool = false
var refined_cliff_silhouettes_enabled: bool = false
var connected_cliff_contours_enabled: bool = false
var unified_cliff_contours_enabled: bool = false
var directional_cliff_projection_enabled: bool = false
var cliff_height_profile: int = CliffHeightProfile.BASELINE
var cliff_edge_overlays_visible: bool = true
var cliff_shadows_visible: bool = true
var profiling_enabled: bool = false
var decorations_enabled: bool = true
var decoration_density: float = 1.0
var decoration_clustering_strength: float = 0.72
var decoration_seed_offset: int = 63017
var decoration_generation_enabled: bool = true # Benchmark-only bypass; normal play keeps generation enabled.
var environment_objects_enabled: bool = true
var procedural_vegetation_enabled: bool = true
var environment_object_generation_enabled: bool = true # Benchmark-only bypass.
var environment_object_density: float = 1.0
var environment_object_seed_offset: int = 91423
var berry_regrowth_seconds: float = 120.0

var generator # TerrainGenerator instance; intentionally dynamically typed.
var world # TerrainWorld instance; intentionally dynamically typed.
var priority_by_id: Dictionary = {} # id -> int
var name_by_id: Dictionary = {} # id -> String
var liquid_by_id: Dictionary = {} # id -> bool material metadata
var render_tileset: TileSet
var cliff_tileset: TileSet
var cliff_edge_tileset: TileSet
var decoration_tileset: TileSet
var decoration_atlas_by_id: Dictionary = {} # decoration id -> first atlas column
var decoration_context: Dictionary = {}
var environment_object_atlas_texture: Texture2D
var environment_object_procedural_atlas_texture: Texture2D
var environment_object_legacy_tree_atlas_texture: Texture2D
var environment_object_atlas_by_id: Dictionary = {}
var environment_object_unripe_atlas_by_id: Dictionary = {}
var environment_object_context: Dictionary = {}
var environment_atlas_generation_usec: int = 0
var environment_legacy_atlas_generation_usec: int = 0
var environment_atlas_variant_count: int = 0
var environment_procedural_variant_count: int = 0
var environment_procedural_tree_variant_count: int = 0
var environment_atlas_dimensions := Vector2i.ZERO
var resource_state_manager
var environment_object_renderer # Global EnvironmentObjectRenderer presentation batch.
var loaded_chunks: Dictionary = {} # Vector2i -> TerrainChunkRenderer
var visual_material_by_id: Dictionary = {} # id -> shared ShaderMaterial
var variant_count_by_id: Dictionary = {} # id -> int
var cliff_material_by_source: Dictionary = {} # cliff source id -> shared ShaderMaterial
var cliff_shadow_material_by_source: Dictionary = {} # source id -> shared foot material
var organic_cliff_material: ShaderMaterial # Shared encoded-source mesh material.
var chunks_finalised_this_frame: int = 0
var last_chunk_total_usec: int = 0
var last_chunk_layer_creation_usec: int = 0
var last_chunk_sampling_usec: int = 0
var last_chunk_mask_usec: int = 0
var last_chunk_cliff_usec: int = 0
var last_chunk_liquid_surface_usec: int = 0
var last_chunk_cliff_edge_usec: int = 0
var last_chunk_organic_cliff_geometry_usec: int = 0
var last_chunk_organic_cliff_mesh_resource_usec: int = 0
var last_chunk_organic_cliff_scene_attachment_usec: int = 0
var last_chunk_decoration_usec: int = 0
var last_chunk_decoration_submission_usec: int = 0
var last_chunk_environment_usec: int = 0
var last_chunk_environment_submission_usec: int = 0
var last_chunk_tile_placement_usec: int = 0
var last_chunk_scene_insertion_usec: int = 0
var last_unload_usec: int = 0
var chunk_processing_usec_this_frame: int = 0
var organic_geometry_processing_usec_this_frame: int = 0
var worst_chunk_processing_frame_usec: int = 0
var worst_organic_geometry_processing_frame_usec: int = 0
var last_chunk_finalisation_usec: int = 0
var worst_chunk_finalisation_usec: int = 0
var total_profiled_chunks: int = 0
var profile_total_chunk_usec: int = 0
var profile_total_layer_creation_usec: int = 0
var profile_total_sampling_usec: int = 0
var profile_total_mask_usec: int = 0
var profile_total_cliff_usec: int = 0
var profile_total_liquid_surface_usec: int = 0
var profile_total_cliff_edge_usec: int = 0
var profile_total_organic_cliff_geometry_usec: int = 0
var profile_total_organic_cliff_mesh_resource_usec: int = 0
var profile_total_organic_cliff_scene_attachment_usec: int = 0
var profile_total_decoration_usec: int = 0
var profile_total_decoration_submission_usec: int = 0
var profile_total_environment_usec: int = 0
var profile_total_environment_submission_usec: int = 0
var profile_total_tile_placement_usec: int = 0
var profile_total_scene_insertion_usec: int = 0
var profile_total_unload_usec: int = 0
var last_chunk_retirement_usec: int = 0
var worst_chunk_retirement_usec: int = 0
var profile_total_chunk_retirement_usec: int = 0
var retired_chunks_total: int = 0
var peak_pending_chunk_retirements: int = 0
var profile_worst_chunk_usec: int = 0
var chunk_processing_overrun_frames: int = 0
var last_edit_dirty_cell_count: int = 0
var last_edit_dirty_chunk_count: int = 0
var last_edit_refresh_usec: int = 0
var last_edit_environment_refresh_usec: int = 0
var pending_edit_environment_chunks: Dictionary = {} # Vector2i -> true
var pending_edit_cells: Dictionary = {} # Vector2i -> true; visuals reread current authority

var _wanted_chunks: Dictionary = {} # Vector2i -> true
var _visible_chunks: Dictionary = {} # Vector2i -> true
var _pending_chunks: Array[Vector2i] = []
var _build_jobs: Dictionary = {} # Vector2i -> TerrainChunkBuildJob
var _organic_rebuild_jobs: Dictionary = {} # Vector2i -> organic-only TerrainChunkBuildJob
var _pending_organic_rebuild_chunks: Array[Vector2i] = []
var _organic_geometry_revisions: Dictionary = {} # Vector2i -> monotonically increasing int
var _organic_terrain_revisions: Dictionary = {} # Vector2i -> authoritative snapshot revision
var _organic_halo_cache: Dictionary = {} # Vector2i -> bounded loaded-chunk halo snapshot
var _pending_chunk_retirements: Array[Node] = [] # Hidden nodes awaiting bounded queue_free.
var _last_visible_chunk_min := Vector2i(2147483647, 2147483647)
var _last_visible_chunk_max := Vector2i(-2147483648, -2147483648)


func _ready() -> void:
	_build_shared_tileset()
	_build_shared_cliff_tileset()
	_build_shared_cliff_edge_tileset()
	_build_shared_decoration_tileset()
	decoration_context = {
		"definitions": DecorationCatalog.DEFINITIONS,
		"indices_by_material": DecorationCatalog.build_indices_by_material(),
		"max_density_by_material": DecorationCatalog.build_max_density_by_material(),
		"seed": world_seed + decoration_seed_offset,
		"density": decoration_density,
		"clustering": decoration_clustering_strength,
		"generation_enabled": decoration_generation_enabled,
	}
	_build_shared_environment_object_atlas()
	environment_object_context = {
		"definitions": EnvironmentObjectCatalog.DEFINITIONS,
		"definitions_by_id": EnvironmentObjectCatalog.build_by_id(),
		"indices_by_material": EnvironmentObjectCatalog.build_indices_by_material(),
		"max_density_by_material": EnvironmentObjectCatalog.build_max_density_by_material(),
		"liquid_by_id": liquid_by_id,
		"seed": world_seed + environment_object_seed_offset,
		"density": environment_object_density,
		"generation_enabled": environment_object_generation_enabled,
	}
	resource_state_manager = ResourceStateManager.new()
	resource_state_manager.configure(
		world_seed, environment_object_context["definitions_by_id"], berry_regrowth_seconds)
	resource_state_manager.resource_changed.connect(_on_resource_changed)
	environment_object_renderer = EnvironmentObjectRenderer.new()
	environment_object_renderer.name = "EnvironmentalObjectBatches"
	environment_object_renderer.configure(
		environment_object_context["definitions_by_id"],
		environment_object_atlas_texture,
		environment_object_atlas_by_id,
		environment_object_unripe_atlas_by_id)
	environment_object_renderer.set_height_step(get_cliff_height_step())
	environment_object_renderer.set_objects_visible(environment_objects_enabled)
	add_child(environment_object_renderer)
	generator = TerrainGenerator.new()
	generator.configure(world_seed, biome_frequency, detail_frequency, include_origin_demo)
	generator.configure_elevation(
		procedural_elevation_enabled, max_generated_elevation,
		elevation_frequency, elevation_detail_frequency,
		elevation_detail_strength, elevation_threshold_1,
		elevation_threshold_2, elevation_threshold_3,
		elevation_flatness_bias)
	world = TerrainWorld.new()
	world.configure(generator)


func _process(delta: float) -> void:
	resource_state_manager.advance_simulated_time(delta)
	_process_pending_chunk_retirements()
	chunks_finalised_this_frame = 0
	organic_geometry_processing_usec_this_frame = 0
	var processing_start: int = Time.get_ticks_usec()
	var deadline_usec: int = processing_start + roundi(maxf(0.1, max_chunk_processing_ms) * 1000.0)
	var tile_cells_remaining: int = maxi(1, max_tile_cells_per_frame)
	var performed_quantum: bool = false
	while not _pending_organic_rebuild_chunks.is_empty():
		if performed_quantum and Time.get_ticks_usec() >= deadline_usec:
			break
		var organic_chunk_coord: Vector2i = _pending_organic_rebuild_chunks[0]
		if (not _organic_rebuild_jobs.has(organic_chunk_coord)
				or not loaded_chunks.has(organic_chunk_coord)):
			_discard_organic_rebuild_job(organic_chunk_coord)
			continue
		var organic_job = _organic_rebuild_jobs[organic_chunk_coord]
		var organic_quantum_started_usec: int = Time.get_ticks_usec()
		organic_job.process_organic_rebuild_quantum(
			get_world_visible_cell, get_world_surface_elevation,
			maxi(1, chunk_work_quantum_cells))
		performed_quantum = true
		if organic_job.is_organic_geometry_ready():
			var organic_result: Dictionary = organic_job.finalize_organic_geometry()
			if (loaded_chunks.has(organic_chunk_coord)
					and int(_organic_geometry_revisions.get(organic_chunk_coord, 0))
						== organic_job.organic_geometry_revision):
				organic_job.organic_scene_attachment_usec = loaded_chunks[
					organic_chunk_coord].apply_prepared_organic_cliffs(organic_result)
				_cache_organic_halo(organic_chunk_coord, organic_job)
			_discard_organic_rebuild_job(organic_chunk_coord)
		organic_geometry_processing_usec_this_frame += (
			Time.get_ticks_usec() - organic_quantum_started_usec)
	while not _pending_chunks.is_empty():
		if performed_quantum and Time.get_ticks_usec() >= deadline_usec:
			break
		if chunks_finalised_this_frame >= maxi(1, chunks_created_per_frame):
			break

		var chunk_coord: Vector2i = _pending_chunks[0]
		if not _wanted_chunks.has(chunk_coord) or loaded_chunks.has(chunk_coord):
			_discard_build_job(chunk_coord)
			continue
		var job = _build_jobs[chunk_coord]
		if not job.is_data_ready():
			var processing_organic_geometry: bool = job.is_processing_organic_geometry()
			var data_quantum_started_usec: int = Time.get_ticks_usec()
			job.process_data_quantum(
				get_world_visible_cell, get_world_surface_elevation,
				get_world_elevation, priority_by_id, liquid_by_id,
				decoration_context,
				environment_object_context,
				maxi(1, chunk_work_quantum_cells))
			if processing_organic_geometry:
				organic_geometry_processing_usec_this_frame += (
					Time.get_ticks_usec() - data_quantum_started_usec)
		else:
			if job.renderer == null:
				_begin_job_population(job)
			if tile_cells_remaining <= 0:
				break
			var placement_start: int = Time.get_ticks_usec()
			var cells_to_place: int = mini(maxi(1, chunk_work_quantum_cells), tile_cells_remaining)
			var placed: int = 0
			if not job.is_terrain_populated():
				placed = job.renderer.populate_prepared_quantum(
					job.slot_sources, job.slot_masks,
					job.elevated_slot_sources, job.elevated_slot_masks,
					job.cliff_sources, job.cliff_variants, job.cliff_owner_heights,
					job.cliff_edge_sources, job.cliff_edge_masks, job.cliff_edge_heights,
					job.cliff_edge_styles, job.cliff_edge_drops,
					job.populate_index, cells_to_place)
				job.populate_index += placed
				job.tile_placement_usec += Time.get_ticks_usec() - placement_start
			else:
				placed = job.renderer.populate_prepared_decoration_quantum(
					job.decoration_ids, job.decoration_variants, job.decoration_heights,
					job.decoration_populate_index, cells_to_place)
				job.decoration_populate_index += placed
				var submission_usec: int = Time.get_ticks_usec() - placement_start
				job.decoration_submission_usec += submission_usec
				job.tile_placement_usec += submission_usec
			tile_cells_remaining -= placed
			if job.is_complete():
				_finalize_build_job(chunk_coord, job)
		performed_quantum = true

	var environment_submission_usec: int = environment_object_renderer.flush_pending()
	last_chunk_environment_submission_usec = environment_submission_usec
	if environment_submission_usec > 0:
		profile_total_environment_submission_usec += environment_submission_usec
	chunk_processing_usec_this_frame = Time.get_ticks_usec() - processing_start
	worst_chunk_processing_frame_usec = maxi(worst_chunk_processing_frame_usec, chunk_processing_usec_this_frame)
	worst_organic_geometry_processing_frame_usec = maxi(
		worst_organic_geometry_processing_frame_usec,
		organic_geometry_processing_usec_this_frame)
	if chunk_processing_usec_this_frame > roundi(max_chunk_processing_ms * 1000.0):
		chunk_processing_overrun_frames += 1
	# Editor refresh has separate instrumentation and must not inflate the
	# streaming scheduler's overrun counter.
	var processed_staged_cells: bool = _process_pending_edit_cell_refresh()
	if not processed_staged_cells:
		_process_pending_edit_environment_refresh()


func update_visible_world_rect(visible_rect: Rect2) -> void:
	var visible_cell_min: Vector2i = world_pixel_to_cell(visible_rect.position)
	var inclusive_end: Vector2 = visible_rect.end - Vector2(0.001, 0.001)
	var visible_cell_max: Vector2i = world_pixel_to_cell(inclusive_end)
	var visible_min: Vector2i = world_cell_to_chunk(visible_cell_min)
	var visible_max: Vector2i = world_cell_to_chunk(visible_cell_max)
	if visible_min == _last_visible_chunk_min and visible_max == _last_visible_chunk_max:
		return
	_last_visible_chunk_min = visible_min
	_last_visible_chunk_max = visible_max

	var safe_load_margin: int = maxi(0, load_margin_chunks)
	var safe_unload_margin: int = maxi(safe_load_margin + 1, unload_margin_chunks)
	var load_min: Vector2i = visible_min - Vector2i.ONE * safe_load_margin
	var load_max: Vector2i = visible_max + Vector2i.ONE * safe_load_margin
	var unload_min: Vector2i = visible_min - Vector2i.ONE * safe_unload_margin
	var unload_max: Vector2i = visible_max + Vector2i.ONE * safe_unload_margin

	_visible_chunks.clear()
	for chunk_y in range(visible_min.y, visible_max.y + 1):
		for chunk_x in range(visible_min.x, visible_max.x + 1):
			_visible_chunks[Vector2i(chunk_x, chunk_y)] = true

	_wanted_chunks.clear()
	for chunk_y in range(load_min.y, load_max.y + 1):
		for chunk_x in range(load_min.x, load_max.x + 1):
			_wanted_chunks[Vector2i(chunk_x, chunk_y)] = true

	var unload_start: int = Time.get_ticks_usec() if profiling_enabled else 0
	for chunk_coord in loaded_chunks.keys():
		if chunk_coord.x < unload_min.x or chunk_coord.x > unload_max.x or chunk_coord.y < unload_min.y or chunk_coord.y > unload_max.y:
			var chunk = loaded_chunks[chunk_coord]
			loaded_chunks.erase(chunk_coord)
			environment_object_renderer.remove_chunk(chunk_coord)
			_discard_organic_rebuild_job(chunk_coord)
			_organic_geometry_revisions.erase(chunk_coord)
			_organic_terrain_revisions.erase(chunk_coord)
			_organic_halo_cache.erase(chunk_coord)
			_queue_chunk_retirement(chunk)
	if profiling_enabled:
		last_unload_usec = Time.get_ticks_usec() - unload_start
		profile_total_unload_usec += last_unload_usec

	for chunk_coord in _build_jobs.keys():
		if not _wanted_chunks.has(chunk_coord):
			_discard_build_job(chunk_coord)

	_pending_chunks.clear()
	for chunk_coord in _wanted_chunks:
		if not loaded_chunks.has(chunk_coord):
			if not _build_jobs.has(chunk_coord):
				_build_jobs[chunk_coord] = _create_build_job(chunk_coord)
			_pending_chunks.append(chunk_coord)
	_sort_pending_chunks()


func _sort_pending_chunks() -> void:
	var visible_centre: Vector2 = (
		Vector2(_last_visible_chunk_min) + Vector2(_last_visible_chunk_max)) * 0.5
	_pending_chunks.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var a_visible: bool = _visible_chunks.has(a)
		var b_visible: bool = _visible_chunks.has(b)
		if a_visible != b_visible:
			return a_visible
		return Vector2(a).distance_squared_to(visible_centre) < Vector2(b).distance_squared_to(visible_centre))
	_pending_organic_rebuild_chunks.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var a_visible: bool = _visible_chunks.has(a)
		var b_visible: bool = _visible_chunks.has(b)
		if a_visible != b_visible:
			return a_visible
		return Vector2(a).distance_squared_to(visible_centre) < Vector2(b).distance_squared_to(visible_centre))


func set_world_cell(world_pos: Vector2i, terrain_id: int) -> void:
	if not priority_by_id.has(terrain_id):
		push_warning("Unknown terrain ID: %s" % terrain_id)
		return
	if not world.set_override(world_pos, terrain_id):
		return
	authoritative_state_changed.emit()
	# Material metadata can change the derived render-surface height (water at
	# sea level), so material painting refreshes the same neighbours as a
	# ground-height edit without mutating that stored ground height.
	_refresh_world_elevation(world_pos)


func get_world_material_override_state(world_pos: Vector2i) -> Dictionary:
	return world.get_material_override_state(world_pos)


func get_world_elevation_override_state(world_pos: Vector2i) -> Dictionary:
	return world.get_elevation_override_state(world_pos)


func get_all_override_cells() -> Array[Vector2i]:
	return world.get_all_override_cells()


func apply_world_edit_states(edit_states: Array[Dictionary]) -> int:
	## Applies authoritative override states first, then refreshes every derived
	## presentation dependency once for the deduplicated set of changed cells.
	var changed_cells: Dictionary = {}
	for edit in edit_states:
		var world_pos: Vector2i = edit.cell
		var changed: bool
		if String(edit.kind) == "material":
			var state: Dictionary = edit.state
			if bool(state.get("has_override", false)) and not priority_by_id.has(int(state.value)):
				push_warning("Unknown terrain ID: %s" % state.value)
				continue
			changed = world.apply_material_override_state(world_pos, state)
		else:
			changed = world.apply_elevation_override_state(world_pos, edit.state)
		if changed:
			changed_cells[world_pos] = true
	if changed_cells.is_empty():
		last_edit_dirty_cell_count = 0
		last_edit_dirty_chunk_count = 0
		last_edit_refresh_usec = 0
		return 0
	authoritative_state_changed.emit()
	if changed_cells.size() > STAGED_EDIT_THRESHOLD or not pending_edit_cells.is_empty():
		for world_pos in changed_cells:
			pending_edit_cells[world_pos] = true
		last_edit_dirty_cell_count = changed_cells.size()
		last_edit_dirty_chunk_count = _count_edit_dependency_chunks(changed_cells)
		last_edit_refresh_usec = 0
		return changed_cells.size()
	var refresh_start_usec: int = Time.get_ticks_usec()
	_refresh_world_cells(changed_cells)
	last_edit_dirty_cell_count = changed_cells.size()
	last_edit_refresh_usec = Time.get_ticks_usec() - refresh_start_usec
	return changed_cells.size()


func _process_pending_edit_cell_refresh() -> bool:
	if pending_edit_cells.is_empty():
		return false
	var batch: Dictionary = {}
	for world_pos in pending_edit_cells:
		if batch.size() >= STAGED_EDIT_CELLS_PER_FRAME:
			break
		if _visible_chunks.has(world_cell_to_chunk(world_pos)):
			batch[world_pos] = true
	if batch.size() < STAGED_EDIT_CELLS_PER_FRAME:
		for world_pos in pending_edit_cells:
			if batch.size() >= STAGED_EDIT_CELLS_PER_FRAME:
				break
			batch[world_pos] = true
	for world_pos in batch:
		pending_edit_cells.erase(world_pos)
	var refresh_start_usec: int = Time.get_ticks_usec()
	_refresh_world_cells(batch)
	last_edit_refresh_usec = Time.get_ticks_usec() - refresh_start_usec
	return true


func _count_edit_dependency_chunks(changed_cells: Dictionary) -> int:
	var chunks: Dictionary = {}
	var radius: int = EnvironmentObjectPlacement.MAX_EXCLUSION_RADIUS + 1
	for world_pos in changed_cells:
		var minimum_chunk: Vector2i = world_cell_to_chunk(world_pos - Vector2i.ONE * radius)
		var maximum_chunk: Vector2i = world_cell_to_chunk(world_pos + Vector2i.ONE * radius)
		for chunk_y in range(minimum_chunk.y, maximum_chunk.y + 1):
			for chunk_x in range(minimum_chunk.x, maximum_chunk.x + 1):
				chunks[Vector2i(chunk_x, chunk_y)] = true
	return chunks.size()


func get_world_cell(world_pos: Vector2i) -> int:
	return world.get_cell(world_pos)


func get_world_visible_cell(world_pos: Vector2i) -> int:
	return world.get_visible_material(world_pos, sea_level)


func get_world_visible_liquid_elevation(world_pos: Vector2i) -> int:
	return world.get_visible_liquid_elevation(world_pos, sea_level)


func set_world_elevation(world_pos: Vector2i, elevation: int) -> void:
	if not world.set_elevation_override(world_pos, elevation):
		return
	authoritative_state_changed.emit()
	_refresh_world_elevation(world_pos)


func restore_world_elevation(world_pos: Vector2i) -> void:
	if not world.clear_elevation_override(world_pos):
		return
	authoritative_state_changed.emit()
	_refresh_world_elevation(world_pos)


func _refresh_world_elevation(world_pos: Vector2i) -> void:
	_refresh_world_cells({world_pos: true})


func _refresh_world_cells(changed_cells: Dictionary) -> void:
	var jobs_to_restart: Dictionary = {}
	var dual_cells: Dictionary = {}
	var cliff_cells: Dictionary = {}
	var decoration_cells: Dictionary = {}
	var environment_chunks: Dictionary = {}
	var dirty_chunks: Dictionary = {}
	var organic_cliff_chunks: Dictionary = {}
	var radius: int = EnvironmentObjectPlacement.MAX_EXCLUSION_RADIUS + 1
	for world_pos in changed_cells:
		for offset in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
			dual_cells[world_pos + offset] = true
		for offset in [
				Vector2i.LEFT, Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN,
				Vector2i(-1, -1), Vector2i.UP, Vector2i(1, -1)]:
			cliff_cells[world_pos + offset] = true
		for offset in [
				Vector2i.ZERO, Vector2i.UP, Vector2i.RIGHT,
				Vector2i.DOWN, Vector2i.LEFT]:
			decoration_cells[world_pos + offset] = true
		var minimum_chunk: Vector2i = world_cell_to_chunk(world_pos - Vector2i.ONE * radius)
		var maximum_chunk: Vector2i = world_cell_to_chunk(world_pos + Vector2i.ONE * radius)
		for chunk_y in range(minimum_chunk.y, maximum_chunk.y + 1):
			for chunk_x in range(minimum_chunk.x, maximum_chunk.x + 1):
				environment_chunks[Vector2i(chunk_x, chunk_y)] = true
				dirty_chunks[Vector2i(chunk_x, chunk_y)] = true

	for chunk_coord in environment_chunks:
		pending_edit_environment_chunks[chunk_coord] = true
		if _build_jobs.has(chunk_coord):
			jobs_to_restart[chunk_coord] = true

	for dual_pos in dual_cells:
		dirty_chunks[world_cell_to_chunk(dual_pos)] = true
		_collect_build_job_restart(dual_pos, jobs_to_restart)
		_refresh_global_dual_cell(dual_pos)
	for cliff_cell in cliff_cells:
		var cliff_chunk: Vector2i = world_cell_to_chunk(cliff_cell)
		dirty_chunks[cliff_chunk] = true
		organic_cliff_chunks[cliff_chunk] = true
		_collect_build_job_restart(cliff_cell, jobs_to_restart)
		_refresh_global_cliff_cell(cliff_cell)
	for decoration_cell in decoration_cells:
		dirty_chunks[world_cell_to_chunk(decoration_cell)] = true
		_collect_build_job_restart(decoration_cell, jobs_to_restart)
		_refresh_global_decoration_cell(decoration_cell)
	for affected_chunk in jobs_to_restart:
		_restart_build_job(affected_chunk)
	if organic_cliff_geometry_enabled:
		for chunk_coord in organic_cliff_chunks:
			if loaded_chunks.has(chunk_coord):
				_organic_terrain_revisions[chunk_coord] = int(
					_organic_terrain_revisions.get(chunk_coord, 0)) + 1
				_schedule_organic_cliff_rebuild(chunk_coord)
	last_edit_dirty_chunk_count = dirty_chunks.size()


func _process_pending_edit_environment_refresh() -> void:
	last_edit_environment_refresh_usec = 0
	if pending_edit_environment_chunks.is_empty():
		return
	var selected_chunk: Variant = null
	for chunk_coord in pending_edit_environment_chunks:
		if selected_chunk == null or (
				_visible_chunks.has(chunk_coord)
				and not _visible_chunks.has(selected_chunk)):
			selected_chunk = chunk_coord
	pending_edit_environment_chunks.erase(selected_chunk)
	if not loaded_chunks.has(selected_chunk):
		return
	var refresh_start_usec: int = Time.get_ticks_usec()
	var previous_occupied: Dictionary = environment_object_renderer.get_occupied_ground_cells()
	_rebuild_environment_object_chunk(selected_chunk)
	environment_object_renderer.flush_pending()
	var current_occupied: Dictionary = environment_object_renderer.get_occupied_ground_cells()
	for occupied_cell in previous_occupied:
		if not current_occupied.has(occupied_cell):
			_refresh_global_decoration_cell(occupied_cell)
	for occupied_cell in current_occupied:
		if not previous_occupied.has(occupied_cell):
			_refresh_global_decoration_cell(occupied_cell)
	last_edit_environment_refresh_usec = Time.get_ticks_usec() - refresh_start_usec


func get_pending_edit_environment_chunk_count() -> int:
	return pending_edit_environment_chunks.size()


func get_pending_edit_cell_count() -> int:
	return pending_edit_cells.size()


func _collect_build_job_restart(world_pos: Vector2i, jobs_to_restart: Dictionary) -> void:
	var affected_chunk: Vector2i = world_cell_to_chunk(world_pos)
	if _build_jobs.has(affected_chunk):
		jobs_to_restart[affected_chunk] = true


func get_world_elevation(world_pos: Vector2i) -> int:
	return world.get_elevation(world_pos)


func get_world_surface_elevation(world_pos: Vector2i) -> int:
	return world.get_surface_elevation(world_pos, sea_level)


func get_cliff_edge_diagnostic(world_pos: Vector2i) -> Dictionary:
	## Read-only developer diagnostic for the local shape-aware treatment. It
	## derives presentation classification without touching authoritative state.
	var north := world_pos + Vector2i.UP
	var east := world_pos + Vector2i.RIGHT
	var south := world_pos + Vector2i.DOWN
	var west := world_pos + Vector2i.LEFT
	var result: Dictionary = TerrainChunkBuildJob.classify_cliff_edge_samples(
		get_world_surface_elevation(world_pos), get_world_visible_cell(world_pos),
		get_world_surface_elevation(north), get_world_surface_elevation(east),
		get_world_surface_elevation(south), get_world_surface_elevation(west),
		get_world_surface_elevation(world_pos + Vector2i(1, -1)),
		get_world_surface_elevation(world_pos + Vector2i(1, 1)),
		get_world_surface_elevation(world_pos + Vector2i(-1, 1)),
		get_world_surface_elevation(world_pos + Vector2i(-1, -1)),
		get_world_visible_cell(north), get_world_visible_cell(east),
		get_world_visible_cell(south), get_world_visible_cell(west), liquid_by_id)
	result["cell"] = world_pos
	result["labels"] = TerrainChunkBuildJob.edge_diagnostic_labels(int(result["flags"]))
	return result


func set_procedural_elevation_enabled(enabled: bool) -> void:
	if procedural_elevation_enabled == enabled:
		return
	procedural_elevation_enabled = enabled
	_configure_procedural_elevation_and_rebuild()


func configure_procedural_elevation(
		enabled: bool, maximum_elevation: int, regional_frequency: float,
		local_detail_frequency: float, local_detail_strength: float,
		threshold_1: float, threshold_2: float, threshold_3: float,
		flatness_bias: float) -> void:
	procedural_elevation_enabled = enabled
	max_generated_elevation = maximum_elevation
	elevation_frequency = regional_frequency
	elevation_detail_frequency = local_detail_frequency
	elevation_detail_strength = local_detail_strength
	elevation_threshold_1 = threshold_1
	elevation_threshold_2 = threshold_2
	elevation_threshold_3 = threshold_3
	elevation_flatness_bias = flatness_bias
	if generator != null:
		_configure_procedural_elevation_and_rebuild()


func _configure_procedural_elevation_and_rebuild() -> void:
	generator.configure_elevation(
		procedural_elevation_enabled, max_generated_elevation,
		elevation_frequency, elevation_detail_frequency,
		elevation_detail_strength, elevation_threshold_1,
		elevation_threshold_2, elevation_threshold_3,
		elevation_flatness_bias)
	_invalidate_streamed_chunks()


func _invalidate_streamed_chunks() -> void:
	# Generator changes replace visuals through the existing budgeted build
	# queue. TerrainWorld's sparse overrides remain authoritative and intact.
	for chunk_coord in loaded_chunks.keys():
		var chunk = loaded_chunks[chunk_coord]
		_queue_chunk_retirement(chunk)
	loaded_chunks.clear()
	environment_object_renderer.clear_chunks()
	for chunk_coord in _build_jobs.keys():
		_discard_build_job(chunk_coord)
	for chunk_coord in _organic_rebuild_jobs.keys():
		_discard_organic_rebuild_job(chunk_coord)
	_organic_geometry_revisions.clear()
	_organic_terrain_revisions.clear()
	_organic_halo_cache.clear()
	_pending_chunks.clear()
	for chunk_coord in _wanted_chunks:
		_build_jobs[chunk_coord] = _create_build_job(chunk_coord)
		_pending_chunks.append(chunk_coord)
	_sort_pending_chunks()


func apply_phase5a_demo() -> void:
	# This legacy optional showcase remains ordinary authoritative sparse
	# overrides and can still be used with procedural elevation disabled.
	for y in range(-11, 12):
		for x in range(-18, 19):
			var world_pos := Vector2i(x, y)
			var elevation: int = 0
			if abs(x) <= 16 and abs(y) <= 8:
				elevation = 1
			if y >= 5 and x >= -16 and x <= -11:
				elevation = 0 # A rectangular recess demonstrates a cliff bend.
			if y >= 5 and x >= 6 and x <= 9:
				elevation = 0 # The level-2 tongue above this makes a two-level drop.
			if x >= -8 and x <= 9 and y >= -5 and y <= 4 and not (x < -5 and y < -2):
				elevation = 2
			if x >= -2 and x <= 4 and y >= -3 and y <= 1:
				elevation = 3
			if elevation > 0:
				world.set_elevation_override(world_pos, elevation)
			var terrain_id: int = Catalog.DEFAULT_MATERIAL_ID
			if elevation == 1 and x >= 8:
				terrain_id = 7 # Gravel meets grass on the first plateau.
			elif elevation == 2:
				terrain_id = 2 if x < -4 else 4 # Dirt and stone share level 2.
			elif elevation == 3:
				terrain_id = 5 # Snow cap.
			world.set_override(world_pos, terrain_id)


func clear_player_overrides() -> void:
	if not world.clear_overrides():
		return
	authoritative_state_changed.emit()
	for chunk in loaded_chunks.values():
		chunk.rebuild()
		if organic_cliff_geometry_enabled:
			_schedule_organic_cliff_rebuild(chunk.chunk_coord)
	for chunk_coord in _build_jobs.keys():
		_restart_build_job(chunk_coord)


func get_override_count() -> int:
	return world.get_override_count()


func get_height_override_count() -> int:
	return world.get_height_override_count()


func get_loaded_chunk_count() -> int:
	return loaded_chunks.size()


func set_decorations_enabled(enabled: bool) -> void:
	decorations_enabled = enabled
	for chunk in loaded_chunks.values():
		chunk.set_decorations_visible(enabled)
	for job in _build_jobs.values():
		if job.renderer != null:
			job.renderer.set_decorations_visible(enabled)


func set_decoration_generation_enabled(enabled: bool) -> void:
	if decoration_generation_enabled == enabled:
		return
	decoration_generation_enabled = enabled
	decoration_context["generation_enabled"] = enabled
	_invalidate_streamed_chunks()


func set_environment_objects_enabled(enabled: bool) -> void:
	environment_objects_enabled = enabled
	environment_object_renderer.set_objects_visible(enabled)


func set_procedural_vegetation_enabled(enabled: bool) -> void:
	## Presentation-only A/B switch. Placement, resource identity and terrain
	## authority are unchanged, and both bounded atlas textures are precomputed.
	if procedural_vegetation_enabled == enabled:
		return
	procedural_vegetation_enabled = enabled
	environment_object_atlas_texture = (
		environment_object_procedural_atlas_texture
		if enabled else environment_object_legacy_tree_atlas_texture)
	if environment_object_renderer != null:
		environment_object_renderer.set_atlas_texture(environment_object_atlas_texture)


func set_environment_object_generation_enabled(enabled: bool) -> void:
	if environment_object_generation_enabled == enabled:
		return
	environment_object_generation_enabled = enabled
	environment_object_context["generation_enabled"] = enabled
	_invalidate_streamed_chunks()


func get_visible_environment_object_count() -> int:
	return environment_object_renderer.get_visible_object_count()


func get_environment_object_category_counts() -> Dictionary:
	return environment_object_renderer.get_category_counts()


func get_environment_atlas_metrics() -> Dictionary:
	return {
		"generation_usec": environment_atlas_generation_usec,
		"legacy_generation_usec": environment_legacy_atlas_generation_usec,
		"variant_count": environment_atlas_variant_count,
		"procedural_variant_count": environment_procedural_variant_count,
		"procedural_tree_variant_count": environment_procedural_tree_variant_count,
		"dimensions": environment_atlas_dimensions,
		"texture_instance_id": environment_object_atlas_texture.get_instance_id(),
		"procedural_texture_instance_id": environment_object_procedural_atlas_texture.get_instance_id(),
		"legacy_texture_instance_id": environment_object_legacy_tree_atlas_texture.get_instance_id(),
		"texture_memory_bytes": environment_atlas_dimensions.x * environment_atlas_dimensions.y * 4 * 2,
		"runtime_generation_count": 0,
	}


func get_resource_at_cell(world_cell: Vector2i) -> Dictionary:
	var rendered: Dictionary = environment_object_renderer.get_resource_at_cell(world_cell)
	if rendered.is_empty():
		return {}
	var definition_id: int = int(rendered["definition_id"])
	var anchor: Vector2i = rendered["anchor"]
	var snapshot: Dictionary = resource_state_manager.get_snapshot(definition_id, anchor)
	var definition: Dictionary = environment_object_context["definitions_by_id"][definition_id]
	snapshot["name"] = String(definition["name"])
	snapshot["expected_yield"] = int(definition.get("future_yield", 0))
	snapshot["height"] = int(rendered["height"])
	snapshot["regrowth_remaining"] = resource_state_manager.get_remaining_regrowth_time(
		definition_id, anchor)
	return snapshot


func get_loaded_resources() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for rendered in environment_object_renderer.get_loaded_resource_entries():
		var definition_id: int = int(rendered["definition_id"])
		var anchor: Vector2i = rendered["anchor"]
		var snapshot: Dictionary = resource_state_manager.get_snapshot(definition_id, anchor)
		var definition: Dictionary = environment_object_context["definitions_by_id"][definition_id]
		snapshot["name"] = String(definition["name"])
		snapshot["expected_yield"] = int(definition.get("future_yield", 0))
		snapshot["height"] = int(rendered["height"])
		result.append(snapshot)
	return result


func designate_resource(definition_id: int, anchor: Vector2i) -> bool:
	return resource_state_manager.designate(definition_id, anchor)


func cancel_resource_designation(definition_id: int, anchor: Vector2i) -> bool:
	return resource_state_manager.cancel_designation(definition_id, anchor)


func complete_designated_resource(definition_id: int, anchor: Vector2i) -> Dictionary:
	return resource_state_manager.complete_designated_harvest(definition_id, anchor)


func set_selected_resource_id(resource_id: String) -> void:
	environment_object_renderer.set_selected_resource_id(resource_id)


func get_resource_inventory() -> Dictionary:
	return resource_state_manager.get_inventory()


func get_resource_state_metrics() -> Dictionary:
	return {
		"modified_states": resource_state_manager.get_modified_state_count(),
		"memory_bytes": resource_state_manager.get_memory_estimate_bytes(),
		"simulated_time": resource_state_manager.simulated_time,
	}


func export_generation_config() -> Dictionary:
	return {
		"world_seed": world_seed,
		"biome_frequency": biome_frequency,
		"detail_frequency": detail_frequency,
		"include_origin_demo": include_origin_demo,
		"procedural_elevation_enabled": procedural_elevation_enabled,
		"max_generated_elevation": max_generated_elevation,
		"elevation_frequency": elevation_frequency,
		"elevation_detail_frequency": elevation_detail_frequency,
		"elevation_detail_strength": elevation_detail_strength,
		"elevation_threshold_1": elevation_threshold_1,
		"elevation_threshold_2": elevation_threshold_2,
		"elevation_threshold_3": elevation_threshold_3,
		"elevation_flatness_bias": elevation_flatness_bias,
		"sea_level": sea_level,
		"decoration_density": decoration_density,
		"decoration_clustering_strength": decoration_clustering_strength,
		"decoration_seed_offset": decoration_seed_offset,
		"decoration_generation_enabled": decoration_generation_enabled,
		"environment_object_density": environment_object_density,
		"environment_object_seed_offset": environment_object_seed_offset,
		"environment_object_generation_enabled": environment_object_generation_enabled,
	}


func apply_generation_config(config: Dictionary) -> void:
	## Called before entering the scene tree when reconstructing a saved world.
	world_seed = int(config["world_seed"])
	biome_frequency = float(config["biome_frequency"])
	detail_frequency = float(config["detail_frequency"])
	include_origin_demo = bool(config["include_origin_demo"])
	procedural_elevation_enabled = bool(config["procedural_elevation_enabled"])
	max_generated_elevation = int(config["max_generated_elevation"])
	elevation_frequency = float(config["elevation_frequency"])
	elevation_detail_frequency = float(config["elevation_detail_frequency"])
	elevation_detail_strength = float(config["elevation_detail_strength"])
	elevation_threshold_1 = float(config["elevation_threshold_1"])
	elevation_threshold_2 = float(config["elevation_threshold_2"])
	elevation_threshold_3 = float(config["elevation_threshold_3"])
	elevation_flatness_bias = float(config["elevation_flatness_bias"])
	sea_level = int(config["sea_level"])
	decoration_density = float(config["decoration_density"])
	decoration_clustering_strength = float(config["decoration_clustering_strength"])
	decoration_seed_offset = int(config["decoration_seed_offset"])
	decoration_generation_enabled = bool(config["decoration_generation_enabled"])
	environment_object_density = float(config["environment_object_density"])
	environment_object_seed_offset = int(config["environment_object_seed_offset"])
	environment_object_generation_enabled = bool(config["environment_object_generation_enabled"])


func export_authoritative_snapshot() -> Dictionary:
	return {
		"terrain": world.export_override_snapshot(),
		"resources": resource_state_manager.export_snapshot(),
	}


func import_authoritative_snapshot(snapshot: Dictionary) -> Dictionary:
	if not snapshot.has("terrain") or not snapshot.has("resources"):
		return {"ok": false, "error": "Authoritative snapshot is incomplete"}
	var terrain_validation: Dictionary = world.validate_override_snapshot(snapshot["terrain"])
	if not bool(terrain_validation["ok"]):
		return terrain_validation
	var resource_validation: Dictionary = resource_state_manager.validate_snapshot(snapshot["resources"])
	if not bool(resource_validation["ok"]):
		return resource_validation
	pending_edit_cells.clear()
	pending_edit_environment_chunks.clear()
	var terrain_result: Dictionary = world.import_override_snapshot(snapshot["terrain"])
	if not bool(terrain_result["ok"]):
		return terrain_result
	var resource_result: Dictionary = resource_state_manager.import_snapshot(snapshot["resources"])
	if not bool(resource_result["ok"]):
		return resource_result
	_invalidate_streamed_chunks()
	return {"ok": true, "error": ""}


func advance_resource_time(delta_seconds: float) -> int:
	return resource_state_manager.advance_simulated_time(delta_seconds)


func _on_resource_changed(
		resource_id: String, anchor: Vector2i,
		definition_id: int, change_kind: String) -> void:
	authoritative_state_changed.emit()
	if change_kind == "removed":
		var changed_occupancy: Array[Vector2i] = _rebuild_environment_objects_near(anchor)
		for cell in changed_occupancy:
			_refresh_global_decoration_cell(cell)
		return
	var snapshot: Dictionary = resource_state_manager.get_snapshot(definition_id, anchor)
	if snapshot.is_empty():
		return
	environment_object_renderer.update_resource_state(
		resource_id,
		bool(snapshot.get("designated", false)),
		bool(snapshot.get("ripe", true)))


func get_visible_decoration_count() -> int:
	if not decorations_enabled:
		return 0
	var count: int = 0
	for chunk in loaded_chunks.values():
		count += chunk.get_decoration_count()
	return count


func set_texture_variation_enabled(enabled: bool) -> void:
	texture_variation_enabled = enabled
	for visual_material in visual_material_by_id.values():
		visual_material.set_shader_parameter("variation_enabled", 1.0 if enabled else 0.0)


func set_clustered_grass_detail_enabled(enabled: bool) -> void:
	## Presentation-only rollback switch. The shared grass material updates
	## without rebuilding chunks or changing authoritative terrain state.
	clustered_grass_detail_enabled = enabled
	_apply_clustered_grass_detail_parameters()


func set_clustered_grass_detail_controls(
		clear_coverage: float, detail_density: float, cluster_scale: float,
		transition_softness: float, residual_density: float,
		seed_offset: int) -> void:
	grass_clear_area_coverage = clampf(clear_coverage, 0.0, 1.0)
	grass_detail_density = clampf(detail_density, 0.0, 1.0)
	grass_cluster_scale = clampf(cluster_scale, 0.0005, 0.02)
	grass_transition_softness = clampf(transition_softness, 0.0, 0.4)
	grass_clear_area_residual_density = clampf(residual_density, 0.0, 1.0)
	grass_detail_seed_offset = seed_offset
	_apply_clustered_grass_detail_parameters()


func _apply_clustered_grass_detail_parameters() -> void:
	if not visual_material_by_id.has(Catalog.DEFAULT_MATERIAL_ID):
		return
	var config: Dictionary = _terrain_surface_factory_config()["grass_detail"].duplicate()
	config["world_seed"] = world_seed
	TerrainSurfaceFactory.apply_clustered_grass_detail_parameters(
		visual_material_by_id[Catalog.DEFAULT_MATERIAL_ID],
		config, true)


func set_organic_grass_color_variation_enabled(enabled: bool) -> void:
	## Presentation-only rollback switch. The shared grass material updates
	## without rebuilding chunks or changing authoritative terrain state.
	organic_grass_color_variation_enabled = enabled
	_apply_organic_grass_color_variation_parameters()


func set_organic_grass_color_variation_controls(
		broad_scale: float, color_strength: float, fine_strength: float) -> void:
	grass_broad_variation_scale = clampf(broad_scale, 0.0005, 0.01)
	grass_color_variation_strength = clampf(color_strength, 0.0, 0.15)
	grass_fine_variation_strength = clampf(fine_strength, 0.0, 0.08)
	_apply_organic_grass_color_variation_parameters()


func _apply_organic_grass_color_variation_parameters() -> void:
	if not visual_material_by_id.has(Catalog.DEFAULT_MATERIAL_ID):
		return
	var config: Dictionary = _terrain_surface_factory_config()["grass_surface_variation"].duplicate()
	config["world_seed"] = world_seed
	TerrainSurfaceFactory.apply_organic_grass_color_variation_parameters(
		visual_material_by_id[Catalog.DEFAULT_MATERIAL_ID], config, true)


func set_grass_texture_repetition_correction_enabled(enabled: bool) -> void:
	## Presentation-only G3 rollback. One shared material changes in place;
	## authoritative terrain and streamed chunks remain untouched.
	grass_texture_repetition_correction_enabled = enabled
	_apply_grass_texture_repetition_parameters()


func _apply_grass_texture_repetition_parameters() -> void:
	if not visual_material_by_id.has(Catalog.DEFAULT_MATERIAL_ID):
		return
	TerrainSurfaceFactory.apply_grass_texture_repetition_parameters(
		visual_material_by_id[Catalog.DEFAULT_MATERIAL_ID],
		_terrain_surface_factory_config()["grass_texture_repetition"], true)


func set_terrain_texture_repetition_correction_enabled(enabled: bool) -> void:
	## Presentation-only G4 rollback; shared materials update without rebuilding
	## chunks or touching authoritative terrain state.
	terrain_texture_repetition_correction_enabled = enabled
	_apply_terrain_texture_repetition_parameters()


func set_terrain_texture_repetition_material_settings(settings: Dictionary) -> void:
	terrain_texture_repetition_material_settings = settings.duplicate(true)
	_apply_terrain_texture_repetition_parameters()


func _apply_terrain_texture_repetition_parameters() -> void:
	var config: Dictionary = _terrain_surface_factory_config()["terrain_texture_repetition"]
	for definition in Catalog.MATERIALS:
		var terrain_id: int = int(definition["id"])
		if visual_material_by_id.has(terrain_id):
			TerrainSurfaceFactory.apply_terrain_texture_repetition_parameters(
				visual_material_by_id[terrain_id], config, definition)


func set_stochastic_terrain_detail_enabled(enabled: bool) -> void:
	## G5 replaces repetitive source detail only in presentation. Disabling it
	## restores the exact G4 shader path without rebuilding streamed chunks.
	stochastic_terrain_detail_enabled = enabled
	_apply_stochastic_terrain_detail_parameters()


func set_stochastic_terrain_detail_material_settings(settings: Dictionary) -> void:
	stochastic_terrain_detail_material_settings = settings.duplicate(true)
	_apply_stochastic_terrain_detail_parameters()


func _apply_stochastic_terrain_detail_parameters() -> void:
	var config: Dictionary = _terrain_surface_factory_config()["stochastic_terrain_detail"]
	for definition in Catalog.MATERIALS:
		var terrain_id: int = int(definition["id"])
		if visual_material_by_id.has(terrain_id):
			TerrainSurfaceFactory.apply_stochastic_terrain_detail_parameters(
				visual_material_by_id[terrain_id], config, definition)


func set_remaining_terrain_detail_enabled(enabled: bool) -> void:
	## G6 presentation-only rollback for snow and gravel. Shared material state
	## changes in place; terrain cells and streamed chunks remain authoritative.
	remaining_terrain_detail_enabled = enabled
	_apply_remaining_terrain_detail_parameters()


func set_remaining_terrain_detail_material_settings(settings: Dictionary) -> void:
	remaining_terrain_detail_material_settings = settings.duplicate(true)
	_apply_remaining_terrain_detail_parameters()


func _apply_remaining_terrain_detail_parameters() -> void:
	var config: Dictionary = _terrain_surface_factory_config()["remaining_terrain_detail"]
	for definition in Catalog.MATERIALS:
		var terrain_id: int = int(definition["id"])
		if visual_material_by_id.has(terrain_id):
			TerrainSurfaceFactory.apply_remaining_terrain_detail_parameters(
				visual_material_by_id[terrain_id], config, definition)


func set_water_repetition_correction_enabled(enabled: bool) -> void:
	water_repetition_correction_enabled = enabled
	_apply_water_repetition_correction_parameters()


func set_water_repetition_correction_strength(strength: float) -> void:
	water_repetition_correction_strength = clampf(strength, 0.0, 1.0)
	_apply_water_repetition_correction_parameters()


func _apply_water_repetition_correction_parameters() -> void:
	for terrain_id in visual_material_by_id:
		if bool(liquid_by_id.get(int(terrain_id), false)):
			TerrainSurfaceFactory.apply_water_repetition_correction_parameters(
				visual_material_by_id[terrain_id], {
					"enabled": water_repetition_correction_enabled,
					"strength": water_repetition_correction_strength,
				})


func set_organic_boundaries_enabled(enabled: bool) -> void:
	organic_boundaries_enabled = enabled
	for visual_material in visual_material_by_id.values():
		visual_material.set_shader_parameter("organic_boundaries_enabled", 1.0 if enabled else 0.0)


func set_experimental_water_enhancement_enabled(enabled: bool) -> void:
	## Presentation-only rollback switch. Shared materials update immediately;
	## authoritative terrain and streamed chunk contents remain unchanged.
	experimental_water_enhancement_enabled = enabled
	for terrain_id in visual_material_by_id:
		if bool(liquid_by_id.get(int(terrain_id), false)):
			visual_material_by_id[terrain_id].set_shader_parameter(
				"experimental_water_enhancement_enabled", 1.0 if enabled else 0.0)


func set_water_enhancement_controls(
		ripple_strength: float, secondary_scale: float, drift_speed: float,
		glint_density: float, glint_brightness: float) -> void:
	water_ripple_strength = clampf(ripple_strength, 0.0, 1.0)
	water_secondary_ripple_scale = clampf(secondary_scale, 0.5, 6.0)
	water_ripple_drift_speed = clampf(drift_speed, 0.0, 2.0)
	water_glint_density = clampf(glint_density, 0.0, 1.0)
	water_glint_brightness = clampf(glint_brightness, 0.0, 1.0)
	for terrain_id in visual_material_by_id:
		if bool(liquid_by_id.get(int(terrain_id), false)):
			_apply_water_enhancement_parameters(visual_material_by_id[terrain_id])


func set_water_animation_time_override(seconds: float) -> void:
	## Capture/validation hook. Pass a negative value to restore global TIME.
	for terrain_id in visual_material_by_id:
		if bool(liquid_by_id.get(int(terrain_id), false)):
			visual_material_by_id[terrain_id].set_shader_parameter(
				"water_animation_time_override", seconds)


func _apply_water_enhancement_parameters(material: ShaderMaterial) -> void:
	TerrainSurfaceFactory.apply_water_enhancement_parameters(
		material, _terrain_surface_factory_config()["water"])


func set_procedural_cliff_materials_enabled(enabled: bool) -> void:
	## Presentation-only rollback switch. Atlas selection, chunk data and
	## authoritative terrain remain unchanged.
	procedural_cliff_materials_enabled = enabled
	for material in cliff_material_by_source.values():
		material.set_shader_parameter("procedural_enabled", enabled)
	for material in cliff_shadow_material_by_source.values():
		material.set_shader_parameter("procedural_enabled", enabled)
	if organic_cliff_material != null:
		organic_cliff_material.set_shader_parameter("procedural_enabled", enabled)


func set_cliff_repetition_correction_enabled(enabled: bool) -> void:
	cliff_repetition_correction_enabled = enabled
	_apply_cliff_repetition_correction_parameters()


func set_cliff_repetition_correction_strength(strength: float) -> void:
	cliff_repetition_correction_strength = clampf(strength, 0.0, 1.0)
	_apply_cliff_repetition_correction_parameters()


func _apply_cliff_repetition_correction_parameters() -> void:
	for material in cliff_material_by_source.values():
		material.set_shader_parameter("texture_detail_reconstruction_enabled",
			cliff_repetition_correction_enabled)
		material.set_shader_parameter("texture_detail_reconstruction_strength",
			cliff_repetition_correction_strength)
	if organic_cliff_material != null:
		organic_cliff_material.set_shader_parameter(
			"texture_detail_reconstruction_enabled", cliff_repetition_correction_enabled)
		organic_cliff_material.set_shader_parameter(
			"texture_detail_reconstruction_strength", cliff_repetition_correction_strength)


func is_procedural_cliff_materials_enabled() -> bool:
	return procedural_cliff_materials_enabled


func set_organic_cliff_geometry_enabled(enabled: bool) -> void:
	## Experimental presentation-only mode. Existing TileMap cliff cells stay
	## populated and are made visible again immediately when this is disabled.
	if organic_cliff_geometry_enabled == enabled:
		return
	organic_cliff_geometry_enabled = enabled
	for chunk in loaded_chunks.values():
		chunk.set_organic_cliff_geometry_enabled(enabled)
	if enabled:
		for chunk_coord in loaded_chunks:
			_schedule_organic_cliff_rebuild(chunk_coord, true)
	else:
		for chunk_coord in _organic_rebuild_jobs.keys():
			_discard_organic_rebuild_job(chunk_coord)
	_restart_pending_stream_builds()


func set_unified_cliff_components_enabled(enabled: bool) -> void:
	if unified_cliff_components_enabled == enabled:
		return
	unified_cliff_components_enabled = enabled
	for chunk in loaded_chunks.values():
		chunk.set_unified_cliff_components_enabled(enabled)
	if organic_cliff_geometry_enabled:
		for chunk_coord in loaded_chunks:
			_schedule_organic_cliff_rebuild(chunk_coord, true)
	_restart_pending_stream_builds()


func set_refined_cliff_silhouettes_enabled(enabled: bool) -> void:
	if refined_cliff_silhouettes_enabled == enabled:
		return
	refined_cliff_silhouettes_enabled = enabled
	for chunk in loaded_chunks.values():
		chunk.set_refined_cliff_silhouettes_enabled(enabled)
	if organic_cliff_geometry_enabled:
		for chunk_coord in loaded_chunks:
			_schedule_organic_cliff_rebuild(chunk_coord, true)
	_restart_pending_stream_builds()


func set_connected_cliff_contours_enabled(enabled: bool) -> void:
	if connected_cliff_contours_enabled == enabled:
		return
	connected_cliff_contours_enabled = enabled
	for chunk in loaded_chunks.values():
		chunk.set_connected_cliff_contours_enabled(enabled)
	if organic_cliff_geometry_enabled:
		for chunk_coord in loaded_chunks:
			_schedule_organic_cliff_rebuild(chunk_coord, true)
	_restart_pending_stream_builds()


func set_unified_cliff_contours_enabled(enabled: bool) -> void:
	## Phase 3E presentation-only rollback switch. Disabled restores Phase 3D.
	if unified_cliff_contours_enabled == enabled:
		return
	unified_cliff_contours_enabled = enabled
	for chunk in loaded_chunks.values():
		chunk.set_unified_cliff_contours_enabled(enabled)
	if organic_cliff_geometry_enabled:
		for chunk_coord in loaded_chunks:
			_schedule_organic_cliff_rebuild(chunk_coord, true)
	_restart_pending_stream_builds()


func set_directional_cliff_projection_enabled(enabled: bool) -> void:
	## Phase 3G comparison only. TerrainWorld and saved data are unchanged.
	if directional_cliff_projection_enabled == enabled:
		return
	directional_cliff_projection_enabled = enabled
	for chunk in loaded_chunks.values():
		chunk.set_directional_cliff_projection_enabled(enabled)
	if organic_cliff_geometry_enabled:
		for chunk_coord in loaded_chunks:
			_schedule_organic_cliff_rebuild(chunk_coord, true)
	_restart_pending_stream_builds()


func set_cliff_height_profile(profile: int) -> void:
	## Phase 3F presentation-only projection. Authoritative heights and saves remain unchanged.
	var clamped_profile: int = clampi(
		profile, CliffHeightProfile.BASELINE, CliffHeightProfile.PROMINENT)
	if cliff_height_profile == clamped_profile:
		return
	cliff_height_profile = clamped_profile
	var height_step: int = get_cliff_height_step()
	for chunk in loaded_chunks.values():
		chunk.set_height_step(height_step)
	if environment_object_renderer != null:
		environment_object_renderer.set_height_step(height_step)
	if organic_cliff_geometry_enabled:
		for chunk_coord in loaded_chunks:
			_schedule_organic_cliff_rebuild(chunk_coord, true)
	_restart_pending_stream_builds()
	cliff_height_profile_changed.emit(height_step)


func get_cliff_height_profile() -> int:
	return cliff_height_profile


func get_cliff_height_step() -> int:
	match cliff_height_profile:
		CliffHeightProfile.MODERATE:
			return MODERATE_HEIGHT_STEP
		CliffHeightProfile.PROMINENT:
			return PROMINENT_HEIGHT_STEP
		_:
			return HEIGHT_STEP


func set_cliff_edge_overlays_visible(visible_value: bool) -> void:
	cliff_edge_overlays_visible = visible_value
	for chunk in loaded_chunks.values():
		chunk.set_cliff_edge_overlays_visible(visible_value)


func set_cliff_shadows_visible(visible_value: bool) -> void:
	cliff_shadows_visible = visible_value
	for chunk in loaded_chunks.values():
		chunk.set_cliff_shadows_visible(visible_value)


func is_organic_cliff_geometry_enabled() -> bool:
	return organic_cliff_geometry_enabled


func is_unified_cliff_components_enabled() -> bool:
	return unified_cliff_components_enabled


func is_refined_cliff_silhouettes_enabled() -> bool:
	return refined_cliff_silhouettes_enabled


func is_connected_cliff_contours_enabled() -> bool:
	return connected_cliff_contours_enabled


func is_unified_cliff_contours_enabled() -> bool:
	return unified_cliff_contours_enabled


func get_variant_texture_count() -> int:
	var count: int = 0
	for material_count in variant_count_by_id.values():
		count += int(material_count)
	return count


func get_pending_chunk_count() -> int:
	return _build_jobs.size() + _organic_rebuild_jobs.size()


func get_pending_chunk_retirement_count() -> int:
	return _pending_chunk_retirements.size()


func get_pending_visible_chunk_count() -> int:
	var count: int = 0
	for chunk_coord in _build_jobs:
		if _visible_chunks.has(chunk_coord):
			count += 1
	for chunk_coord in _organic_rebuild_jobs:
		if _visible_chunks.has(chunk_coord):
			count += 1
	return count


func get_incremental_cliff_scheduler_metrics() -> Dictionary:
	return {
		"pending_rebuild_jobs": _organic_rebuild_jobs.size(),
		"geometry_processing_usec_this_frame": organic_geometry_processing_usec_this_frame,
		"worst_geometry_processing_frame_usec": worst_organic_geometry_processing_frame_usec,
		"chunk_processing_usec_this_frame": chunk_processing_usec_this_frame,
		"worst_chunk_processing_frame_usec": worst_chunk_processing_frame_usec,
		"last_chunk_finalisation_usec": last_chunk_finalisation_usec,
		"worst_chunk_finalisation_usec": worst_chunk_finalisation_usec,
		"pending_chunk_retirements": _pending_chunk_retirements.size(),
		"peak_pending_chunk_retirements": peak_pending_chunk_retirements,
		"last_chunk_retirement_usec": last_chunk_retirement_usec,
		"worst_chunk_retirement_usec": worst_chunk_retirement_usec,
		"total_chunk_retirement_usec": profile_total_chunk_retirement_usec,
		"retired_chunks_total": retired_chunks_total,
	}


func reset_incremental_cliff_scheduler_metrics() -> void:
	organic_geometry_processing_usec_this_frame = 0
	worst_organic_geometry_processing_frame_usec = 0
	chunk_processing_usec_this_frame = 0
	worst_chunk_processing_frame_usec = 0
	last_chunk_finalisation_usec = 0
	worst_chunk_finalisation_usec = 0
	last_chunk_retirement_usec = 0
	worst_chunk_retirement_usec = 0
	profile_total_chunk_retirement_usec = 0
	retired_chunks_total = 0
	peak_pending_chunk_retirements = _pending_chunk_retirements.size()


func world_pixel_to_cell(pixel_pos: Vector2) -> Vector2i:
	# Logical cell (x,y) occupies [x*32,(x+1)*32), including for negatives.
	return Vector2i(floori(pixel_pos.x / TILE_SIZE.x), floori(pixel_pos.y / TILE_SIZE.y))


func get_projected_cell_rect(world_pos: Vector2i) -> Rect2:
	var elevation: int = get_world_surface_elevation(world_pos)
	return Rect2(
		Vector2(world_pos * TILE_SIZE) - Vector2(0.0, float(elevation * get_cliff_height_step())),
		Vector2(TILE_SIZE))


func get_projected_cell_polygon(world_pos: Vector2i) -> PackedVector2Array:
	var rect := get_projected_cell_rect(world_pos)
	return PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])


func pick_world_position(pixel_pos: Vector2, target_ground: bool = false) -> Dictionary:
	# Raised cells project upward and can overlap the flat logical cell under
	# the cursor. Resolve the same height ordering used by the visual layers.
	var flat_cell: Vector2i = world_pixel_to_cell(pixel_pos)
	if target_ground:
		return _make_pick(flat_cell, get_world_elevation(flat_cell), false, 0, true)
	var best_pick: Dictionary = {}
	var best_score: int = -1
	var height_step: int = get_cliff_height_step()
	var vertical_reach: int = ceili(float(MAX_ELEVATION * height_step) / TILE_SIZE.y) + 1
	for cell_y in range(flat_cell.y, flat_cell.y + vertical_reach + 1):
		var candidate := Vector2i(flat_cell.x, cell_y)
		var elevation: int = get_world_surface_elevation(candidate)
		if get_projected_cell_rect(candidate).has_point(pixel_pos):
			var score: int = elevation * 10 + 5
			if score > best_score:
				best_score = score
				best_pick = _make_pick(candidate, elevation, false, 0, false)

	for cell_y in range(flat_cell.y - 1, flat_cell.y + vertical_reach + 2):
		var candidate := Vector2i(flat_cell.x, cell_y)
		var elevation: int = get_world_surface_elevation(candidate)
		var south_elevation: int = get_world_surface_elevation(candidate + Vector2i.DOWN)
		if elevation <= south_elevation:
			continue
		var face_rect := Rect2(
			Vector2(
				candidate.x * TILE_SIZE.x,
				(candidate.y + 1) * TILE_SIZE.y - elevation * height_step),
			Vector2(TILE_SIZE.x, (elevation - south_elevation) * height_step))
		var score: int = elevation * 10
		if face_rect.has_point(pixel_pos) and score > best_score:
			best_score = score
			best_pick = _make_pick(
				candidate, elevation, true, elevation - south_elevation, false)
	if best_pick.is_empty():
		best_pick = _make_pick(
			flat_cell, get_world_surface_elevation(flat_cell), false, 0, false)
	return best_pick


func _make_pick(
		cell: Vector2i, elevation: int, is_cliff: bool,
		cliff_drop: int, targets_ground: bool) -> Dictionary:
	return {
		"cell": cell,
		"elevation": elevation,
		"ground_elevation": get_world_elevation(cell),
		"liquid_elevation": get_world_visible_liquid_elevation(cell),
		"material_id": get_world_cell(cell),
		"visible_material_id": get_world_visible_cell(cell),
		"is_cliff": is_cliff,
		"cliff_drop": cliff_drop,
		"targets_ground": targets_ground,
	}


func world_cell_to_chunk(world_pos: Vector2i) -> Vector2i:
	# floori, rather than integer truncation, is required for negative cells.
	return Vector2i(
		floori(float(world_pos.x) / CHUNK_SIZE),
		floori(float(world_pos.y) / CHUNK_SIZE)
	)


func _begin_job_population(job) -> void:
	var phase_start: int = Time.get_ticks_usec()
	var chunk = TerrainChunkRenderer.new()
	chunk.configure(
		job.chunk_coord, render_tileset, cliff_tileset, cliff_edge_tileset,
		decoration_tileset, decoration_atlas_by_id, decoration_context,
		priority_by_id, liquid_by_id,
		get_world_visible_cell, get_world_surface_elevation, get_world_elevation,
		environment_object_renderer.is_ground_cell_occupied,
		decorations_enabled, organic_cliff_geometry_enabled,
		unified_cliff_components_enabled, refined_cliff_silhouettes_enabled,
		connected_cliff_contours_enabled,
		unified_cliff_contours_enabled,
		world_seed,
		organic_cliff_material, job.max_elevation_present, get_cliff_height_step(),
		directional_cliff_projection_enabled)
	chunk.set_cliff_edge_overlays_visible(cliff_edge_overlays_visible)
	chunk.set_cliff_shadows_visible(cliff_shadows_visible)
	job.layer_creation_usec = Time.get_ticks_usec() - phase_start
	phase_start = Time.get_ticks_usec()
	add_child(chunk)
	job.scene_insertion_usec = Time.get_ticks_usec() - phase_start
	job.renderer = chunk


func _finalize_build_job(chunk_coord: Vector2i, job) -> void:
	var finalisation_started_usec: int = Time.get_ticks_usec()
	if organic_cliff_geometry_enabled and job.organic_geometry_enabled:
		var organic_result: Dictionary = job.finalize_organic_geometry()
		job.organic_scene_attachment_usec = job.renderer.apply_prepared_organic_cliffs(
			organic_result)
		_cache_organic_halo(chunk_coord, job)
	_set_resource_aware_chunk_objects(
		chunk_coord,
		job.environment_object_ids,
		job.environment_object_variants,
		job.environment_object_anchor_x,
		job.environment_object_anchor_y,
		job.environment_object_heights)
	loaded_chunks[chunk_coord] = job.renderer
	_build_jobs.erase(chunk_coord)
	_pending_chunks.erase(chunk_coord)
	chunks_finalised_this_frame += 1
	last_chunk_finalisation_usec = Time.get_ticks_usec() - finalisation_started_usec
	worst_chunk_finalisation_usec = maxi(
		worst_chunk_finalisation_usec, last_chunk_finalisation_usec)

	last_chunk_sampling_usec = job.sampling_usec
	last_chunk_mask_usec = job.mask_usec
	last_chunk_cliff_usec = job.cliff_usec
	last_chunk_liquid_surface_usec = job.liquid_surface_usec
	last_chunk_cliff_edge_usec = job.cliff_edge_usec
	last_chunk_organic_cliff_geometry_usec = job.renderer.organic_cliff_geometry_usec
	last_chunk_organic_cliff_mesh_resource_usec = job.organic_mesh_resource_usec
	last_chunk_organic_cliff_scene_attachment_usec = job.organic_scene_attachment_usec
	last_chunk_decoration_usec = job.decoration_usec
	last_chunk_decoration_submission_usec = job.decoration_submission_usec
	last_chunk_environment_usec = job.environment_usec
	last_chunk_tile_placement_usec = job.tile_placement_usec
	last_chunk_layer_creation_usec = job.layer_creation_usec
	last_chunk_scene_insertion_usec = job.scene_insertion_usec
	last_chunk_total_usec = (
		job.sampling_usec + job.mask_usec + job.decoration_usec + job.environment_usec
		+ job.tile_placement_usec
		+ job.layer_creation_usec + job.scene_insertion_usec
		+ last_chunk_organic_cliff_geometry_usec
		+ last_chunk_organic_cliff_scene_attachment_usec)
	total_profiled_chunks += 1
	profile_total_chunk_usec += last_chunk_total_usec
	profile_total_layer_creation_usec += last_chunk_layer_creation_usec
	profile_total_sampling_usec += last_chunk_sampling_usec
	profile_total_mask_usec += last_chunk_mask_usec
	profile_total_cliff_usec += last_chunk_cliff_usec
	profile_total_liquid_surface_usec += last_chunk_liquid_surface_usec
	profile_total_cliff_edge_usec += last_chunk_cliff_edge_usec
	profile_total_organic_cliff_geometry_usec += last_chunk_organic_cliff_geometry_usec
	profile_total_organic_cliff_mesh_resource_usec += last_chunk_organic_cliff_mesh_resource_usec
	profile_total_organic_cliff_scene_attachment_usec += last_chunk_organic_cliff_scene_attachment_usec
	profile_total_decoration_usec += last_chunk_decoration_usec
	profile_total_decoration_submission_usec += last_chunk_decoration_submission_usec
	profile_total_environment_usec += last_chunk_environment_usec
	profile_total_tile_placement_usec += last_chunk_tile_placement_usec
	profile_total_scene_insertion_usec += last_chunk_scene_insertion_usec
	profile_worst_chunk_usec = maxi(profile_worst_chunk_usec, last_chunk_total_usec)


func _discard_build_job(chunk_coord: Vector2i) -> void:
	if _build_jobs.has(chunk_coord):
		var job = _build_jobs[chunk_coord]
		if job.renderer != null:
			_queue_chunk_retirement(job.renderer)
		_build_jobs.erase(chunk_coord)
	_pending_chunks.erase(chunk_coord)


func _restart_build_job(chunk_coord: Vector2i) -> void:
	_discard_build_job(chunk_coord)
	if _wanted_chunks.has(chunk_coord) and not loaded_chunks.has(chunk_coord):
		_build_jobs[chunk_coord] = _create_build_job(chunk_coord)
		_pending_chunks.append(chunk_coord)
		_sort_pending_chunks()


func _create_build_job(chunk_coord: Vector2i):
	var job = TerrainChunkBuildJob.new(chunk_coord)
	job.configure_organic_geometry(
		organic_cliff_geometry_enabled, world_seed, liquid_by_id,
		unified_cliff_components_enabled, refined_cliff_silhouettes_enabled,
		connected_cliff_contours_enabled,
		unified_cliff_contours_enabled,
		int(_organic_geometry_revisions.get(chunk_coord, 0)), profiling_enabled,
		get_cliff_height_step(), directional_cliff_projection_enabled)
	return job


func _restart_pending_stream_builds() -> void:
	var pending_coords: Array = _build_jobs.keys()
	for chunk_coord in pending_coords:
		_restart_build_job(chunk_coord)


func _schedule_organic_cliff_rebuild(
		chunk_coord: Vector2i, reuse_cached_halo: bool = false) -> void:
	if not organic_cliff_geometry_enabled or not loaded_chunks.has(chunk_coord):
		return
	_discard_organic_rebuild_job(chunk_coord)
	var revision: int = int(_organic_geometry_revisions.get(chunk_coord, 0)) + 1
	_organic_geometry_revisions[chunk_coord] = revision
	var job = TerrainChunkBuildJob.new(chunk_coord)
	job.configure_organic_geometry(
		true, world_seed, liquid_by_id,
		unified_cliff_components_enabled, refined_cliff_silhouettes_enabled,
		connected_cliff_contours_enabled,
		unified_cliff_contours_enabled,
		revision, profiling_enabled, get_cliff_height_step(),
		directional_cliff_projection_enabled)
	if reuse_cached_halo and _organic_halo_cache.has(chunk_coord):
		var cached: Dictionary = _organic_halo_cache[chunk_coord]
		if int(cached.revision) == int(_organic_terrain_revisions.get(chunk_coord, 0)):
			job.seed_organic_halo(cached.ids, cached.heights)
	_organic_rebuild_jobs[chunk_coord] = job
	_pending_organic_rebuild_chunks.append(chunk_coord)
	_sort_pending_chunks()


func _discard_organic_rebuild_job(chunk_coord: Vector2i) -> void:
	_organic_rebuild_jobs.erase(chunk_coord)
	_pending_organic_rebuild_chunks.erase(chunk_coord)


func _cache_organic_halo(chunk_coord: Vector2i, job) -> void:
	# This snapshot is bounded by loaded chunks and invalidated by any affected
	# terrain edit. It avoids re-querying unchanged authority on mode changes.
	_organic_halo_cache[chunk_coord] = {
		"ids": job.halo_ids,
		"heights": job.halo_heights,
		"revision": int(_organic_terrain_revisions.get(chunk_coord, 0)),
	}


func _queue_chunk_retirement(chunk: Node) -> void:
	if chunk == null or not is_instance_valid(chunk) or chunk.is_queued_for_deletion():
		return
	if chunk is CanvasItem:
		chunk.visible = false
	_pending_chunk_retirements.append(chunk)
	peak_pending_chunk_retirements = maxi(
		peak_pending_chunk_retirements, _pending_chunk_retirements.size())


func _process_pending_chunk_retirements() -> void:
	last_chunk_retirement_usec = 0
	if _pending_chunk_retirements.is_empty():
		return
	var started_usec: int = Time.get_ticks_usec()
	var chunk_budget: int = maxi(1, max_chunk_retirements_per_frame)
	if not incremental_chunk_retirement_enabled:
		while chunk_budget > 0 and not _pending_chunk_retirements.is_empty():
			var whole_chunk: Node = _pending_chunk_retirements.pop_front()
			if is_instance_valid(whole_chunk) and not whole_chunk.is_queued_for_deletion():
				whole_chunk.queue_free()
				retired_chunks_total += 1
			chunk_budget -= 1
		last_chunk_retirement_usec = Time.get_ticks_usec() - started_usec
		worst_chunk_retirement_usec = maxi(
			worst_chunk_retirement_usec, last_chunk_retirement_usec)
		profile_total_chunk_retirement_usec += last_chunk_retirement_usec
		return
	var node_budget: int = maxi(1, max_chunk_retirement_nodes_per_frame)
	while chunk_budget > 0 and node_budget > 0 and not _pending_chunk_retirements.is_empty():
		var chunk: Node = _pending_chunk_retirements[0]
		if not is_instance_valid(chunk) or chunk.is_queued_for_deletion():
			_pending_chunk_retirements.pop_front()
			continue
		var queued_child: bool = false
		for child in chunk.get_children():
			if child.is_queued_for_deletion():
				continue
			child.queue_free()
			node_budget -= 1
			queued_child = true
			if node_budget <= 0:
				break
		if queued_child:
			# Children are actually released at frame end. Revisit the chunk on
			# the next frame instead of recursively freeing the remaining tree.
			break
		chunk.queue_free()
		_pending_chunk_retirements.pop_front()
		retired_chunks_total += 1
		chunk_budget -= 1
		node_budget -= 1
	last_chunk_retirement_usec = Time.get_ticks_usec() - started_usec
	worst_chunk_retirement_usec = maxi(
		worst_chunk_retirement_usec, last_chunk_retirement_usec)
	profile_total_chunk_retirement_usec += last_chunk_retirement_usec


func _refresh_global_dual_cell(global_dual_pos: Vector2i) -> void:
	var chunk_coord: Vector2i = world_cell_to_chunk(global_dual_pos)
	if loaded_chunks.has(chunk_coord):
		loaded_chunks[chunk_coord].refresh_global_dual_cell(global_dual_pos)


func _refresh_global_cliff_cell(global_cell: Vector2i) -> void:
	var chunk_coord: Vector2i = world_cell_to_chunk(global_cell)
	if loaded_chunks.has(chunk_coord):
		loaded_chunks[chunk_coord].refresh_global_cliff_cell(global_cell)


func _refresh_global_decoration_cell(
		global_cell: Vector2i, sample_cache: Dictionary = {}) -> void:
	var chunk_coord: Vector2i = world_cell_to_chunk(global_cell)
	if loaded_chunks.has(chunk_coord):
		loaded_chunks[chunk_coord].refresh_global_decoration_cell(global_cell, sample_cache)


func _sample_decoration_neighbourhood(center: Vector2i) -> Dictionary:
	var materials: Dictionary = {}
	var ground: Dictionary = {}
	var surface: Dictionary = {}
	for y in range(center.y - 2, center.y + 3):
		for x in range(center.x - 2, center.x + 3):
			var sample_pos := Vector2i(x, y)
			var distance: int = abs(x - center.x) + abs(y - center.y)
			if distance > 2:
				continue
			materials[sample_pos] = get_world_visible_cell(sample_pos)
			surface[sample_pos] = get_world_surface_elevation(sample_pos)
			if distance <= 1:
				ground[sample_pos] = get_world_elevation(sample_pos)
	return {"materials": materials, "ground": ground, "surface": surface}


func _rebuild_environment_objects_near(world_pos: Vector2i) -> Array[Vector2i]:
	if environment_object_renderer == null:
		return []
	var previous_occupied: Dictionary = environment_object_renderer.get_occupied_ground_cells()
	var radius: int = EnvironmentObjectPlacement.MAX_EXCLUSION_RADIUS + 1
	var minimum_chunk: Vector2i = world_cell_to_chunk(world_pos - Vector2i.ONE * radius)
	var maximum_chunk: Vector2i = world_cell_to_chunk(world_pos + Vector2i.ONE * radius)
	for chunk_y in range(minimum_chunk.y, maximum_chunk.y + 1):
		for chunk_x in range(minimum_chunk.x, maximum_chunk.x + 1):
			var chunk_coord := Vector2i(chunk_x, chunk_y)
			if loaded_chunks.has(chunk_coord):
				_rebuild_environment_object_chunk(chunk_coord)
	environment_object_renderer.flush_pending()
	var current_occupied: Dictionary = environment_object_renderer.get_occupied_ground_cells()
	var changed: Array[Vector2i] = []
	for occupied_cell in previous_occupied:
		if not current_occupied.has(occupied_cell):
			changed.append(occupied_cell)
	for occupied_cell in current_occupied:
		if not previous_occupied.has(occupied_cell):
			changed.append(occupied_cell)
	return changed


func _rebuild_environment_object_chunk(chunk_coord: Vector2i) -> void:
	var object_ids := PackedInt32Array()
	var object_variants := PackedByteArray()
	var anchor_x := PackedInt32Array()
	var anchor_y := PackedInt32Array()
	var heights := PackedByteArray()
	if bool(environment_object_context.get("generation_enabled", true)):
		var chunk_origin: Vector2i = chunk_coord * CHUNK_SIZE
		var candidate_cache: Dictionary = {}
		for local_y in range(CHUNK_SIZE):
			for local_x in range(CHUNK_SIZE):
				var anchor: Vector2i = chunk_origin + Vector2i(local_x, local_y)
				var selection: Vector2i = EnvironmentObjectPlacement.choose(
					anchor, environment_object_context,
					get_world_visible_cell, get_world_elevation, get_world_surface_elevation,
					candidate_cache)
				if selection.x < 0:
					continue
				object_ids.append(selection.x)
				object_variants.append(selection.y)
				anchor_x.append(anchor.x)
				anchor_y.append(anchor.y)
				heights.append(get_world_surface_elevation(anchor))
	_set_resource_aware_chunk_objects(
		chunk_coord, object_ids, object_variants,
		anchor_x, anchor_y, heights)


func _set_resource_aware_chunk_objects(
		chunk_coord: Vector2i,
		object_ids: PackedInt32Array,
		object_variants: PackedByteArray,
		anchor_x: PackedInt32Array,
		anchor_y: PackedInt32Array,
		object_heights: PackedByteArray) -> void:
	var filtered_ids := PackedInt32Array()
	var filtered_variants := PackedByteArray()
	var filtered_anchor_x := PackedInt32Array()
	var filtered_anchor_y := PackedInt32Array()
	var filtered_heights := PackedByteArray()
	var resource_ids := PackedStringArray()
	var resource_flags := PackedByteArray()
	var valid_resource_ids: Dictionary = {}
	for index in range(object_ids.size()):
		var object_id: int = int(object_ids[index])
		var definition: Dictionary = environment_object_context["definitions_by_id"][object_id]
		var anchor := Vector2i(anchor_x[index], anchor_y[index])
		var resource_id: String = ""
		var flags: int = 2
		if definition.has("resource_category"):
			var snapshot: Dictionary = resource_state_manager.get_snapshot(object_id, anchor)
			resource_id = String(snapshot["resource_id"])
			valid_resource_ids[resource_id] = true
			var is_food: bool = String(snapshot["category"]) == "food"
			if not bool(snapshot["available"]) and not is_food:
				continue
			flags = (
				(1 if bool(snapshot["designated"]) else 0)
				| (2 if bool(snapshot.get("ripe", true)) else 0)
				| 4)
		filtered_ids.append(object_id)
		filtered_variants.append(object_variants[index])
		filtered_anchor_x.append(anchor.x)
		filtered_anchor_y.append(anchor.y)
		filtered_heights.append(object_heights[index])
		resource_ids.append(resource_id)
		resource_flags.append(flags)
	resource_state_manager.reconcile_missing_designations(
		valid_resource_ids, chunk_coord, CHUNK_SIZE)
	environment_object_renderer.set_chunk_objects(
		chunk_coord, filtered_ids, filtered_variants,
		filtered_anchor_x, filtered_anchor_y, filtered_heights,
		resource_ids, resource_flags)


func _terrain_surface_factory_config() -> Dictionary:
	return {
		"world_seed": world_seed,
		"texture_variation_enabled": texture_variation_enabled,
		"texture_variation_strength": texture_variation_strength,
		"texture_variation_frequency": texture_variation_frequency,
		"grass_detail": {
			"enabled": clustered_grass_detail_enabled,
			"clear_area_coverage": grass_clear_area_coverage,
			"detail_density": grass_detail_density,
			"cluster_scale": grass_cluster_scale,
			"transition_softness": grass_transition_softness,
			"clear_area_residual_density": grass_clear_area_residual_density,
			"seed_offset": grass_detail_seed_offset,
		},
		"grass_surface_variation": {
			"enabled": organic_grass_color_variation_enabled,
			"broad_scale": grass_broad_variation_scale,
			"color_strength": grass_color_variation_strength,
			"fine_strength": grass_fine_variation_strength,
		},
		"grass_texture_repetition": {
			"enabled": grass_texture_repetition_correction_enabled,
		},
		"terrain_texture_repetition": {
			"enabled": terrain_texture_repetition_correction_enabled,
			"material_overrides": terrain_texture_repetition_material_settings,
		},
		"stochastic_terrain_detail": {
			"enabled": stochastic_terrain_detail_enabled,
			"material_overrides": stochastic_terrain_detail_material_settings,
		},
		"remaining_terrain_detail": {
			"enabled": remaining_terrain_detail_enabled,
			"material_overrides": remaining_terrain_detail_material_settings,
		},
		"organic_boundaries_enabled": organic_boundaries_enabled,
		"organic_edge_strength": organic_edge_strength,
		"organic_edge_frequency": organic_edge_frequency,
		"water": {
			"enabled": experimental_water_enhancement_enabled,
			"ripple_strength": water_ripple_strength,
			"secondary_scale": water_secondary_ripple_scale,
			"drift_speed": water_ripple_drift_speed,
			"glint_density": water_glint_density,
			"glint_brightness": water_glint_brightness,
			"repetition_correction_enabled": water_repetition_correction_enabled,
			"repetition_correction_strength": water_repetition_correction_strength,
		},
	}


func _build_shared_tileset() -> void:
	var resources: Dictionary = TerrainSurfaceFactory.create(
		Catalog.MATERIALS, TILE_SIZE, _terrain_surface_factory_config())
	render_tileset = resources["tileset"]
	priority_by_id = resources["priority_by_id"]
	name_by_id = resources["name_by_id"]
	liquid_by_id = resources["liquid_by_id"]
	visual_material_by_id = resources["visual_material_by_id"]
	variant_count_by_id = resources["variant_count_by_id"]


func _build_shared_cliff_tileset() -> void:
	var resources: Dictionary = CliffResourceFactory.create(
		TILE_SIZE, HEIGHT_STEP, world_seed, procedural_cliff_materials_enabled)
	cliff_tileset = resources["cliff_tileset"]
	cliff_edge_tileset = resources["edge_tileset"]
	cliff_material_by_source = resources["materials"]
	cliff_shadow_material_by_source = resources["shadow_materials"]
	organic_cliff_material = resources["organic_material"]
	_apply_cliff_repetition_correction_parameters()


func _build_shared_cliff_edge_tileset() -> void:
	assert(cliff_edge_tileset != null)


func _build_shared_decoration_tileset() -> void:
	var resources: Dictionary = TerrainDetailAtlasFactory.create_decoration_tileset(
		DecorationCatalog.DEFINITIONS, TILE_SIZE, _draw_decoration_variant)
	decoration_tileset = resources["tileset"]
	decoration_atlas_by_id = resources["atlas_by_id"]


func _build_shared_environment_object_atlas() -> void:
	var resources: Dictionary = TerrainDetailAtlasFactory.create_environment_atlases(
		EnvironmentObjectCatalog.DEFINITIONS, procedural_vegetation_enabled,
		_draw_environment_object_variant)
	environment_object_atlas_texture = resources["active_texture"]
	environment_object_procedural_atlas_texture = resources["procedural_texture"]
	environment_object_legacy_tree_atlas_texture = resources["legacy_tree_texture"]
	environment_object_atlas_by_id = resources["atlas_by_id"]
	environment_object_unripe_atlas_by_id = resources["unripe_atlas_by_id"]
	environment_atlas_variant_count = resources["variant_count"]
	environment_procedural_variant_count = resources["procedural_variant_count"]
	environment_procedural_tree_variant_count = resources["procedural_tree_variant_count"]
	environment_atlas_dimensions = resources["dimensions"]
	environment_legacy_atlas_generation_usec = resources["legacy_generation_usec"]
	environment_atlas_generation_usec = resources["generation_usec"]

func _draw_environment_object_variant(
		image: Image, atlas_x: int,
		definition: Dictionary, variant: int) -> void:
	var origin := Vector2i(atlas_x * 96, 0)
	var root := origin + Vector2i(48, 89)
	var kind: String = String(definition["kind"])
	var jitter: int = variant % 3 - 1
	match kind:
		"deciduous_small", "deciduous_large":
			var large: bool = kind == "deciduous_large"
			var trunk_height: int = 43 if large else 34
			var trunk_half_width: int = 4 if large else 3
			_fill_object_rect(image, Rect2i(
				root + Vector2i(-trunk_half_width, -trunk_height),
				Vector2i(trunk_half_width * 2 + 1, trunk_height)), Color("69462f"))
			_fill_object_rect(image, Rect2i(
				root + Vector2i(-1, -trunk_height),
				Vector2i(3, trunk_height - 3)), Color("9a6740"))
			var canopy_y: int = root.y - trunk_height - (9 if large else 6)
			var dark := Color("24552d")
			var middle: Color = [Color("39743a"), Color("467f3e"), Color("326b38")][variant % 3]
			var light := Color("72a94c")
			var radius_x: int = 23 if large else 17
			var radius_y: int = 18 if large else 14
			_draw_object_blob(image, Vector2i(root.x - radius_x / 2, canopy_y + 3), radius_x, radius_y, dark, middle, light)
			_draw_object_blob(image, Vector2i(root.x + radius_x / 2, canopy_y + 2), radius_x, radius_y, dark, middle, light)
			_draw_object_blob(image, Vector2i(root.x + jitter, canopy_y - 8), radius_x, radius_y, dark, middle, light)
		"conifer":
			_fill_object_rect(image, Rect2i(root + Vector2i(-3, -48), Vector2i(7, 48)), Color("68472f"))
			var conifer_dark := Color("1f4d39")
			var conifer_mid: Color = [Color("2f6b45"), Color("386f48"), Color("285f42")][variant % 3]
			var conifer_light := Color("5d9160")
			for tier in range(4):
				var tier_y: int = root.y - 22 - tier * 14
				var half_width: int = 22 - tier * 4
				for row in range(13):
					var row_half: int = maxi(1, floori(float(row + 2) / 13.0 * half_width))
					var color: Color = conifer_light if row < 3 else (conifer_mid if row < 10 else conifer_dark)
					_fill_object_rect(image, Rect2i(
						Vector2i(root.x - row_half, tier_y - 12 + row),
						Vector2i(row_half * 2 + 1, 1)), color)
		"dead_tree":
			var dead_dark := Color("4d392d")
			var dead_light := Color("896846")
			for width in range(-3, 4):
				_draw_line(image, root + Vector2i(width, 0), root + Vector2i(width + jitter, -58), dead_dark if abs(width) == 3 else dead_light)
			_draw_line(image, root + Vector2i(0, -35), root + Vector2i(-17, -50), dead_light)
			_draw_line(image, root + Vector2i(1, -29), root + Vector2i(18, -43), dead_dark)
			_draw_line(image, root + Vector2i(-13, -47), root + Vector2i(-20, -55), dead_dark)
		"shrub_small", "bush_large", "shore_bush":
			var large_bush: bool = kind == "bush_large"
			var shore: bool = kind == "shore_bush"
			var bush_dark := Color("28513a") if shore else Color("26572d")
			var bush_mid := Color("3e7650") if shore else Color("4b833b")
			var bush_light := Color("79a86c") if shore else Color("78aa49")
			var bush_rx: int = 20 if large_bush else 14
			var bush_ry: int = 12 if large_bush else 9
			_draw_object_blob(image, root + Vector2i(-bush_rx / 2, -8), bush_rx, bush_ry, bush_dark, bush_mid, bush_light)
			_draw_object_blob(image, root + Vector2i(bush_rx / 2, -7), bush_rx, bush_ry, bush_dark, bush_mid, bush_light)
		"shrub_dry":
			for branch in range(-4, 5, 2):
				_draw_line(image, root + Vector2i(branch, 0), root + Vector2i(branch * 3, -22 + abs(branch)), Color("9c7641"))
				_draw_line(image, root + Vector2i(branch, -10), root + Vector2i(branch * 3 + 5, -17), Color("c09352"))
		"boulder_small", "boulder_large", "outcrop", "stone_group":
			var rx: int = 16
			var ry: int = 10
			if kind == "boulder_large":
				rx = 26; ry = 16
			elif kind == "outcrop":
				rx = 31; ry = 21
			elif kind == "stone_group":
				rx = 18; ry = 9
			_draw_object_blob(image, root + Vector2i(jitter, -ry + 1), rx, ry, Color("46545b"), Color("6f7c80"), Color("a9b2b1"))
			if kind in ["outcrop", "stone_group"]:
				_draw_object_blob(image, root + Vector2i(-rx / 2, -5), rx / 2, ry / 2, Color("3e4c53"), Color("68767a"), Color("9aa6a7"))
		"fallen_log":
			_fill_object_rect(image, Rect2i(root + Vector2i(-27, -13), Vector2i(54, 12)), Color("59412f"))
			_fill_object_rect(image, Rect2i(root + Vector2i(-25, -11), Vector2i(48, 4)), Color("906442"))
			_draw_object_blob(image, root + Vector2i(27, -7), 7, 7, Color("49362b"), Color("78543a"), Color("b07a49"))
			_draw_line(image, root + Vector2i(-12, -12), root + Vector2i(-4, -22), Color("664a32"))
		"stump":
			_fill_object_rect(image, Rect2i(root + Vector2i(-8, -18), Vector2i(17, 18)), Color("684832"))
			_draw_object_blob(image, root + Vector2i(0, -18), 9, 5, Color("4b392d"), Color("986a43"), Color("c89557"))
			_draw_line(image, root + Vector2i(-5, -19), root + Vector2i(5, -17), Color("4e382b"))
		"deadwood":
			_draw_line(image, root + Vector2i(-22, -2), root + Vector2i(22, -18), Color("5a4332"))
			_draw_line(image, root + Vector2i(-21, 0), root + Vector2i(23, -16), Color("8a6542"))
			_draw_line(image, root + Vector2i(5, -12), root + Vector2i(17, -28), Color("705039"))


func _draw_object_blob(
		image: Image, center: Vector2i,
		radius_x: int, radius_y: int,
		dark: Color, middle: Color, light: Color) -> void:
	for y in range(-radius_y, radius_y + 1):
		var normalized_y: float = float(y) / maxf(1.0, radius_y)
		var row_half: int = floori(radius_x * sqrt(maxf(0.0, 1.0 - normalized_y * normalized_y)))
		var row_color: Color = light if y < -radius_y / 3 else (middle if y < radius_y * 2 / 3 else dark)
		_fill_object_rect(image, Rect2i(
			center + Vector2i(-row_half, y), Vector2i(row_half * 2 + 1, 1)), row_color)
	_put_pixel(image, center + Vector2i(-radius_x / 3, -radius_y / 2), light.lightened(0.12))


func _fill_object_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_put_pixel(image, Vector2i(x, y), color)


func _draw_decoration_variant(
		image: Image, atlas_x: int,
		definition: Dictionary, variant: int) -> void:
	var origin := Vector2i(atlas_x * TILE_SIZE.x, 0)
	var visual_offset: Vector2i = definition.get("visual_offset", Vector2i.ZERO)
	var scale: float = float(definition.get("scale", 1.0))
	var jitter_x: int = posmod(
		int(definition["id"]) * 7 + variant * 11, 9) - 4
	var base := origin + Vector2i(16 + jitter_x, 14) + visual_offset
	var size: int = maxi(1, roundi(3.0 * scale)) + (1 if variant % 3 == 0 else 0)
	var kind: String = String(definition["kind"])

	match kind:
		"tuft", "cliff_tuft":
			var dark := Color("285b2b") if kind == "tuft" else Color("4d642c")
			var light := Color("82bd55") if kind == "tuft" else Color("a4bd61")
			_draw_line(image, base + Vector2i(-size, 0), base + Vector2i(-size - 1, -5), dark)
			_draw_line(image, base, base + Vector2i(variant % 3 - 1, -7), light)
			_draw_line(image, base + Vector2i(size, 0), base + Vector2i(size + 1, -4), dark)
			_draw_line(image, base + Vector2i(-size, 1), base + Vector2i(size, 1), dark)
		"flower":
			_draw_line(image, base, base + Vector2i(0, -6), Color("326b31"))
			_put_pixel(image, base + Vector2i(-1, -3), Color("72a84c"))
			var flower_color: Color = [Color("f2db72"), Color("e69bb2"), Color("d6c6ff"), Color("f4f0dc")][variant % 4]
			var flower_pos := base + Vector2i(0, -7)
			for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				_put_pixel(image, flower_pos + offset, flower_color)
			_put_pixel(image, flower_pos, Color("d08b42"))
		"shrub":
			_draw_blob(image, base + Vector2i(0, -3), 4 + variant % 2, Color("254f2c"), Color("72a649"))
			_draw_blob(image, base + Vector2i(-3, -2), 3, Color("315f32"), Color("6b9d48"))
			_draw_blob(image, base + Vector2i(3, -2), 3, Color("315f32"), Color("567f3b"))
		"dry_grass":
			for stem in range(-2, 3, 2):
				_draw_line(
					image, base + Vector2i(stem, 0),
					base + Vector2i(stem + (1 if stem >= 0 else -1), -4 - abs(stem)),
					Color("c0924b"))
			_draw_line(image, base + Vector2i(-3, 1), base + Vector2i(3, 1), Color("72532e"))
		"reeds":
			for stem in range(-3, 4, 2):
				var height: int = 7 + posmod(stem + variant, 3)
				_draw_line(image, base + Vector2i(stem, 0), base + Vector2i(stem, -height), Color("6f8b42"))
				_put_pixel(image, base + Vector2i(stem, -height), Color("9d7445"))
			_draw_line(image, base + Vector2i(-4, 1), base + Vector2i(4, 1), Color("405c35"))
		"wet_grass":
			for stem in range(-3, 4, 2):
				_draw_line(image, base + Vector2i(stem, 0), base + Vector2i(stem + signi(stem), -6), Color("3a7049"))
			_put_pixel(image, base + Vector2i(2, -2), Color("8bc0a5"))
		"drift":
			_draw_line(image, base + Vector2i(-6, 1), base + Vector2i(6, 1), Color("aabfc8"))
			_draw_line(image, base + Vector2i(-5, 0), base + Vector2i(5, 0), Color("d7e6ec"))
			_draw_line(image, base + Vector2i(-3, -1), base + Vector2i(3, -1), Color("f1f7f8"))
			_draw_line(image, base + Vector2i(-1, -2), base + Vector2i(2, -2), Color("ffffff"))
		"rock", "snow_stone":
			var rock_dark := Color("46545b") if kind == "rock" else Color("68747b")
			var rock_light := Color("b0bcbd") if kind == "rock" else Color("ced8da")
			_draw_blob(image, base + Vector2i(0, -2), 4 + variant % 2, rock_dark, rock_light)
		"pebbles", "sand_pebbles", "stone_detail", "gravel":
			var colors := [Color("6d6259"), Color("9a8b72")]
			if kind == "sand_pebbles":
				colors = [Color("a88d68"), Color("d2b889")]
			elif kind in ["stone_detail", "gravel"]:
				colors = [Color("67747a"), Color("a2aaab")]
			for pebble in range(4):
				var px: int = posmod(variant * 5 + pebble * 7, 11) - 5
				var py: int = -posmod(variant + pebble * 3, 4)
				_draw_blob(image, base + Vector2i(px, py), 1 + (pebble & 1), colors[0], colors[1])
		"debris":
			var debris_color := Color("554b45")
			_draw_line(image, base + Vector2i(-4, -1), base + Vector2i(1, -3), debris_color)
			_draw_line(image, base + Vector2i(2, 0), base + Vector2i(5, -4), Color("a58d6e"))
			_put_pixel(image, base + Vector2i(-2, -4), Color("c3b8a8"))


func _draw_blob(
		image: Image, center: Vector2i, radius: int,
		dark: Color, light: Color) -> void:
	var half_height: int = maxi(1, radius / 2)
	for y in range(-half_height, 1):
		var row_width: int = radius - abs(y)
		for x in range(-row_width, row_width + 1):
			_put_pixel(image, center + Vector2i(x, y), dark if y == 0 else light)
	_put_pixel(image, center + Vector2i(-1, -half_height), light.lightened(0.12))


func _draw_line(image: Image, start: Vector2i, finish: Vector2i, color: Color) -> void:
	var delta := finish - start
	var steps: int = maxi(abs(delta.x), abs(delta.y))
	if steps == 0:
		_put_pixel(image, start, color)
		return
	for step in range(steps + 1):
		var t: float = float(step) / steps
		_put_pixel(image, Vector2i(Vector2(start).lerp(Vector2(finish), t).round()), color)


func _put_pixel(image: Image, point: Vector2i, color: Color) -> void:
	if point.x < 0 or point.y < 0 or point.x >= image.get_width() or point.y >= image.get_height():
		return
	image.set_pixel(point.x, point.y, color)

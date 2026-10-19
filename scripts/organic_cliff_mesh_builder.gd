extends RefCounted
## Builds presentation-only, pixel-quantised cliff meshes for one terrain
## chunk. Every outline sample is derived from absolute world coordinates, so
## independently built neighbouring chunks produce identical seam vertices.

const CHUNK_SIZE := 32
const TILE_SIZE := 32
const HEIGHT_STEP := 16
const PROFILE_STEP := 16
const COLUMN_COUNT := TILE_SIZE / PROFILE_STEP
const RETURN_PROFILE_STEP := 8
const REFINED_RETURN_STEP := 16
const HALO_MARGIN := 1
const HALO_SIZE := CHUNK_SIZE + HALO_MARGIN * 2
const HALO_CELL_COUNT := HALO_SIZE * HALO_SIZE


static func build(
		chunk_coord: Vector2i, max_elevation: int, world_seed: int,
		world_lookup: Callable, height_lookup: Callable,
		liquid_by_id: Dictionary,
		unified_components_enabled: bool = false,
		refined_silhouettes_enabled: bool = false) -> Dictionary:
	var started_usec: int = Time.get_ticks_usec()
	var sampling_started_usec: int = Time.get_ticks_usec()
	# One bounded halo read replaces repeated height/material callbacks from the
	# face, return, and shadow builders. The sampled data remains presentation-
	# only and is discarded when this chunk batch is complete.
	var halo_heights := PackedInt32Array()
	var halo_ids := PackedInt32Array()
	halo_heights.resize(HALO_CELL_COUNT)
	halo_ids.resize(HALO_CELL_COUNT)
	var halo_world_origin: Vector2i = chunk_coord * CHUNK_SIZE - Vector2i.ONE
	for sample_y in range(HALO_SIZE):
		for sample_x in range(HALO_SIZE):
			var sample_index: int = sample_y * HALO_SIZE + sample_x
			var sample_pos := halo_world_origin + Vector2i(sample_x, sample_y)
			halo_heights[sample_index] = int(height_lookup.call(sample_pos))
			halo_ids[sample_index] = int(world_lookup.call(sample_pos))
	var sampling_usec: int = Time.get_ticks_usec() - sampling_started_usec
	var state: Dictionary = create_incremental(
		chunk_coord, max_elevation, world_seed, halo_ids, halo_heights,
		liquid_by_id, unified_components_enabled, refined_silhouettes_enabled, true)
	process_incremental(state, CHUNK_SIZE * CHUNK_SIZE)
	var result: Dictionary = finalize_incremental(state)
	result.sampling_usec = sampling_usec
	result.height_query_count = HALO_CELL_COUNT
	result.material_query_count = HALO_CELL_COUNT
	result.build_usec = Time.get_ticks_usec() - started_usec
	return result


static func create_incremental(
		chunk_coord: Vector2i, max_elevation: int, world_seed: int,
		halo_ids: PackedInt32Array, halo_heights,
		liquid_by_id: Dictionary, unified_components_enabled: bool,
		refined_silhouettes_enabled: bool,
		profiling_enabled: bool = false) -> Dictionary:
	## The caller owns the immutable 34x34 snapshot. All mutable state below is
	## presentation-only and can be discarded safely when a chunk is invalidated.
	return {
		"chunk_coord": chunk_coord,
		"max_elevation": max_elevation,
		"world_seed": world_seed,
		"halo_ids": halo_ids,
		"halo_heights": halo_heights,
		"liquid_by_id": liquid_by_id,
		"unified_components_enabled": unified_components_enabled,
		"refined_silhouettes_enabled": refined_silhouettes_enabled,
		"profiling_enabled": profiling_enabled,
		"cell_index": 0,
		"buffers": {},
		"edge_buffers": {},
		"shadow_buffers": {},
		"face_count": 0,
		"edge_component_count": 0,
		"shadow_count": 0,
		"triangle_count": 0,
		"face_construction_usec": 0,
		"contour_generation_usec": 0,
		"vertex_assembly_usec": 0,
		"profile_metrics": ({"vertex_assembly_usec": 0} if profiling_enabled else {}),
	}


static func process_incremental(state: Dictionary, max_cells: int) -> int:
	var start_index: int = int(state.cell_index)
	var end_index: int = mini(start_index + maxi(1, max_cells), CHUNK_SIZE * CHUNK_SIZE)
	for cell_index in range(start_index, end_index):
		_process_cell(state, cell_index)
	state.cell_index = end_index
	return end_index - start_index


static func is_incremental_ready(state: Dictionary) -> bool:
	return int(state.get("cell_index", 0)) >= CHUNK_SIZE * CHUNK_SIZE


static func _process_cell(state: Dictionary, cell_index: int) -> void:
	var profiling_enabled: bool = bool(state.profiling_enabled)
	var started_usec: int = Time.get_ticks_usec() if profiling_enabled else 0
	var local_x: int = cell_index % CHUNK_SIZE
	var local_y: int = floori(float(cell_index) / CHUNK_SIZE)
	var world_pos: Vector2i = state.chunk_coord * CHUNK_SIZE + Vector2i(local_x, local_y)
	var center_index: int = (
		(local_y + HALO_MARGIN) * HALO_SIZE + local_x + HALO_MARGIN)
	var halo_heights = state.halo_heights
	var halo_ids: PackedInt32Array = state.halo_ids
	var liquid_by_id: Dictionary = state.liquid_by_id
	var owner_height: int = int(halo_heights[center_index])
	if owner_height <= 0 or owner_height > int(state.max_elevation):
		if profiling_enabled:
			state.face_construction_usec += Time.get_ticks_usec() - started_usec
		return
	var terrain_id: int = int(halo_ids[center_index])
	if bool(liquid_by_id.get(terrain_id, false)):
		if profiling_enabled:
			state.face_construction_usec += Time.get_ticks_usec() - started_usec
		return
	var north_index: int = center_index - HALO_SIZE
	var south_index: int = center_index + HALO_SIZE
	var west_index: int = center_index - 1
	var east_index: int = center_index + 1
	var north_height: int = int(halo_heights[north_index])
	var south_height: int = int(halo_heights[south_index])
	var west_height: int = int(halo_heights[west_index])
	var east_height: int = int(halo_heights[east_index])
	var west_south_height: int = int(halo_heights[west_index + HALO_SIZE])
	var east_south_height: int = int(halo_heights[east_index + HALO_SIZE])
	var left_connected: bool = _has_face_values(
		int(halo_ids[west_index]), west_height,
		west_south_height,
		south_height, owner_height, liquid_by_id)
	var right_connected: bool = _has_face_values(
		int(halo_ids[east_index]), east_height,
		east_south_height,
		south_height, owner_height, liquid_by_id)
	var left_top_connected: bool = _face_band_connected(
		left_connected, west_south_height, west_height,
		owner_height - 1, owner_height)
	var right_top_connected: bool = _face_band_connected(
		right_connected, east_south_height, east_height,
		owner_height - 1, owner_height)
	var left_foot_connected: bool = (
		left_connected and west_south_height == south_height)
	var right_foot_connected: bool = (
		right_connected and east_south_height == south_height)
	if profiling_enabled:
		state.face_construction_usec += Time.get_ticks_usec() - started_usec

	if owner_height > south_height:
		var south_is_liquid: bool = bool(liquid_by_id.get(int(halo_ids[south_index]), false))
		var source_id: int = _cliff_source_for(terrain_id, south_is_liquid)
		if not state.buffers.has(owner_height):
			state.buffers[owner_height] = _new_buffer()
		var geometry_started_usec: int = Time.get_ticks_usec() if profiling_enabled else 0
		var vertex_started_usec: int = int(state.profile_metrics.get("vertex_assembly_usec", 0))
		var result: Vector2i = _append_face(
			state.buffers[owner_height], local_x, local_y, world_pos,
			owner_height, south_height, source_id, int(state.world_seed),
			left_connected, right_connected,
			west_south_height, west_height, east_south_height, east_height,
			state.profile_metrics)
		var geometry_elapsed_usec: int = (
			Time.get_ticks_usec() - geometry_started_usec if profiling_enabled else 0)
		var vertex_elapsed_usec: int = (
			int(state.profile_metrics.get("vertex_assembly_usec", 0)) - vertex_started_usec)
		state.contour_generation_usec += maxi(0, geometry_elapsed_usec - vertex_elapsed_usec)
		state.face_count += 1
		state.triangle_count += result.y
		if bool(state.unified_components_enabled) and not south_is_liquid:
			if not state.shadow_buffers.has(owner_height):
				state.shadow_buffers[owner_height] = _new_buffer()
			geometry_started_usec = Time.get_ticks_usec() if profiling_enabled else 0
			vertex_started_usec = int(state.profile_metrics.get("vertex_assembly_usec", 0))
			state.triangle_count += _append_contact_shadow(
				state.shadow_buffers[owner_height], local_x, local_y, world_pos,
				owner_height, south_height, source_id, int(state.world_seed),
				left_foot_connected, right_foot_connected, state.profile_metrics)
			geometry_elapsed_usec = (
				Time.get_ticks_usec() - geometry_started_usec if profiling_enabled else 0)
			vertex_elapsed_usec = (
				int(state.profile_metrics.get("vertex_assembly_usec", 0)) - vertex_started_usec)
			state.contour_generation_usec += maxi(0, geometry_elapsed_usec - vertex_elapsed_usec)
			state.shadow_count += 1
	if bool(state.unified_components_enabled) and (
			north_height < owner_height or west_height < owner_height
			or east_height < owner_height):
		if not state.edge_buffers.has(owner_height):
			state.edge_buffers[owner_height] = _new_buffer()
		var geometry_started_usec: int = Time.get_ticks_usec() if profiling_enabled else 0
		var vertex_started_usec: int = int(state.profile_metrics.get("vertex_assembly_usec", 0))
		var edge_result: Vector2i = _append_edge_components(
			state.edge_buffers[owner_height], local_x, local_y, world_pos,
			owner_height, terrain_id, int(state.world_seed), liquid_by_id,
			north_height, west_height, east_height, south_height,
			int(halo_ids[north_index]), int(halo_ids[west_index]),
			int(halo_ids[east_index]), bool(state.refined_silhouettes_enabled),
			left_top_connected, right_top_connected, state.profile_metrics)
		var geometry_elapsed_usec: int = (
			Time.get_ticks_usec() - geometry_started_usec if profiling_enabled else 0)
		var vertex_elapsed_usec: int = (
			int(state.profile_metrics.get("vertex_assembly_usec", 0)) - vertex_started_usec)
		state.contour_generation_usec += maxi(0, geometry_elapsed_usec - vertex_elapsed_usec)
		state.edge_component_count += edge_result.x
		state.triangle_count += edge_result.y


static func finalize_incremental(state: Dictionary) -> Dictionary:
	assert(is_incremental_ready(state), "Cannot finalize an incomplete cliff geometry job")
	var mesh_started_usec: int = Time.get_ticks_usec()
	var face_result: Dictionary = _buffers_to_meshes(state.buffers, int(state.max_elevation))
	var edge_result: Dictionary = _buffers_to_meshes(state.edge_buffers, int(state.max_elevation))
	var shadow_result: Dictionary = _buffers_to_meshes(state.shadow_buffers, int(state.max_elevation))
	var mesh_resource_usec: int = Time.get_ticks_usec() - mesh_started_usec
	var vertex_count: int = int(face_result.vertex_count) + int(edge_result.vertex_count) + int(shadow_result.vertex_count)
	return {
		"meshes": face_result.meshes,
		"edge_meshes": edge_result.meshes,
		"shadow_meshes": shadow_result.meshes,
		"face_count": int(state.face_count),
		"edge_component_count": int(state.edge_component_count),
		"shadow_count": int(state.shadow_count),
		"surface_count": int(face_result.surface_count) + int(edge_result.surface_count) + int(shadow_result.surface_count),
		"vertex_count": vertex_count,
		"triangle_count": int(state.triangle_count),
		"height_query_count": 0,
		"material_query_count": 0,
		"sampling_usec": 0,
		"face_construction_usec": int(state.face_construction_usec),
		"contour_generation_usec": int(state.contour_generation_usec),
		# Packed-array insertion is the vertex-assembly work performed while the
		# contour builders run; report it explicitly without double-counting it in
		# total CPU work.
		"vertex_assembly_usec": int(state.profile_metrics.get("vertex_assembly_usec", 0)),
		"mesh_resource_usec": mesh_resource_usec,
		"build_usec": int(state.face_construction_usec) + int(state.contour_generation_usec)
			+ int(state.profile_metrics.get("vertex_assembly_usec", 0)) + mesh_resource_usec,
	}


static func _buffers_to_meshes(buffers: Dictionary, max_elevation: int) -> Dictionary:
	var meshes: Array = []
	meshes.resize(max_elevation)
	var surface_count: int = 0
	var vertex_count: int = 0
	for elevation in range(1, max_elevation + 1):
		if not buffers.has(elevation):
			continue
		var buffer: Dictionary = buffers[elevation]
		if buffer.vertices.is_empty():
			continue
		var mesh := ArrayMesh.new()
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = buffer.vertices
		arrays[Mesh.ARRAY_COLOR] = buffer.colors
		arrays[Mesh.ARRAY_INDEX] = buffer.indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		meshes[elevation - 1] = mesh
		surface_count += 1
		vertex_count += buffer.vertices.size()
	return {
		"meshes": meshes,
		"surface_count": surface_count,
		"vertex_count": vertex_count,
	}


static func outline_offset(
		world_pixel_x: int, contour_world_y: int,
		level: int, world_seed: int, channel: int) -> int:
	## Public for seam regression tests. Inputs are absolute and integer-only.
	var sample_x: int = floori(float(world_pixel_x) / PROFILE_STEP)
	var coarse_x: int = floori(float(sample_x) / 4.0)
	var coarse: int = _hash_int(coarse_x, contour_world_y, level, world_seed, channel)
	var fine: int = _hash_int(sample_x, contour_world_y, level, world_seed, channel + 17)
	return clampi(posmod(coarse, 5) - 2 + posmod(fine, 3) - 1, -3, 3)


static func _append_face(
		buffer: Dictionary, local_x: int, local_y: int, world_pos: Vector2i,
		owner_height: int, south_height: int, source_id: int, world_seed: int,
		left_connected: bool, right_connected: bool,
		left_minimum: int, left_maximum: int,
		right_minimum: int, right_maximum: int,
		profile_metrics: Dictionary) -> Vector2i:
	var local_left: int = local_x * TILE_SIZE
	var local_top_base: int = local_y * TILE_SIZE + TILE_SIZE - owner_height * HEIGHT_STEP
	var local_bottom_base: int = local_y * TILE_SIZE + TILE_SIZE - south_height * HEIGHT_STEP
	var world_left: int = world_pos.x * TILE_SIZE
	var face_height: int = local_bottom_base - local_top_base
	var row_count: int = maxi(1, ceili(float(face_height) / PROFILE_STEP))
	var boundary_samples: Array[PackedInt32Array] = []
	for boundary in range(row_count + 1):
		var level: int = owner_height - boundary
		var samples := PackedInt32Array()
		for column in range(COLUMN_COUNT + 1):
			var world_x: int = world_left + column * PROFILE_STEP
			samples.append(_face_level_offset(
				world_x, world_pos.y, level, world_seed))
		boundary_samples.append(samples)
	var triangles_before: int = buffer.indices.size() / 3
	for row in range(row_count):
		var t0: float = float(row) / row_count
		var t1: float = float(row + 1) / row_count
		var band_maximum: int = owner_height - row
		var band_minimum: int = band_maximum - 1
		var left_row_connected: bool = _face_band_connected(
			left_connected, left_minimum, left_maximum,
			band_minimum, band_maximum)
		var right_row_connected: bool = _face_band_connected(
			right_connected, right_minimum, right_maximum,
			band_minimum, band_maximum)
		var left_above_connected: bool = _face_band_connected(
			left_connected, left_minimum, left_maximum,
			band_maximum, band_maximum + 1)
		var right_above_connected: bool = _face_band_connected(
			right_connected, right_minimum, right_maximum,
			band_maximum, band_maximum + 1)
		var left_below_connected: bool = _face_band_connected(
			left_connected, left_minimum, left_maximum,
			band_minimum - 1, band_minimum)
		var right_below_connected: bool = _face_band_connected(
			right_connected, right_minimum, right_maximum,
			band_minimum - 1, band_minimum)
		for column in range(COLUMN_COUNT):
			var x00: float = local_left + column * PROFILE_STEP
			var x10: float = x00 + PROFILE_STEP
			var x01: float = x00
			var x11: float = x10
			if column == 0:
				if not left_row_connected and not left_above_connected:
					x00 += _face_cap_offset(world_pos, t0, world_seed, true)
				if not left_row_connected and not left_below_connected:
					x01 += _face_cap_offset(world_pos, t1, world_seed, true)
			if column == COLUMN_COUNT - 1:
				if not right_row_connected and not right_above_connected:
					x10 += _face_cap_offset(world_pos, t0, world_seed, false)
				if not right_row_connected and not right_below_connected:
					x11 += _face_cap_offset(world_pos, t1, world_seed, false)
			var row_top: int = local_y * TILE_SIZE + TILE_SIZE - band_maximum * HEIGHT_STEP
			var row_bottom: int = row_top + HEIGHT_STEP
			var y00: float = row_top + boundary_samples[row][column]
			var y10: float = row_top + boundary_samples[row][column + 1]
			var y01: float = row_bottom + boundary_samples[row + 1][column]
			var y11: float = row_bottom + boundary_samples[row + 1][column + 1]
			var shade: float = _facet_shade(world_pos, column, row, source_id, world_seed)
			_append_quad(
				buffer, Vector2(x00, y00), Vector2(x10, y10),
				Vector2(x11, y11), Vector2(x01, y01), shade, source_id,
				_hash_int(world_pos.x * 4 + column, world_pos.y * 4 + row,
					owner_height, world_seed, source_id) & 1, 0, 1.0,
				profile_metrics)
	return Vector2i(1, buffer.indices.size() / 3 - triangles_before)


static func _append_quad(
		buffer: Dictionary, top_left: Vector2, top_right: Vector2,
		bottom_right: Vector2, bottom_left: Vector2,
		shade: float, source_id: int, diagonal: int,
		component_role: int = 0, alpha: float = 1.0,
		profile_metrics: Dictionary = {}) -> void:
	var profile_assembly: bool = not profile_metrics.is_empty()
	var assembly_started_usec: int = Time.get_ticks_usec() if profile_assembly else 0
	var base: int = buffer.vertices.size()
	buffer.vertices.append_array(PackedVector2Array([
		top_left.round(), top_right.round(), bottom_right.round(), bottom_left.round()]))
	var encoded_source: float = float(source_id) / 3.0
	var encoded_role: float = float(component_role) / 3.0
	var light := Color(shade, encoded_source, encoded_role, alpha)
	var dark_shade: float = clampf(shade - 0.055, 0.78, 1.12)
	var dark := Color(dark_shade, encoded_source, encoded_role, alpha)
	buffer.colors.append_array(PackedColorArray([light, light, dark, dark]))
	if diagonal == 0:
		buffer.indices.append_array(PackedInt32Array([
			base, base + 1, base + 2, base, base + 2, base + 3]))
	else:
		buffer.indices.append_array(PackedInt32Array([
			base, base + 1, base + 3, base + 1, base + 2, base + 3]))
	if profile_assembly:
		profile_metrics.vertex_assembly_usec += Time.get_ticks_usec() - assembly_started_usec


static func _append_edge_components(
		buffer: Dictionary, local_x: int, local_y: int, world_pos: Vector2i,
		owner_height: int, terrain_id: int, world_seed: int,
		liquid_by_id: Dictionary, north_height: int, west_height: int,
		east_height: int, south_height: int, north_id: int, west_id: int,
		east_id: int, refined_silhouettes_enabled: bool,
		left_connected: bool, right_connected: bool,
		profile_metrics: Dictionary) -> Vector2i:
	var component_count: int = 0
	var triangles_before: int = buffer.indices.size() / 3
	if north_height < owner_height:
		var north_source: int = _cliff_source_for(
			terrain_id, bool(liquid_by_id.get(north_id, false)))
		_append_north_lip(
			buffer, local_x, local_y, world_pos, owner_height,
			north_source, world_seed, profile_metrics)
		component_count += 1
	if west_height < owner_height:
		var west_source: int = _cliff_source_for(
			terrain_id, bool(liquid_by_id.get(west_id, false)))
		if refined_silhouettes_enabled:
			_append_refined_side_return(
				buffer, local_x, local_y, world_pos, owner_height,
				west_height, south_height, west_source, world_seed, true,
				left_connected, profile_metrics)
		else:
			_append_side_return(
				buffer, local_x, local_y, world_pos, owner_height,
				west_height, west_source, world_seed, true, profile_metrics)
		component_count += 1
	if east_height < owner_height:
		var east_source: int = _cliff_source_for(
			terrain_id, bool(liquid_by_id.get(east_id, false)))
		if refined_silhouettes_enabled:
			_append_refined_side_return(
				buffer, local_x, local_y, world_pos, owner_height,
				east_height, south_height, east_source, world_seed, false,
				right_connected, profile_metrics)
		else:
			_append_side_return(
				buffer, local_x, local_y, world_pos, owner_height,
				east_height, east_source, world_seed, false, profile_metrics)
		component_count += 1
	return Vector2i(component_count, buffer.indices.size() / 3 - triangles_before)


static func _append_north_lip(
		buffer: Dictionary, local_x: int, local_y: int, world_pos: Vector2i,
		owner_height: int, source_id: int, world_seed: int,
		profile_metrics: Dictionary) -> void:
	var local_left: int = local_x * TILE_SIZE
	var local_top: int = local_y * TILE_SIZE - owner_height * HEIGHT_STEP
	var world_left: int = world_pos.x * TILE_SIZE
	for column in range(COLUMN_COUNT):
		var world_x0: int = world_left + column * PROFILE_STEP
		var world_x1: int = world_x0 + PROFILE_STEP
		var y0: int = local_top + mini(0, outline_offset(
			world_x0, world_pos.y, owner_height, world_seed, 41))
		var y1: int = local_top + mini(0, outline_offset(
			world_x1, world_pos.y, owner_height, world_seed, 41))
		var depth0: int = 3 + posmod(_hash_int(
			world_x0 / PROFILE_STEP, world_pos.y, owner_height, world_seed, 42), 3)
		var depth1: int = 3 + posmod(_hash_int(
			world_x1 / PROFILE_STEP, world_pos.y, owner_height, world_seed, 42), 3)
		var x0: int = local_left + column * PROFILE_STEP
		var x1: int = x0 + PROFILE_STEP
		_append_quad(
			buffer, Vector2(x0, y0), Vector2(x1, y1),
			Vector2(x1, y1 + depth1), Vector2(x0, y0 + depth0),
			1.06, source_id,
			posmod(_hash_int(world_pos.x, world_pos.y, column,
				world_seed, 43), 2), 1, 1.0, profile_metrics)


static func _append_side_return(
		buffer: Dictionary, local_x: int, local_y: int, world_pos: Vector2i,
		owner_height: int, neighbor_height: int, source_id: int,
		world_seed: int, west_side: bool,
		profile_metrics: Dictionary) -> void:
	var boundary_x: int = local_x * TILE_SIZE + (0 if west_side else TILE_SIZE)
	var world_boundary_x: int = world_pos.x * TILE_SIZE + (0 if west_side else TILE_SIZE)
	var local_top: int = local_y * TILE_SIZE - owner_height * HEIGHT_STEP
	var drop: int = clampi(owner_height - neighbor_height, 1, 3)
	var segment_count: int = TILE_SIZE / RETURN_PROFILE_STEP
	for segment in range(segment_count):
		var local_y0: int = local_top + segment * RETURN_PROFILE_STEP
		var local_y1: int = local_y0 + RETURN_PROFILE_STEP
		var world_y0: int = world_pos.y * TILE_SIZE + segment * RETURN_PROFILE_STEP
		var world_y1: int = world_y0 + RETURN_PROFILE_STEP
		var outer0: int = boundary_x + clampi(outline_offset(
			world_boundary_x, world_y0, owner_height, world_seed, 51), -1, 1)
		var outer1: int = boundary_x + clampi(outline_offset(
			world_boundary_x, world_y1, owner_height, world_seed, 51), -1, 1)
		var width0: int = 2 + ceili(float(drop) * 0.5) + posmod(_hash_int(
			world_boundary_x, world_y0, owner_height, world_seed, 52), 2)
		var width1: int = 2 + ceili(float(drop) * 0.5) + posmod(_hash_int(
			world_boundary_x, world_y1, owner_height, world_seed, 52), 2)
		var inner0: int = outer0 + (width0 if west_side else -width0)
		var inner1: int = outer1 + (width1 if west_side else -width1)
		var shade: float = 0.92 if west_side else 1.0
		_append_quad(
			buffer, Vector2(outer0, local_y0), Vector2(inner0, local_y0),
			Vector2(inner1, local_y1), Vector2(outer1, local_y1),
			shade, source_id,
			posmod(_hash_int(world_pos.x, world_pos.y, segment,
				world_seed, 53), 2), 2, 1.0, profile_metrics)


static func _append_refined_side_return(
		buffer: Dictionary, local_x: int, local_y: int, world_pos: Vector2i,
		owner_height: int, neighbor_height: int, south_height: int,
		source_id: int, world_seed: int, west_side: bool,
		neighbor_face_connected: bool, profile_metrics: Dictionary) -> void:
	## Phase 1E uses a coherent world-space ribbon rather than independent
	## eight-pixel rectangles. Its last sample is snapped to the owning south
	## face cap and grows a tapered shoulder into that wall when one exists.
	var boundary_x: int = local_x * TILE_SIZE + (0 if west_side else TILE_SIZE)
	var world_boundary_x: int = world_pos.x * TILE_SIZE + (0 if west_side else TILE_SIZE)
	var local_top: int = local_y * TILE_SIZE - owner_height * HEIGHT_STEP
	var world_top: int = world_pos.y * TILE_SIZE
	var drop: int = clampi(owner_height - neighbor_height, 1, 3)
	var has_south_wall: bool = owner_height > south_height
	var outer_points := PackedVector2Array()
	var inner_points := PackedVector2Array()
	for sample in range(TILE_SIZE / REFINED_RETURN_STEP + 1):
		var along: int = sample * REFINED_RETURN_STEP
		var world_y: int = world_top + along
		var y: int = local_top + along
		var outer_x: int = boundary_x + _return_outer_offset(
			world_boundary_x, world_y, owner_height, world_seed)
		var width: int = _return_width(
			world_boundary_x, world_y, owner_height, drop, world_seed)
		if has_south_wall and sample == TILE_SIZE / REFINED_RETURN_STEP:
			var face_height: int = (owner_height - south_height) * HEIGHT_STEP
			outer_x = _face_top_cap_x(
				boundary_x, world_pos, face_height, world_seed,
				west_side, neighbor_face_connected)
			y += _face_level_offset(
				world_boundary_x, world_pos.y, owner_height, world_seed)
			# Preserve a readable joint without turning every corner into a
			# rectangular buttress.
			width = maxi(width, 3 + drop / 2)
		var inner_x: int = outer_x + (width if west_side else -width)
		outer_points.append(Vector2(outer_x, y))
		inner_points.append(Vector2(inner_x, y))
	var shade: float = 0.94 if west_side else 1.01
	_append_strip(
		buffer, outer_points, inner_points, shade, source_id, 2, 1.0,
		_hash_int(world_pos.x, world_pos.y, owner_height, world_seed, 73),
		profile_metrics)


static func _append_strip(
		buffer: Dictionary, outer_points: PackedVector2Array,
		inner_points: PackedVector2Array, shade: float, source_id: int,
		component_role: int, alpha: float, diagonal_seed: int,
		profile_metrics: Dictionary) -> void:
	var profile_assembly: bool = not profile_metrics.is_empty()
	var assembly_started_usec: int = Time.get_ticks_usec() if profile_assembly else 0
	assert(outer_points.size() == inner_points.size())
	var base: int = buffer.vertices.size()
	var encoded_source: float = float(source_id) / 3.0
	var encoded_role: float = float(component_role) / 3.0
	for index in range(outer_points.size()):
		buffer.vertices.append(outer_points[index].round())
		buffer.vertices.append(inner_points[index].round())
		var point_shade: float = clampf(
			shade - float(index) * 0.018, 0.78, 1.12)
		var color := Color(point_shade, encoded_source, encoded_role, alpha)
		buffer.colors.append(color)
		buffer.colors.append(color)
	for segment in range(outer_points.size() - 1):
		var top_outer: int = base + segment * 2
		var top_inner: int = top_outer + 1
		var bottom_outer: int = top_outer + 2
		var bottom_inner: int = top_outer + 3
		if ((diagonal_seed + segment) & 1) == 0:
			buffer.indices.append_array(PackedInt32Array([
				top_outer, top_inner, bottom_inner,
				top_outer, bottom_inner, bottom_outer]))
		else:
			buffer.indices.append_array(PackedInt32Array([
				top_outer, top_inner, bottom_outer,
				top_inner, bottom_inner, bottom_outer]))
	if profile_assembly:
		profile_metrics.vertex_assembly_usec += Time.get_ticks_usec() - assembly_started_usec


static func _return_outer_offset(
		world_boundary_x: int, world_pixel_y: int, owner_height: int,
		world_seed: int) -> int:
	var sample_y: int = floori(float(world_pixel_y) / REFINED_RETURN_STEP)
	var formation_y: int = floori(float(sample_y) / 4.0)
	var fraction: float = float(posmod(sample_y, 4)) / 4.0
	var first: int = posmod(_hash_int(
		world_boundary_x / TILE_SIZE, formation_y, owner_height,
		world_seed, 75), 5) - 2
	var second: int = posmod(_hash_int(
		world_boundary_x / TILE_SIZE, formation_y + 1, owner_height,
		world_seed, 75), 5) - 2
	return clampi(roundi(lerpf(first, second, fraction)), -2, 2)


static func _return_width(
		world_boundary_x: int, world_pixel_y: int, owner_height: int,
		drop: int, world_seed: int) -> int:
	var formation_y: int = floori(float(world_pixel_y) / 64.0)
	var within_formation: int = posmod(world_pixel_y, 64)
	var center: int = 20 + posmod(_hash_int(
		world_boundary_x / TILE_SIZE, formation_y, owner_height,
		world_seed, 77), 25)
	var radius: int = 13 + posmod(_hash_int(
		world_boundary_x, formation_y, owner_height, world_seed, 78), 6)
	var strength: int = 2 + posmod(_hash_int(
		world_boundary_x, formation_y, owner_height, world_seed, 79), 3)
	var distance: int = absi(within_formation - center)
	var formation_mass: int = 0
	if distance < radius:
		formation_mass = ceili(float(radius - distance) / radius * strength)
	var base_width: int = 2 + (1 if drop > 1 else 0)
	return clampi(base_width + formation_mass, 2, 7)


static func _face_top_cap_x(
		boundary_x: int, world_pos: Vector2i, _face_height: int,
		world_seed: int, west_side: bool,
		neighbor_face_connected: bool) -> int:
	if neighbor_face_connected:
		return boundary_x
	return boundary_x + roundi(_face_cap_offset(
		world_pos, 0.0, world_seed, west_side))


static func _append_contact_shadow(
		buffer: Dictionary, local_x: int, local_y: int, world_pos: Vector2i,
		owner_height: int, south_height: int, source_id: int, world_seed: int,
		left_connected: bool, right_connected: bool,
		profile_metrics: Dictionary) -> int:
	var local_left: int = local_x * TILE_SIZE
	var local_bottom_base: int = local_y * TILE_SIZE + TILE_SIZE - south_height * HEIGHT_STEP
	var world_left: int = world_pos.x * TILE_SIZE
	var triangles_before: int = buffer.indices.size() / 3
	for column in range(COLUMN_COUNT):
		var world_x0: int = world_left + column * PROFILE_STEP
		var world_x1: int = world_x0 + PROFILE_STEP
		var x0: int = local_left + column * PROFILE_STEP
		var x1: int = x0 + PROFILE_STEP
		if column == 0 and not left_connected:
			x0 += roundi(_face_cap_offset(world_pos, 1.0, world_seed, true))
		if column == COLUMN_COUNT - 1 and not right_connected:
			x1 += roundi(_face_cap_offset(world_pos, 1.0, world_seed, false))
		var y0: int = local_bottom_base + _face_level_offset(
			world_x0, world_pos.y, south_height, world_seed)
		var y1: int = local_bottom_base + _face_level_offset(
			world_x1, world_pos.y, south_height, world_seed)
		var depth0: int = 3 + posmod(_hash_int(
			world_x0 / PROFILE_STEP, world_pos.y + 1, south_height,
			world_seed, 61), 3)
		var depth1: int = 3 + posmod(_hash_int(
			world_x1 / PROFILE_STEP, world_pos.y + 1, south_height,
			world_seed, 61), 3)
		_append_quad(
			buffer, Vector2(x0, y0), Vector2(x1, y1),
			Vector2(x1, y1 + depth1), Vector2(x0, y0 + depth0),
			0.82, source_id, 0, 3, 0.34, profile_metrics)
	return buffer.indices.size() / 3 - triangles_before


static func _has_face_values(
		neighbor_id: int, neighbor_maximum: int, neighbor_minimum: int,
		minimum_level: int, maximum_level: int,
		liquid_by_id: Dictionary) -> bool:
	if bool(liquid_by_id.get(neighbor_id, false)):
		return false
	return maxi(minimum_level, neighbor_minimum) < mini(maximum_level, neighbor_maximum)


static func _face_band_connected(
		neighbor_connected: bool, neighbor_minimum: int, neighbor_maximum: int,
		band_minimum: int, band_maximum: int) -> bool:
	return (neighbor_connected
		and maxi(band_minimum, neighbor_minimum)
		< mini(band_maximum, neighbor_maximum))


static func _cliff_source_for(terrain_id: int, shoreline: bool) -> int:
	# Kept identical to the legacy cliff source mapping. The mesh builder no
	# longer depends on TerrainChunkBuildJob, so that job can own this builder's
	# resumable state without a cyclic script dependency.
	var stone_style: bool = terrain_id in [4, 5, 7]
	return (2 if shoreline else 0) + (1 if stone_style else 0)


static func _cap_offset(
		world_pos: Vector2i, fraction: float, world_seed: int, channel: int) -> int:
	var row: int = roundi(fraction * 8.0)
	return posmod(_hash_int(
		world_pos.x, world_pos.y, row, world_seed, channel), 5) - 2


static func _face_cap_offset(
		world_pos: Vector2i, fraction: float, world_seed: int,
		west_side: bool) -> float:
	## Both vertices on a row boundary must evaluate the same absolute cap
	## position. Mixing the next row's taper into both endpoints opens wedges
	## between independently emitted row quads.
	var primary_channel: int = 2 if west_side else 3
	var taper_channel: int = 4 if west_side else 5
	return (_cap_offset(world_pos, fraction, world_seed, primary_channel)
		+ _cap_offset(world_pos, fraction, world_seed, taper_channel) * fraction)


static func _face_level_offset(
		world_pixel_x: int, world_cell_y: int, level: int, world_seed: int) -> int:
	## A level boundary is independent of the total drop on either adjacent
	## face. Clamping inward preserves coverage beneath authoritative top tiles.
	return mini(0, outline_offset(
		world_pixel_x, world_cell_y, level, world_seed, 83))


static func _facet_shade(
		world_pos: Vector2i, column: int, row: int,
		source_id: int, world_seed: int) -> float:
	var value: int = posmod(_hash_int(
		world_pos.x * 4 + column, world_pos.y * 8 + row,
		source_id, world_seed, 29), 5)
	return [0.84, 0.91, 0.98, 1.04, 1.10][value]


static func _new_buffer() -> Dictionary:
	return {
		"vertices": PackedVector2Array(),
		"colors": PackedColorArray(),
		"indices": PackedInt32Array(),
	}


static func _hash_int(a: int, b: int, c: int, seed: int, channel: int) -> int:
	var value: int = a * 73856093 ^ b * 19349663 ^ c * 83492791
	value ^= seed * 2654435761
	value ^= channel * 374761393
	value = (value ^ (value >> 13)) * 1274126177
	return value ^ (value >> 16)

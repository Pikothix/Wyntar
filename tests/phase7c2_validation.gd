extends SceneTree
## Phase 7C.2 validation for deterministic 3x3 edge classification, simplified
## small shapes, connected wall corners, diagnostics, and signed chunk seams.

const Catalog = preload("res://scripts/terrain_catalog.gd")
const TerrainChunkBuildJob = preload("res://scripts/terrain_chunk_build_job.gd")
const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")

var failures: Array[String] = []
var priorities: Dictionary = {}
var liquids: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for material in Catalog.MATERIALS:
		priorities[int(material["id"])] = int(material["priority"])
		liquids[int(material["id"])] = bool(material.get("liquid", false))
	_test_classifier_shapes()
	_test_signed_chunk_boundary()
	await _test_read_only_diagnostic()
	if failures.is_empty():
		print("PHASE7C2_VALIDATION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE7C2_VALIDATION: FAIL (%d)" % failures.size())
	quit(1)


func _test_classifier_shapes() -> void:
	var broad: Dictionary = _classify(
		2, 3, 1, 2, 2, 2, 2, 2, 2, 2, 0, 3, 3, 3)
	_expect(int(broad["edge_mask"]) == 1, "broad plateau exposes only its north lip")
	_expect(int(broad["style"]) == TerrainChunkBuildJob.EDGE_STYLE_STANDARD,
		"broad plateau retains the standard ledge treatment")

	var island: Dictionary = _classify(
		2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
	_expect(int(island["edge_mask"]) == 15, "single-cell island exposes all directions")
	_expect(int(island["style"]) == TerrainChunkBuildJob.EDGE_STYLE_SIMPLIFIED,
		"single-cell island receives a simplified rim")
	_expect((int(island["flags"]) & TerrainChunkBuildJob.EDGE_FLAG_SUPPRESSED_SECONDARY) != 0,
		"single-cell island suppresses detached secondary returns")
	_expect(bool(island["water_contact"]), "island uses liquid metadata for water contact")
	_expect(int(island["max_drop"]) == 2, "island retains its true two-level drop")

	var peninsula: Dictionary = _classify(
		2, 3, 0, 2, 0, 2, 1, 1, 1, 1, 0, 3, 0, 3)
	_expect(int(peninsula["style"]) == TerrainChunkBuildJob.EDGE_STYLE_SIMPLIFIED,
		"narrow peninsula avoids accumulating independent edge strips")

	var corner: Dictionary = _classify(
		2, 4, 2, 1, 1, 2, 2, 2, 2, 2, 4, 0, 0, 4)
	_expect(int(corner["style"]) == TerrainChunkBuildJob.EDGE_STYLE_WALL_CONNECTED,
		"east return connects to the southern wall")
	_expect((int(corner["flags"]) & TerrainChunkBuildJob.EDGE_FLAG_CONNECTED_CORNER) != 0,
		"connected corner is exposed diagnostically")

	var water_side: Dictionary = _classify(
		1, 3, 1, 0, 1, 1, 1, 1, 1, 1, 3, 0, 3, 3)
	_expect((int(water_side["flags"]) & TerrainChunkBuildJob.EDGE_FLAG_SUPPRESSED_SECONDARY) != 0,
		"water-only side exposure suppresses a detached grey strip")


func _test_signed_chunk_boundary() -> void:
	var west_job = _prepare_job(Vector2i(-1, 0))
	var east_job = _prepare_job(Vector2i(0, 0))
	var west_index: int = 10 * TerrainChunkBuildJob.CHUNK_SIZE + 31
	var east_index: int = 10 * TerrainChunkBuildJob.CHUNK_SIZE
	_expect((int(west_job.cliff_edge_masks[west_index]) & 4) == 0,
		"negative-coordinate plateau has no false east seam return")
	_expect((int(east_job.cliff_edge_masks[east_index]) & 2) == 0,
		"positive-coordinate plateau has no false west seam return")
	var island_index: int = 5 * TerrainChunkBuildJob.CHUNK_SIZE + 5
	_expect(int(east_job.cliff_edge_styles[island_index]) == TerrainChunkBuildJob.EDGE_STYLE_SIMPLIFIED,
		"prepared jobs persist the single-cell island style")


func _test_read_only_diagnostic() -> void:
	var renderer = TerrainRenderer.new()
	root.add_child(renderer)
	await process_frame
	var cell := Vector2i(-65, -33)
	renderer.world.set_override(cell, 1)
	renderer.world.set_elevation_override(cell, 2)
	for offset in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		renderer.world.set_override(cell + offset, 0)
		renderer.world.set_elevation_override(cell + offset, 0)
	var before: Dictionary = renderer.world.export_override_snapshot()
	var diagnostic: Dictionary = renderer.get_cliff_edge_diagnostic(cell)
	var labels: PackedStringArray = diagnostic["labels"]
	_expect(labels.has("southern_wall") and labels.has("northern_lip"),
		"diagnostic reports primary wall and tertiary lip")
	_expect(labels.has("suppressed_secondary_cue") and labels.has("water_contact_edge"),
		"diagnostic reports simplified liquid-contact treatment")
	_expect(renderer.world.export_override_snapshot() == before,
		"diagnostic lookup does not mutate authoritative state")
	renderer.queue_free()


func _prepare_job(coord: Vector2i):
	var job = TerrainChunkBuildJob.new(coord)
	while not job.is_data_ready():
		job.process_data_quantum(
			_fixture_material, _fixture_height, _fixture_height,
			priorities, liquids, {"generation_enabled": false},
			{"generation_enabled": false}, 4096)
	return job


func _classify(
		center_height: int, center_id: int,
		north_height: int, east_height: int, south_height: int, west_height: int,
		north_east_height: int, south_east_height: int,
		south_west_height: int, north_west_height: int,
		north_id: int, east_id: int, south_id: int, west_id: int) -> Dictionary:
	return TerrainChunkBuildJob.classify_cliff_edge_samples(
		center_height, center_id,
		north_height, east_height, south_height, west_height,
		north_east_height, south_east_height, south_west_height, north_west_height,
		north_id, east_id, south_id, west_id, liquids)


func _fixture_material(pos: Vector2i) -> int:
	if pos == Vector2i(5, 5):
		return 1
	if pos.y == 10 and pos.x >= -2 and pos.x <= 1:
		return 3
	return 0


func _fixture_height(pos: Vector2i) -> int:
	if pos == Vector2i(5, 5):
		return 2
	if pos.y == 10 and pos.x >= -2 and pos.x <= 1:
		return 2
	return 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

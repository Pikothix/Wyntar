extends SceneTree
## Phase 7C.4 validation for unified cliff profiles, stacked-face continuity,
## deterministic chunk preparation, and atlas contact geometry.

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
		priorities[int(material.id)] = int(material.priority)
		liquids[int(material.id)] = bool(material.get("liquid", false))
	_test_profile_function()
	_test_stacked_face_encoding()
	_test_signed_chunk_determinism()
	await _test_atlas_geometry()
	if failures.is_empty():
		print("PHASE7C4_VALIDATION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE7C4_VALIDATION: FAIL (%d)" % failures.size())
	quit(1)


func _test_profile_function() -> void:
	for style in range(4):
		_expect(TerrainRenderer._cliff_boundary_offset(style, 0) == 0,
			"left profile endpoint is seam-safe for style %d" % style)
		_expect(TerrainRenderer._cliff_boundary_offset(style, 31) == 0,
			"right profile endpoint is seam-safe for style %d" % style)
		for x in range(32):
			var offset: int = TerrainRenderer._cliff_boundary_offset(style, x)
			_expect(offset >= 0 and offset <= 2,
				"profile remains pixel-quantised for style %d x %d" % [style, x])


func _test_stacked_face_encoding() -> void:
	var job = _prepare_job(Vector2i.ZERO)
	var index: int = 10 * TerrainChunkBuildJob.CHUNK_SIZE + 10
	var level_one_variant: int = int(job.cliff_variants[TerrainChunkBuildJob.CELL_COUNT + index])
	var level_two_variant: int = int(job.cliff_variants[2 * TerrainChunkBuildJob.CELL_COUNT + index])
	_expect(int(job.cliff_sources[TerrainChunkBuildJob.CELL_COUNT + index]) >= 0,
		"height 3 to 1 drop prepares its lower wall step")
	_expect(int(job.cliff_sources[2 * TerrainChunkBuildJob.CELL_COUNT + index]) >= 0,
		"height 3 to 1 drop prepares its upper wall step")
	_expect((level_one_variant & 4) == 0,
		"internal stacked wall step omits a false top silhouette")
	_expect((level_two_variant & 4) != 0,
		"uppermost stacked wall step owns the top silhouette")
	_expect((level_one_variant >> 3) == (level_two_variant >> 3),
		"all levels of one face reuse the same deterministic profile")


func _test_signed_chunk_determinism() -> void:
	var west = _prepare_job(Vector2i(-1, 0))
	var east = _prepare_job(Vector2i.ZERO)
	var west_index: int = 10 * TerrainChunkBuildJob.CHUNK_SIZE + 31
	var east_index: int = 10 * TerrainChunkBuildJob.CHUNK_SIZE
	var west_variant: int = int(west.cliff_variants[2 * TerrainChunkBuildJob.CELL_COUNT + west_index])
	var east_variant: int = int(east.cliff_variants[2 * TerrainChunkBuildJob.CELL_COUNT + east_index])
	_expect((west_variant & 2) == 0, "west chunk face connects through its east cap")
	_expect((east_variant & 1) == 0, "east chunk face connects through its west cap")


func _test_atlas_geometry() -> void:
	var renderer = TerrainRenderer.new()
	root.add_child(renderer)
	await process_frame
	var source: TileSetAtlasSource = renderer.cliff_tileset.get_source(0)
	var image: Image = source.texture.get_image()
	var sample_x: int = 8 # style 0 profile offset is two pixels here.
	_expect(image.get_pixel(4 * 32 + sample_x, 0).a == 0.0,
		"topmost face uses the shared organic upper profile")
	_expect(image.get_pixel(sample_x, 0).a > 0.9,
		"internal face step stays solid and cannot compress the wall")
	_expect(image.get_pixel(sample_x, 16).a == 0.0,
		"contact shadow begins at the shared lower profile")
	_expect(image.get_pixel(sample_x, 18).a > 0.0,
		"contact shadow remains attached after its profile offset")
	renderer.queue_free()


func _prepare_job(coord: Vector2i):
	var job = TerrainChunkBuildJob.new(coord)
	while not job.is_data_ready():
		job.process_data_quantum(
			_fixture_material, _fixture_height, _fixture_height,
			priorities, liquids, {"generation_enabled": false},
			{"generation_enabled": false}, 4096)
	return job


func _fixture_material(_pos: Vector2i) -> int:
	return 1


func _fixture_height(pos: Vector2i) -> int:
	if pos.y == 10 and pos.x >= -2 and pos.x <= 1:
		return 3
	if pos.y == 11 and pos.x >= -2 and pos.x <= 1:
		return 1
	if pos == Vector2i(10, 10):
		return 3
	if pos == Vector2i(10, 11):
		return 1
	return 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

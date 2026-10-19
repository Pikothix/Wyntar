extends SceneTree
## Phase 7C.5 validation for height-aware textured side returns, diagonal
## corner continuity, and strict separation from the cast-shadow atlas row.

const Catalog = preload("res://scripts/terrain_catalog.gd")
const TerrainChunkBuildJob = preload("res://scripts/terrain_chunk_build_job.gd")
const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")

var failures: Array[String] = []
var liquids: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for material in Catalog.MATERIALS:
		liquids[int(material.id)] = bool(material.get("liquid", false))
	_test_variant_encoding()
	_test_geometry_classification()
	await _test_atlas_separation()
	if failures.is_empty():
		print("PHASE7C5_VALIDATION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE7C5_VALIDATION: FAIL (%d)" % failures.size())
	quit(1)


func _test_variant_encoding() -> void:
	for style in range(3):
		for drop in range(1, 4):
			_expect(
				TerrainChunkBuildJob.cliff_edge_variant(style, drop) == style * 3 + drop - 1,
				"edge atlas row preserves style %d and drop %d" % [style, drop])
	_expect(TerrainChunkBuildJob.cliff_edge_variant(0, 9) == 2,
		"drops above the supported visual range reuse the bounded height-3 variant")


func _test_geometry_classification() -> void:
	var isolated: Vector4i = TerrainChunkBuildJob.classify_cliff_edge_values(
		3, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, liquids)
	_expect(isolated.x == 15, "isolated raised cells expose all physical boundaries")
	_expect(isolated.y == TerrainChunkBuildJob.EDGE_STYLE_SIMPLIFIED,
		"isolated cells retain the restrained return style")
	_expect(isolated.w == 3, "isolated height-3 cells retain their visible drop")
	var corner: Vector4i = TerrainChunkBuildJob.classify_cliff_edge_values(
		2, 1, 2, 0, 0, 2, 2, 0, 2, 2, 1, 1, 1, 1, liquids)
	_expect((corner.z & TerrainChunkBuildJob.EDGE_FLAG_CONNECTED_CORNER) != 0,
		"diagonal steps classify as connected wall corners")
	_expect(corner.y == TerrainChunkBuildJob.EDGE_STYLE_WALL_CONNECTED,
		"connected corners select the continuous textured treatment")


func _test_atlas_separation() -> void:
	var renderer = TerrainRenderer.new()
	root.add_child(renderer)
	await process_frame
	var edge_source: TileSetAtlasSource = renderer.cliff_edge_tileset.get_source(0)
	var edge_image: Image = edge_source.texture.get_image()
	var isolated_variant: int = TerrainChunkBuildJob.cliff_edge_variant(
		TerrainChunkBuildJob.EDGE_STYLE_SIMPLIFIED, 3)
	var edge_origin := Vector2i(15 * 32, isolated_variant * 32)
	var outer: Color = edge_image.get_pixel(edge_origin.x, edge_origin.y + 31)
	var inner: Color = edge_image.get_pixel(edge_origin.x + 2, edge_origin.y + 31)
	_expect(outer.a > 0.8 and inner.a > 0.7,
		"isolated side returns are opaque textured geometry, not low-alpha grey cues")
	_expect(absf(outer.r - outer.g) > 0.01 or absf(outer.g - outer.b) > 0.01,
		"side-return pigment retains the cliff artwork palette")
	var connected_variant: int = TerrainChunkBuildJob.cliff_edge_variant(
		TerrainChunkBuildJob.EDGE_STYLE_WALL_CONNECTED, 2)
	var connected_origin := Vector2i(14 * 32, connected_variant * 32)
	_expect(edge_image.get_pixel(connected_origin.x, connected_origin.y + 31).a > 0.8,
		"diagonal corner return reaches the southern wall join")
	var cliff_source: TileSetAtlasSource = renderer.cliff_tileset.get_source(0)
	var cliff_image: Image = cliff_source.texture.get_image()
	_expect(cliff_image.get_pixel(8, 16).a == 0.0,
		"cast shadow respects the shared organic contact offset")
	_expect(cliff_image.get_pixel(8, 18).a > 0.0,
		"cast shadow remains attached below physical southern geometry")
	_expect(cliff_image.get_pixel(8, 21).a == 0.0,
		"cast shadow remains a bounded five-pixel band")
	renderer.queue_free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

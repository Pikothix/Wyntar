extends SceneTree
## Phase 7C validation for liquid metadata, height-strict surface composition,
## deterministic chunk preparation, and cliff-lip atlas readability.

const Catalog = preload("res://scripts/terrain_catalog.gd")
const TerrainGenerator = preload("res://scripts/terrain_generator.gd")
const TerrainWorld = preload("res://scripts/terrain_world.gd")
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
	_test_liquid_profile()
	_test_height_strict_compositing()
	_test_authoritative_ground_preservation()
	await _test_render_resources()
	if failures.is_empty():
		print("PHASE7C_VALIDATION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE7C_VALIDATION: FAIL (%d)" % failures.size())
	quit(1)


func _test_liquid_profile() -> void:
	var water: Dictionary = Catalog.MATERIALS[0]
	for key in [
			"surface_style", "shoreline_style", "visual_calmness",
			"liquid_pattern_frequency", "liquid_motion_enabled",
			"emissive", "depth_effect_strength"]:
		_expect(water.has(key), "water liquid profile defines %s" % key)
	_expect(Catalog.is_liquid(0), "water remains liquid by catalog metadata")
	_expect(not Catalog.is_liquid(1), "ordinary ground remains non-liquid")
	_expect(float(water["visual_calmness"]) > 0.75,
		"water selects a calm large-scale surface profile")


func _test_height_strict_compositing() -> void:
	var job = TerrainChunkBuildJob.new(Vector2i.ZERO)
	while not job.is_data_ready():
		job.process_data_quantum(
			_fixture_material, _fixture_surface_height, _fixture_ground_height,
			priorities, liquids, {"generation_enabled": false},
			{"generation_enabled": false}, 4096)
	var cell_index: int = 10 * TerrainChunkBuildJob.CHUNK_SIZE + 10
	_expect(int(job.slot_sources[cell_index]) == 0,
		"sea-level stack starts with water")
	_expect(int(job.slot_masks[cell_index]) == 12,
		"sea-level base is masked to the two sea-level corners")
	var sand_slot: int = TerrainChunkBuildJob.CELL_COUNT + cell_index
	_expect(int(job.slot_sources[sand_slot]) == 1,
		"sea-level sand remains available above water by priority")
	_expect(int(job.slot_masks[sand_slot]) == 4,
		"sand cannot cover the raised or water corners")
	for depth in range(TerrainChunkBuildJob.SLOT_COUNT):
		var source: int = int(job.slot_sources[depth * TerrainChunkBuildJob.CELL_COUNT + cell_index])
		_expect(source != 3, "raised grass never enters the sea-level material stack")
	var raised_index: int = TerrainChunkBuildJob.SLOT_COUNT * TerrainChunkBuildJob.CELL_COUNT + cell_index
	_expect(int(job.elevated_slot_sources[raised_index]) == 3,
		"raised grass remains in its authoritative elevation band")
	_expect(int(job.elevated_slot_masks[raised_index]) == 3,
		"raised surface mask covers only raised corners")
	_expect(job.liquid_surface_usec >= 0,
		"liquid preparation timing remains available")


func _test_authoritative_ground_preservation() -> void:
	var generator := TerrainGenerator.new()
	generator.configure(84521, 0.012, 0.055, true)
	generator.configure_elevation(true, 3, 0.006, 0.021, 0.14, -0.12, 0.16, 0.43, 0.02)
	var world := TerrainWorld.new()
	world.configure(generator)
	var cell := Vector2i(14, -9)
	var raised_height: int = 1 if generator.get_elevation(cell) != 1 else 2
	world.set_elevation_override(cell, raised_height)
	world.set_override(cell, 0)
	_expect(world.get_elevation(cell) == raised_height,
		"liquid rendering does not mutate authoritative ground elevation")
	_expect(world.get_surface_elevation(cell, 0) == raised_height,
		"ground above sea level is exposed instead of lifting liquid")
	_expect(world.get_visible_liquid_elevation(cell, 0) == -1,
		"raised seabed has no visible liquid surface")
	_expect(world.get_visible_material(cell, 0) == 1,
		"raised water cell derives its declared exposed substrate")


func _test_render_resources() -> void:
	var renderer = TerrainRenderer.new()
	root.add_child(renderer)
	await process_frame
	var water_material: ShaderMaterial = renderer.visual_material_by_id[0]
	var sand_material: ShaderMaterial = renderer.visual_material_by_id[1]
	_expect(float(water_material.get_shader_parameter("liquid_enabled")) == 1.0,
		"water uses the liquid shader branch")
	_expect(float(sand_material.get_shader_parameter("liquid_enabled")) == 0.0,
		"sand stays on the ordinary terrain shader branch")
	var edge_source: TileSetAtlasSource = renderer.cliff_edge_tileset.get_source(0)
	var edge_image: Image = edge_source.texture.get_image()
	var first_lip_alpha: float = edge_image.get_pixel(32, 0).a
	var inner_lip_alpha: float = edge_image.get_pixel(32, 2).a
	_expect(first_lip_alpha >= 0.55 and inner_lip_alpha >= 0.20,
		"north cliff lip uses readable stepped opacity")
	renderer.queue_free()


func _fixture_material(pos: Vector2i) -> int:
	if pos == Vector2i(9, 9):
		return 0
	if pos == Vector2i(10, 9):
		return 1
	if pos in [Vector2i(9, 10), Vector2i(10, 10)]:
		return 3
	return 3


func _fixture_surface_height(pos: Vector2i) -> int:
	return 2 if pos in [Vector2i(9, 10), Vector2i(10, 10)] else 0


func _fixture_ground_height(pos: Vector2i) -> int:
	return 3 if pos == Vector2i(9, 9) else _fixture_surface_height(pos)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

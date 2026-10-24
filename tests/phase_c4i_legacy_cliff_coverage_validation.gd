extends SceneTree
## C4I validates that coverage is deterministic, LEGACY-only, and separate
## from both terrain authority and the accepted organic face geometry.

const OrganicCliffMeshBuilder = preload("res://scripts/organic_cliff_mesh_builder.gd")
const MainScript = preload("res://scripts/main.gd")
const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")
const CliffRenderingSettings = preload(
	"res://scripts/settings/cliff_rendering_settings.gd")

var _heights: Dictionary = {}
var _materials: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_r3_configuration_path()
	_build_fixture()
	var baseline: Dictionary = _build(
		OrganicCliffMeshBuilder.ExperimentalCliffMode.LEGACY, false)
	var repaired: Dictionary = _build(
		OrganicCliffMeshBuilder.ExperimentalCliffMode.LEGACY, true)
	var repaired_repeat: Dictionary = _build(
		OrganicCliffMeshBuilder.ExperimentalCliffMode.LEGACY, true)
	assert(_mesh_signature(baseline.meshes) == _mesh_signature(repaired.meshes),
		"C4I must not change the accepted LEGACY face silhouette")
	assert(int(baseline.coverage_triangle_count) == 0)
	assert(int(repaired.coverage_triangle_count) > 0)
	assert(int(repaired.coverage_vertex_count) > 0)
	assert(_mesh_signature(repaired.coverage_meshes)
		== _mesh_signature(repaired_repeat.coverage_meshes),
		"C4I coverage must rebuild deterministically")
	for mode in [
		OrganicCliffMeshBuilder.ExperimentalCliffMode.GRID,
		OrganicCliffMeshBuilder.ExperimentalCliffMode.UNIFIED,
		OrganicCliffMeshBuilder.ExperimentalCliffMode.STYLISED]:
		var result: Dictionary = _build(mode, true)
		assert(int(result.coverage_triangle_count) == 0,
			"C4I coverage must remain disabled outside LEGACY")
		assert(_mesh_signature(result.coverage_meshes).is_empty())
	print("PHASE_C4I_LEGACY_CLIFF_COVERAGE_VALIDATION: PASS coverage_vertices=%d coverage_triangles=%d" % [
		repaired.coverage_vertex_count, repaired.coverage_triangle_count])
	quit(0)


func _test_r3_configuration_path() -> void:
	var main = MainScript.new()
	var renderer = TerrainRenderer.new()
	main.legacy_cliff_coverage_repair_enabled = true
	CliffRenderingSettings.capture(main).apply_to(renderer)
	assert(renderer.legacy_cliff_coverage_repair_enabled,
		"R3 cliff settings must apply the enabled C4I state pre-ready")
	main.legacy_cliff_coverage_repair_enabled = false
	CliffRenderingSettings.capture(main).apply_to(renderer)
	assert(not renderer.legacy_cliff_coverage_repair_enabled,
		"R3 cliff settings must preserve C4I rollback pre-ready")
	main.free()
	renderer.free()


func _build_fixture() -> void:
	for y in range(4, 13):
		for x in range(4, 13):
			if x <= 8 + floori(sin(float(y) * 0.7) * 2.0):
				_heights[Vector2i(x, y)] = 2
				_materials[Vector2i(x, y)] = 4
	for y in range(7, 10):
		for x in range(7, 10):
			_heights[Vector2i(x, y)] = 3
			_materials[Vector2i(x, y)] = 2


func _build(mode: int, coverage_enabled: bool) -> Dictionary:
	return OrganicCliffMeshBuilder.build(
		Vector2i.ZERO, 3, 84521,
		func(pos: Vector2i) -> int: return int(_materials.get(pos, 3)),
		func(pos: Vector2i) -> int: return int(_heights.get(pos, 0)),
		{6: true}, true, true, true, true, 32, true, false, mode,
		coverage_enabled)


func _mesh_signature(meshes: Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	for mesh in meshes:
		if mesh == null:
			continue
		for surface in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface)
			bytes.append_array(arrays[Mesh.ARRAY_VERTEX].to_byte_array())
			bytes.append_array(arrays[Mesh.ARRAY_COLOR].to_byte_array())
			bytes.append_array(arrays[Mesh.ARRAY_INDEX].to_byte_array())
	return bytes

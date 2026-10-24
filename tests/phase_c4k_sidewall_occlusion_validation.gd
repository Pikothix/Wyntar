extends SceneTree
## Structural C4K validation: separate deterministic LEGACY-only occlusion,
## unchanged accepted faces/C4J underlay, and typed configuration rollback.

const OrganicCliffMeshBuilder = preload("res://scripts/organic_cliff_mesh_builder.gd")
const MainScript = preload("res://scripts/main.gd")
const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")
const CliffRenderingSettings = preload(
	"res://scripts/settings/cliff_rendering_settings.gd")

var heights: Dictionary = {}
var materials: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_configuration()
	_build_fixture()
	var before: Dictionary = _build(
		OrganicCliffMeshBuilder.ExperimentalCliffMode.LEGACY, false)
	var after: Dictionary = _build(
		OrganicCliffMeshBuilder.ExperimentalCliffMode.LEGACY, true)
	var repeat: Dictionary = _build(
		OrganicCliffMeshBuilder.ExperimentalCliffMode.LEGACY, true)
	assert(_mesh_signature(before.meshes) == _mesh_signature(after.meshes),
		"C4K must not change the accepted LEGACY face geometry")
	assert(_mesh_signature(before.coverage_meshes) == _mesh_signature(after.coverage_meshes),
		"C4K must not change C4J coverage geometry")
	assert(int(before.sidewall_occlusion_triangle_count) == 0)
	assert(int(after.sidewall_occlusion_triangle_count) > 0)
	assert(int(after.sidewall_occlusion_vertex_count) > 0)
	assert(_mesh_signature(after.sidewall_occlusion_meshes)
		== _mesh_signature(repeat.sidewall_occlusion_meshes),
		"C4K sidewall occlusion must rebuild deterministically")
	for mode in [
		OrganicCliffMeshBuilder.ExperimentalCliffMode.GRID,
		OrganicCliffMeshBuilder.ExperimentalCliffMode.UNIFIED,
		OrganicCliffMeshBuilder.ExperimentalCliffMode.STYLISED]:
		var result: Dictionary = _build(mode, true)
		assert(int(result.sidewall_occlusion_triangle_count) == 0,
			"C4K must remain disabled outside LEGACY")
		assert(_mesh_signature(result.sidewall_occlusion_meshes).is_empty())
	print("PHASE_C4K_SIDEWALL_OCCLUSION_VALIDATION: PASS vertices=%d triangles=%d" % [
		after.sidewall_occlusion_vertex_count,
		after.sidewall_occlusion_triangle_count])
	quit(0)


func _validate_configuration() -> void:
	var main = MainScript.new()
	var renderer = TerrainRenderer.new()
	main.legacy_cliff_sidewall_occlusion_repair_enabled = true
	CliffRenderingSettings.capture(main).apply_to(renderer)
	assert(renderer.legacy_cliff_sidewall_occlusion_repair_enabled,
		"C4K enabled state must follow the typed pre-ready configuration path")
	main.legacy_cliff_sidewall_occlusion_repair_enabled = false
	CliffRenderingSettings.capture(main).apply_to(renderer)
	assert(not renderer.legacy_cliff_sidewall_occlusion_repair_enabled,
		"C4K rollback must follow the typed pre-ready configuration path")
	main.free()
	renderer.free()


func _build_fixture() -> void:
	for y in range(3, 15):
		for x in range(3, 16):
			if x <= 9 + floori(sin(float(y) * 0.73) * 3.0):
				heights[Vector2i(x, y)] = 2
				materials[Vector2i(x, y)] = 2
	for y in range(7, 11):
		for x in range(6, 10):
			heights[Vector2i(x, y)] = 3
			materials[Vector2i(x, y)] = 4


func _build(mode: int, sidewall_enabled: bool) -> Dictionary:
	return OrganicCliffMeshBuilder.build(
		Vector2i.ZERO, 3, 84521,
		func(pos: Vector2i) -> int: return int(materials.get(pos, 3)),
		func(pos: Vector2i) -> int: return int(heights.get(pos, 0)),
		{0: true}, true, true, true, true, 32, true, false, mode,
		true, sidewall_enabled)


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

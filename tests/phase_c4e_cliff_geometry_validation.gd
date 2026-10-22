extends SceneTree
## Focused C4E structural coverage checks. Terrain data remains authoritative;
## this validator examines only source-image support and generated mesh output.

const OrganicCliffMeshBuilder = preload("res://scripts/organic_cliff_mesh_builder.gd")
const SOURCE_TEXTURES := [
	"res://art/water.png",
	"res://art/sand.png",
	"res://art/dirt.png",
	"res://art/grass.png",
	"res://art/stone.png",
	"res://art/snow.png",
	"res://art/mud.png",
	"res://art/gravel.png",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_surface_asset_support()
	_test_isolated_cell_uses_one_geometry_path()
	_test_cardinal_and_diagonal_faces_are_non_degenerate()
	_test_chunk_seam_determinism()
	if failures.is_empty():
		print("PHASE_C4E_CLIFF_GEOMETRY_VALIDATION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PHASE_C4E_CLIFF_GEOMETRY_VALIDATION: FAIL (%d)" % failures.size())
	quit(1)


func _test_surface_asset_support() -> void:
	for path in SOURCE_TEXTURES:
		var texture: Texture2D = load(path) as Texture2D
		_expect(texture != null, "%s loads" % path)
		if texture == null:
			continue
		var image: Image = texture.get_image()
		_expect(image.get_size() == Vector2i(32, 32),
			"%s has full 32x32 tile support" % path)
		var transparent_pixels: int = 0
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				if image.get_pixel(x, y).a < 0.999:
					transparent_pixels += 1
		_expect(transparent_pixels == 0,
			"%s has no source-alpha holes" % path)


func _test_isolated_cell_uses_one_geometry_path() -> void:
	var heights := {Vector2i(16, 16): 2}
	var result: Dictionary = _build_fixture(heights)
	_expect(int(result.face_count) == 8,
		"isolated two-level cell emits four unified contour faces per level")
	_expect(_degenerate_triangle_count(result.meshes) == 0,
		"isolated unified contour contains no degenerate triangles")
	var bounds: Rect2 = _mesh_bounds(result.meshes)
	var projected_surface_bottom: float = 16.0 * 32.0 + 16.0 - 2.0 * 32.0
	_expect(bounds.position.y <= projected_surface_bottom,
		"isolated face crest underlaps the projected surface cap")


func _test_cardinal_and_diagonal_faces_are_non_degenerate() -> void:
	var cardinal_heights: Dictionary = {}
	for y in range(3, 29):
		for x in range(2, 17):
			cardinal_heights[Vector2i(x, y)] = 2
	var cardinal: Dictionary = _build_fixture(cardinal_heights)
	_expect(_degenerate_triangle_count(cardinal.meshes) == 0,
		"straight cardinal transitions contain no zero-area faces")
	var diagonal_heights: Dictionary = {}
	for y in range(3, 29):
		for x in range(2, 30):
			if x <= y:
				diagonal_heights[Vector2i(x, y)] = 2
	var diagonal: Dictionary = _build_fixture(diagonal_heights)
	_expect(_degenerate_triangle_count(diagonal.meshes) == 0,
		"diagonal transitions contain no zero-area faces")


func _test_chunk_seam_determinism() -> void:
	var heights: Dictionary = {}
	for y in range(-4, 37):
		for x in range(20, 45):
			if x <= 32 + floori(float(y) * 0.5):
				heights[Vector2i(x, y)] = 2
	var first: Dictionary = _build_fixture(heights, Vector2i.ZERO)
	var second: Dictionary = _build_fixture(heights, Vector2i.ZERO)
	_expect(_geometry_signature(first) == _geometry_signature(second),
		"C4E geometry remains byte-deterministic")
	var left: Vector2 = OrganicCliffMeshBuilder._unified_edge_point(
		1, 31, 12, Vector2i(31, 12), 84521)
	var right: Vector2 = OrganicCliffMeshBuilder._unified_edge_point(
		3, 0, 12, Vector2i(32, 12), 84521) + Vector2(32 * 32, 0)
	_expect(left == right, "C4E preserves canonical chunk-seam crest endpoints")


func _build_fixture(heights: Dictionary, chunk_coord := Vector2i.ZERO) -> Dictionary:
	var height_lookup := func(pos: Vector2i) -> int: return int(heights.get(pos, 0))
	var material_lookup := func(_pos: Vector2i) -> int: return 3
	return OrganicCliffMeshBuilder.build(
		chunk_coord, 3, 84521, material_lookup, height_lookup,
		{0: true}, true, true, true, true, 32, true)


func _degenerate_triangle_count(meshes: Array) -> int:
	var count: int = 0
	for mesh in meshes:
		if mesh == null:
			continue
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertices: PackedVector2Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for index in range(0, indices.size(), 3):
			var first: Vector2 = vertices[indices[index]]
			var second: Vector2 = vertices[indices[index + 1]]
			var third: Vector2 = vertices[indices[index + 2]]
			if absf((second - first).cross(third - first)) < 0.5:
				count += 1
	return count


func _mesh_bounds(meshes: Array) -> Rect2:
	var bounds := Rect2()
	var initialized := false
	for mesh in meshes:
		if mesh == null:
			continue
		for vertex in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			if not initialized:
				bounds = Rect2(vertex, Vector2.ZERO)
				initialized = true
			else:
				bounds = bounds.expand(vertex)
	return bounds


func _geometry_signature(result: Dictionary) -> Array:
	var signature: Array = [
		int(result.face_count), int(result.vertex_count), int(result.triangle_count)]
	for mesh in result.meshes:
		signature.append(null if mesh == null else hash(mesh.surface_get_arrays(0)))
	return signature


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

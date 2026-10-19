extends Node2D
## Read-only Phase 7C.4 geometry diagnostic. It visualises authoritative
## surface bands and logical southern faces without changing terrain state.

const TILE_SIZE := Vector2i(32, 32)
const HEIGHT_STEP: int = 16

var terrain
var center := Vector2i.ZERO
var extent := Vector2i(22, 14)


func configure(terrain_renderer, world_center: Vector2i) -> void:
	terrain = terrain_renderer
	center = world_center
	queue_redraw()


func _draw() -> void:
	if terrain == null:
		return
	for y in range(center.y - extent.y, center.y + extent.y + 1):
		for x in range(center.x - extent.x, center.x + extent.x + 1):
			var cell := Vector2i(x, y)
			var height: int = terrain.get_world_surface_elevation(cell)
			var south_height: int = terrain.get_world_surface_elevation(cell + Vector2i.DOWN)
			var top := Vector2(cell * TILE_SIZE) - Vector2(0, height * HEIGHT_STEP)
			draw_rect(Rect2(top, Vector2(TILE_SIZE)), Color(0.12, 0.85, 0.27, 0.34), true)
			draw_rect(Rect2(top, Vector2(TILE_SIZE)), Color(0.03, 0.08, 0.04, 0.72), false, 1.0)
			if height <= south_height:
				continue
			var face_top := Vector2(
				cell.x * TILE_SIZE.x,
				(cell.y + 1) * TILE_SIZE.y - height * HEIGHT_STEP)
			var face_height: int = (height - south_height) * HEIGHT_STEP
			draw_rect(
				Rect2(face_top, Vector2(TILE_SIZE.x, face_height)),
				Color(0.48, 0.24, 0.08, 0.76), true)
			draw_line(face_top, face_top + Vector2(TILE_SIZE.x, 0), Color(1.0, 0.72, 0.22), 2.0)
			var contact_y: float = face_top.y + face_height
			draw_line(
				Vector2(face_top.x, contact_y),
				Vector2(face_top.x + TILE_SIZE.x, contact_y),
				Color(0.94, 0.94, 0.98), 2.0)
			draw_rect(
				Rect2(Vector2(face_top.x, contact_y + 2), Vector2(TILE_SIZE.x, 5)),
				Color(0.34, 0.36, 0.40, 0.55), true)

extends Node2D
## Read-only Phase 7C.5 presentation diagnostic. Physical geometry uses warm
## colours; contact and cast shadows use cyan and blue-grey respectively.

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
			if height <= 0:
				continue
			var diagnostic: Dictionary = terrain.get_cliff_edge_diagnostic(cell)
			var mask: int = int(diagnostic.get("edge_mask", 0))
			var top := Vector2(cell * TILE_SIZE) - Vector2(0, height * HEIGHT_STEP)
			draw_rect(Rect2(top, Vector2(TILE_SIZE)), Color(0.12, 0.85, 0.27, 0.20), true)
			if (mask & 1) != 0:
				draw_line(top, top + Vector2(TILE_SIZE.x, 0), Color(1.0, 0.80, 0.16), 2.0)
			if (mask & 2) != 0:
				draw_rect(Rect2(top + Vector2(0, 20), Vector2(5, 12)),
					Color(0.95, 0.37, 0.08, 0.72), true)
			if (mask & 4) != 0:
				draw_rect(Rect2(top + Vector2(27, 20), Vector2(5, 12)),
					Color(1.0, 0.48, 0.12, 0.72), true)
			var south_height: int = terrain.get_world_surface_elevation(cell + Vector2i.DOWN)
			if height <= south_height:
				continue
			var face_top := Vector2(cell.x * TILE_SIZE.x,
				(cell.y + 1) * TILE_SIZE.y - height * HEIGHT_STEP)
			var face_height: int = (height - south_height) * HEIGHT_STEP
			draw_rect(Rect2(face_top, Vector2(TILE_SIZE.x, face_height)),
				Color(0.48, 0.22, 0.06, 0.62), true)
			var contact_y: float = face_top.y + face_height
			draw_line(Vector2(face_top.x, contact_y),
				Vector2(face_top.x + TILE_SIZE.x, contact_y), Color(0.20, 0.92, 0.92), 2.0)
			var south_id: int = terrain.get_world_cell(cell + Vector2i.DOWN)
			if not bool(terrain.liquid_by_id.get(south_id, false)):
				draw_rect(Rect2(Vector2(face_top.x, contact_y + 2), Vector2(TILE_SIZE.x, 5)),
					Color(0.25, 0.32, 0.48, 0.48), true)

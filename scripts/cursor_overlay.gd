extends Node2D
## Renders non-authoritative paint feedback and the visible camera grid.

const TILE_SIZE: float = 32.0
var selected_cell: Vector2i = Vector2i.ZERO
var selected_height: int = 0
var selected_is_cliff: bool = false
var selected_cliff_drop: int = 0
var height_step: float = 16.0
var enabled: bool = true
var show_grid: bool = false
var show_affected_dual_cells: bool = false
var show_elevation_overlay: bool = false
var height_lookup: Callable
var cell_polygon_lookup: Callable
var brush_cells: Array[Vector2i] = [Vector2i.ZERO]
var visible_world_rect: Rect2 = Rect2(Vector2(-640.0, -360.0), Vector2(1280.0, 720.0))


func set_visible_world_rect(value: Rect2) -> void:
    if visible_world_rect.is_equal_approx(value):
        return
    visible_world_rect = value
    if show_grid or show_elevation_overlay:
        queue_redraw()


func get_selected_cell_rect() -> Rect2:
    if cell_polygon_lookup.is_valid():
        return _polygon_bounds(cell_polygon_lookup.call(selected_cell))
    return Rect2(
        Vector2(selected_cell) * TILE_SIZE - Vector2(0.0, selected_height * height_step),
        Vector2.ONE * TILE_SIZE)

func _draw() -> void:
    if show_elevation_overlay and height_lookup.is_valid():
        _draw_elevation_overlay()
    if show_grid:
        var margin: float = TILE_SIZE
        var left: float = visible_world_rect.position.x - margin
        var right: float = visible_world_rect.end.x + margin
        var top: float = visible_world_rect.position.y - margin
        var bottom: float = visible_world_rect.end.y + margin
        var first_x: int = floori(left / TILE_SIZE)
        var last_x: int = ceili(right / TILE_SIZE)
        var first_y: int = floori(top / TILE_SIZE)
        var last_y: int = ceili(bottom / TILE_SIZE)
        var grid_color := Color(1, 1, 1, 0.17)
        for x in range(first_x, last_x + 1):
            var line_x: float = x * TILE_SIZE
            draw_line(Vector2(line_x, top), Vector2(line_x, bottom), grid_color, 1.0)
        for y in range(first_y, last_y + 1):
            var line_y: float = y * TILE_SIZE
            draw_line(Vector2(left, line_y), Vector2(right, line_y), grid_color, 1.0)
    if show_affected_dual_cells:
        var affected_color := Color(0.2, 0.9, 1.0, 0.55)
        for offset in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
            var dual_cell: Vector2i = selected_cell + offset
            if cell_polygon_lookup.is_valid():
                _draw_polygon_outline(cell_polygon_lookup.call(dual_cell), affected_color, 1.0)
            else:
                var dual_origin: Vector2 = Vector2(dual_cell) * TILE_SIZE - Vector2.ONE * TILE_SIZE * 0.5
                draw_rect(Rect2(dual_origin, Vector2.ONE * TILE_SIZE), affected_color, false, 1.0)
    if enabled:
        # Every logical brush cell is projected independently so previews stay
        # aligned with raised surfaces at every camera zoom.
        for brush_cell in brush_cells:
            var elevation: int = selected_height
            if height_lookup.is_valid():
                elevation = int(height_lookup.call(brush_cell))
            if cell_polygon_lookup.is_valid():
                var brush_polygon: PackedVector2Array = cell_polygon_lookup.call(brush_cell)
                draw_colored_polygon(brush_polygon, Color(0.18, 0.82, 1.0, 0.12))
                _draw_polygon_outline(brush_polygon, Color(0.05, 0.08, 0.10, 0.88), 3.0)
                _draw_polygon_outline(brush_polygon, Color(0.55, 0.92, 1.0, 0.96), 1.5)
            else:
                var brush_rect := Rect2(
                    Vector2(brush_cell) * TILE_SIZE - Vector2(0.0, elevation * height_step),
                    Vector2.ONE * TILE_SIZE)
                draw_rect(brush_rect, Color(0.18, 0.82, 1.0, 0.12), true)
                draw_rect(brush_rect, Color(0.05, 0.08, 0.10, 0.88), false, 3.0)
                draw_rect(brush_rect, Color(0.55, 0.92, 1.0, 0.96), false, 1.5)
        var selected_rect: Rect2 = get_selected_cell_rect()
        if selected_is_cliff and selected_cliff_drop > 0:
            var face_rect := Rect2(
                Vector2(selected_rect.position.x, selected_rect.end.y),
                Vector2(TILE_SIZE, selected_cliff_drop * height_step))
            draw_rect(face_rect, Color(1.0, 0.55, 0.2, 0.28), true)
            draw_rect(face_rect, Color(1.0, 0.62, 0.24, 0.95), false, 2.0)
        if show_affected_dual_cells:
            draw_circle(
                selected_rect.position + Vector2.ONE * TILE_SIZE * 0.5,
                3.0, Color(1.0, 0.3, 0.3, 0.95))


func _draw_elevation_overlay() -> void:
    var colors := [
        Color(0.10, 0.55, 0.95, 0.56),
        Color(0.18, 0.82, 0.32, 0.56),
        Color(1.00, 0.66, 0.12, 0.56),
        Color(0.86, 0.22, 0.82, 0.56),
    ]
    var first_x: int = floori(visible_world_rect.position.x / TILE_SIZE) - 1
    var last_x: int = ceili(visible_world_rect.end.x / TILE_SIZE) + 1
    var first_y: int = floori(visible_world_rect.position.y / TILE_SIZE) - 1
    var last_y: int = ceili(visible_world_rect.end.y / TILE_SIZE) + 3
    for y in range(first_y, last_y + 1):
        for x in range(first_x, last_x + 1):
            var world_cell := Vector2i(x, y)
            var elevation: int = clampi(int(height_lookup.call(world_cell)), 0, 3)
            var surface_rect := Rect2(
                Vector2(world_cell) * TILE_SIZE - Vector2(0.0, elevation * height_step),
                Vector2.ONE * TILE_SIZE)
            draw_rect(surface_rect, colors[elevation], true)
            draw_rect(surface_rect, Color(1.0, 1.0, 1.0, 0.30), false, 1.0)
            var south_elevation: int = clampi(
                int(height_lookup.call(world_cell + Vector2i.DOWN)), 0, 3)
            if elevation > south_elevation:
                var face_rect := Rect2(
                    Vector2(surface_rect.position.x, surface_rect.end.y),
                    Vector2(TILE_SIZE, (elevation - south_elevation) * height_step))
                var face_color: Color = colors[elevation].darkened(0.45)
                face_color.a = 0.72
                draw_rect(face_rect, face_color, true)
                draw_rect(face_rect, Color(0.05, 0.05, 0.05, 0.75), false, 1.0)


func _draw_polygon_outline(
        polygon: PackedVector2Array, color: Color, width: float) -> void:
    var closed := PackedVector2Array(polygon)
    closed.append(polygon[0])
    draw_polyline(closed, color, width, true)


func _polygon_bounds(polygon: PackedVector2Array) -> Rect2:
    var minimum: Vector2 = polygon[0]
    var maximum: Vector2 = polygon[0]
    for point in polygon:
        minimum.x = minf(minimum.x, point.x)
        minimum.y = minf(minimum.y, point.y)
        maximum.x = maxf(maximum.x, point.x)
        maximum.y = maxf(maximum.y, point.y)
    return Rect2(minimum, maximum - minimum)

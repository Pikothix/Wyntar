extends Node2D
## One elevation band for globally sorted environmental-object atlas draws.
## It is one CanvasItem regardless of object count.

const ATLAS_CELL_SIZE := Vector2i(96, 96)

var atlas_texture: Texture2D
var atlas_by_id: Dictionary
var unripe_atlas_by_id: Dictionary
var definitions_by_id: Dictionary
var draw_items: Array = []
var selected_resource_id: String = ""


func configure(
        shared_atlas: Texture2D,
        shared_atlas_by_id: Dictionary,
        shared_unripe_atlas_by_id: Dictionary,
        shared_definitions_by_id: Dictionary) -> void:
    atlas_texture = shared_atlas
    atlas_by_id = shared_atlas_by_id
    unripe_atlas_by_id = shared_unripe_atlas_by_id
    definitions_by_id = shared_definitions_by_id
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func set_draw_items(items: Array) -> void:
    draw_items = items
    queue_redraw()


func set_atlas_texture(shared_atlas: Texture2D) -> void:
    atlas_texture = shared_atlas
    queue_redraw()


func set_selected_resource_id(resource_id: String) -> void:
    if selected_resource_id == resource_id:
        return
    selected_resource_id = resource_id
    queue_redraw()


func update_resource_flags(resource_id: String, flags: int) -> bool:
    for index in range(draw_items.size()):
        var item: Dictionary = draw_items[index]
        if String(item.get("resource_id", "")) != resource_id:
            continue
        item["resource_flags"] = flags
        draw_items[index] = item
        queue_redraw()
        return true
    return false


func _draw() -> void:
    for item in draw_items:
        var object_id: int = int(item["id"])
        var definition: Dictionary = definitions_by_id[object_id]
        var flags: int = int(item.get("resource_flags", 0))
        var ripe: bool = (flags & 2) != 0
        var atlas_start: int = int(atlas_by_id[object_id])
        if not ripe and unripe_atlas_by_id.has(object_id):
            atlas_start = int(unripe_atlas_by_id[object_id])
        var atlas_x: int = atlas_start + int(item["variant"])
        var root_position: Vector2 = item["root_position"]
        var root_anchor: Vector2i = definition["root_anchor"]
        draw_texture_rect_region(
            atlas_texture,
            Rect2(root_position - Vector2(root_anchor), Vector2(ATLAS_CELL_SIZE)),
            Rect2(
                Vector2(atlas_x * ATLAS_CELL_SIZE.x, 0),
                Vector2(ATLAS_CELL_SIZE)))
        var resource_id: String = String(item.get("resource_id", ""))
        if (flags & 1) != 0:
            var marker := PackedVector2Array([
                root_position + Vector2(0, -7), root_position + Vector2(7, 0),
                root_position + Vector2(0, 7), root_position + Vector2(-7, 0)])
            draw_colored_polygon(marker, Color(1.0, 0.76, 0.18, 0.24))
            draw_polyline(marker, Color(1.0, 0.82, 0.28, 0.95), 1.5)
        if not resource_id.is_empty() and resource_id == selected_resource_id:
            draw_arc(root_position, 11.0, 0.0, TAU, 20, Color(0.35, 0.94, 1.0, 0.95), 2.0)

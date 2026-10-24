extends Camera2D
## Owns map-camera navigation and camera-derived viewport calculations.
## Main routes unhandled input here and passes the resulting visible rectangle
## to presentation systems; this controller never owns terrain streaming.

signal zoom_changed(zoom_value: float)

const PAN_SPEED: float = 700.0
const MIN_ZOOM: float = 0.001
const MAX_ZOOM: float = 166.0
const ZOOM_FACTOR: float = 1.15
const DEFAULT_CENTER: Vector2 = Vector2(16.0, 16.0)

var _middle_panning: bool = false


func update_keyboard_movement(delta: float) -> void:
	var direction := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT))
			- float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN))
			- float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
	)
	pan_direction(direction, delta)


func pan_direction(direction: Vector2, delta: float) -> void:
	if direction.is_zero_approx():
		return
	position += direction.normalized() * PAN_SPEED * delta / zoom.x
	force_update_scroll()


func release_middle_pan_if_needed() -> void:
	if _middle_panning and not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_middle_panning = false


func handle_pointer_input(event: InputEvent) -> bool:
	var mouse_button := event as InputEventMouseButton
	if mouse_button != null:
		if mouse_button.button_index == MOUSE_BUTTON_MIDDLE:
			_middle_panning = mouse_button.pressed
			return true
		if mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_toward_screen_point(
				ZOOM_FACTOR, get_viewport().get_mouse_position(), get_viewport_rect().size)
			return true
		if mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_toward_screen_point(
				1.0 / ZOOM_FACTOR, get_viewport().get_mouse_position(), get_viewport_rect().size)
			return true
		return false

	var mouse_motion := event as InputEventMouseMotion
	if mouse_motion != null and _middle_panning:
		position -= mouse_motion.relative / zoom.x
		force_update_scroll()
		return true
	return false


func handle_navigation_shortcut(event: InputEventKey) -> bool:
	if event.keycode != KEY_HOME:
		return false
	reset_view()
	return true


func zoom_toward_screen_point(
		factor: float, screen_point: Vector2, viewport_size: Vector2) -> void:
	var old_zoom: float = zoom.x
	var new_zoom: float = clampf(old_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(old_zoom, new_zoom):
		return

	var cursor_offset: Vector2 = screen_point - viewport_size * 0.5
	var world_under_cursor: Vector2 = position + cursor_offset / old_zoom
	zoom = Vector2.ONE * new_zoom
	position = world_under_cursor - cursor_offset / new_zoom
	force_update_scroll()
	zoom_changed.emit(new_zoom)


func reset_view() -> void:
	apply_state(DEFAULT_CENTER, 1.0)
	_middle_panning = false


func apply_state(camera_position: Vector2, zoom_value: float) -> void:
	position = camera_position
	zoom = Vector2.ONE * zoom_value
	force_update_scroll()
	zoom_changed.emit(zoom.x)


func is_middle_panning() -> bool:
	return _middle_panning


func get_visible_world_rect(canvas_item: CanvasItem, viewport_size: Vector2) -> Rect2:
	var inverse_canvas: Transform2D = canvas_item.get_global_transform_with_canvas().affine_inverse()
	var top_left: Vector2 = inverse_canvas * Vector2.ZERO
	var bottom_right: Vector2 = inverse_canvas * viewport_size
	return Rect2(top_left, bottom_right - top_left).abs()

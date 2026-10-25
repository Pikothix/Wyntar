extends RefCounted
## E1B presentation-only pixel renderer. Resolved anatomy drives distinct body,
## head, limb, ear, snout, tail, and marking grammars; simulation stays absent.

const CANVAS_SIZE := 72
const CENTER := Vector2(36.0, 38.0)

static func render_creature(anatomy: Dictionary, direction: String = "south") -> Dictionary:
	var image := Image.create(CANVAS_SIZE, CANVAS_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var d: Dictionary = anatomy.dimensions
	var a: Dictionary = anatomy.attachments
	var palette: Dictionary = anatomy.palette
	var traits: Dictionary = anatomy.traits
	var transform := _direction_transform(direction)
	var body_center := CENTER
	var head_root: Vector2 = _point(a.head_root, transform) + body_center
	var tail_root: Vector2 = _point(a.tail_root, transform) + body_center
	var head_center: Vector2 = head_root + _point(Vector2(0, float(d.neck_length) + float(d.head_size) * 0.42), transform)
	_draw_tail(image, tail_root, d, traits, palette, transform)
	var limb_endpoints: Array[Vector2i] = []
	var marking_pixels := 0
	for key in ["leg_back_left", "leg_back_right", "leg_front_left", "leg_front_right"]:
		var leg_result := _draw_leg(image, Vector2(a[key]), d, palette, anatomy.markings, transform)
		limb_endpoints.append(leg_result.endpoint)
		marking_pixels += int(leg_result.marking_pixels)
	_draw_body(image, body_center + Vector2(1, 2), d, palette.shadow, transform, 1.08)
	_draw_body(image, body_center, d, palette.base, transform)
	_draw_body_highlight(image, body_center, d, palette.highlight, transform)
	marking_pixels += _draw_body_markings(image, anatomy, body_center, transform)
	_line(image, head_root - _point(Vector2(0, 1), transform), head_center, maxi(2, roundi(float(d.head_width) * 0.38)), palette.shadow)
	_line(image, head_root, head_center, maxi(1, roundi(float(d.head_width) * 0.3)), palette.base)
	_draw_ears(image, anatomy, head_center, transform)
	_draw_head(image, head_center + Vector2(1, 1), d, traits, palette.shadow, transform, 1.08)
	_draw_head(image, head_center, d, traits, palette.base, transform)
	_draw_head_highlight(image, head_center, d, traits, palette.highlight, transform)
	_draw_face(image, anatomy, head_center, transform)
	var bounds := _opaque_bounds(image)
	var clipped: bool = bounds.position.x <= 0 or bounds.position.y <= 0 or bounds.end.x >= CANVAS_SIZE - 1 or bounds.end.y >= CANVAS_SIZE - 1
	return {
		"image": image, "opaque_bounds": bounds, "clipped": clipped,
		"marking_pixels": marking_pixels, "marking_pixels_outside_anatomy": 0,
		"ground_contact_pixel": Vector2i(roundi(CENTER.x), bounds.end.y - 1),
		"anatomy_pivot_pixel": Vector2i(CENTER),
		"head_root_pixel": Vector2i(head_root.round()),
		"head_center_pixel": Vector2i(head_center.round()),
		"limb_endpoints": limb_endpoints, "direction": direction,
	}

static func render_rig_parts(anatomy: Dictionary, direction: String = "south") -> Dictionary:
	## Generates immutable presentation layers once. Animation subsequently moves
	## these pixels around anatomy-derived pivots without rerunning appearance work.
	var d: Dictionary = anatomy.dimensions
	var a: Dictionary = anatomy.attachments
	var palette: Dictionary = anatomy.palette
	var traits: Dictionary = anatomy.traits
	var transform := _direction_transform(direction)
	var body_center := CENTER
	var head_root: Vector2 = _point(a.head_root, transform) + body_center
	var tail_root: Vector2 = _point(a.tail_root, transform) + body_center
	var head_center: Vector2 = head_root + _point(Vector2(0, float(d.neck_length) + float(d.head_size) * 0.42), transform)
	var layers: Dictionary = {}

	var tail := _new_layer()
	if float(d.tail_length) >= 13.0:
		_draw_tail_range(tail, tail_root, d, traits, palette, transform, 0, 3)
	else:
		_draw_tail(tail, tail_root, d, traits, palette, transform)
	layers.tail = tail
	if float(d.tail_length) >= 13.0:
		var middle_tail := _new_layer()
		_draw_tail_range(middle_tail, tail_root, d, traits, palette, transform, 3, 6)
		layers.tail_segment_0 = middle_tail
		var tip_tail := _new_layer()
		_draw_tail_range(tip_tail, tail_root, d, traits, palette, transform, 6, 8)
		layers.tail_segment_1 = tip_tail
	for key in ["leg_back_left", "leg_back_right", "leg_front_left", "leg_front_right"]:
		var leg := _new_layer()
		_draw_leg(leg, Vector2(a[key]), d, palette, anatomy.markings, transform)
		layers[key] = leg

	var body := _new_layer()
	_draw_body(body, body_center + Vector2(1, 2), d, palette.shadow, transform, 1.08)
	_draw_body(body, body_center, d, palette.base, transform)
	_draw_body_highlight(body, body_center, d, palette.highlight, transform)
	_draw_body_markings(body, anatomy, body_center, transform)
	layers.body = body

	for side_data in [["ear_left", -1.0], ["ear_right", 1.0]]:
		var ear := _new_layer()
		_draw_ear(ear, anatomy, head_center, transform, float(side_data[1]))
		layers[side_data[0]] = ear

	var head := _new_layer()
	_line(head, head_root - _point(Vector2(0, 1), transform), head_center, maxi(2, roundi(float(d.head_width) * 0.38)), palette.shadow)
	_line(head, head_root, head_center, maxi(1, roundi(float(d.head_width) * 0.3)), palette.base)
	_draw_head(head, head_center + Vector2(1, 1), d, traits, palette.shadow, transform, 1.08)
	_draw_head(head, head_center, d, traits, palette.base, transform)
	_draw_head_highlight(head, head_center, d, traits, palette.highlight, transform)
	_draw_face(head, anatomy, head_center, transform)
	layers.head = head
	return {"layers": layers, "direction": direction}

static func _new_layer() -> Image:
	var image := Image.create(CANVAS_SIZE, CANVAS_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	return image

static func _direction_transform(direction: String) -> Dictionary:
	match direction:
		"north": return {"xx": -1.0, "xy": 0.0, "yx": 0.0, "yy": -1.0}
		"east": return {"xx": 0.0, "xy": 1.0, "yx": -1.0, "yy": 0.0}
		"west": return {"xx": 0.0, "xy": -1.0, "yx": 1.0, "yy": 0.0}
		_: return {"xx": 1.0, "xy": 0.0, "yx": 0.0, "yy": 1.0}

static func _point(value: Vector2, transform: Dictionary) -> Vector2:
	return Vector2(value.x * transform.xx + value.y * transform.xy, value.x * transform.yx + value.y * transform.yy)

static func _inverse_point(value: Vector2, transform: Dictionary) -> Vector2:
	return Vector2(value.x * transform.xx + value.y * transform.yx, value.x * transform.xy + value.y * transform.yy)

static func _body_half_width(local_y: float, d: Dictionary, scale: float = 1.0) -> float:
	var half_length: float = float(d.torso_length) * 0.5 * scale
	var normal_y: float = local_y / maxf(half_length, 0.1)
	if absf(normal_y) > 1.0:
		return 0.0
	var exponent: float = lerpf(0.72, 0.38, float(d.torso_roundness))
	var curved: float = pow(maxf(0.0, 1.0 - normal_y * normal_y), exponent)
	var profile_t: float = clampf((normal_y + 1.0) * 0.5, 0.0, 1.0)
	var profile_scale: float = lerpf(float(d.hip_scale), float(d.shoulder_scale), profile_t)
	var end_taper: float = 1.0 - float(d.torso_taper) * absf(normal_y)
	return float(d.torso_width) * 0.5 * scale * curved * profile_scale * end_taper

static func _inside_body(point: Vector2, center: Vector2, d: Dictionary, transform: Dictionary, inset: float = 0.0) -> bool:
	var local := _inverse_point(point - center, transform)
	var half_width: float = _body_half_width(local.y, d) - inset
	return half_width > 0.0 and absf(local.x) <= half_width

static func _draw_body(image: Image, center: Vector2, d: Dictionary, color: Color, transform: Dictionary, scale: float = 1.0) -> void:
	var radius: int = ceili(maxf(float(d.torso_length), float(d.torso_width)) * 0.75 * scale)
	for y in range(maxi(0, floori(center.y - radius)), mini(image.get_height() - 1, ceili(center.y + radius)) + 1):
		for x in range(maxi(0, floori(center.x - radius)), mini(image.get_width() - 1, ceili(center.x + radius)) + 1):
			var local := _inverse_point(Vector2(x, y) - center, transform)
			if absf(local.x) <= _body_half_width(local.y, d, scale):
				image.set_pixel(x, y, color)

static func _draw_body_highlight(image: Image, center: Vector2, d: Dictionary, color: Color, transform: Dictionary) -> void:
	var highlight_center := center + _point(Vector2(-float(d.torso_width) * 0.16, -float(d.torso_length) * 0.16), transform)
	_paint_ellipse_clipped_to_body(image, highlight_center, float(d.torso_width) * 0.27, float(d.torso_length) * 0.28, color, center, d, transform)

static func _draw_tail(image: Image, root: Vector2, d: Dictionary, traits: Dictionary, palette: Dictionary, transform: Dictionary) -> void:
	_draw_tail_range(image, root, d, traits, palette, transform, 0, 8)

static func _draw_tail_range(image: Image, root: Vector2, d: Dictionary, traits: Dictionary, palette: Dictionary, transform: Dictionary, start_step: int, end_step: int) -> void:
	var length: float = float(d.tail_length)
	var curve: float = float(traits.tail_curve)
	var curve_scale: float = 0.45 if traits.tail_shape == "rounded" else 1.0
	var start_t: float = float(start_step) / 8.0
	var previous := root + _point(Vector2(curve * length * start_t * start_t * curve_scale, -length * start_t), transform)
	for step in range(start_step + 1, end_step + 1):
		var t: float = float(step) / 8.0
		var local := Vector2(curve * length * t * t * curve_scale, -length * t)
		var point := root + _point(local, transform)
		var taper: float = 1.0 - t * (0.58 if traits.tail_shape == "curved" else 0.3)
		_line(image, previous, point, maxi(1, roundi(float(d.tail_thickness) * taper)), palette.shadow)
		previous = point
	if end_step < 8:
		return
	var tip_radius: float = 1.2
	if traits.tail_shape == "rounded":
		tip_radius = float(d.tail_thickness) * 0.72
	elif traits.tail_shape == "club":
		tip_radius = float(d.tail_thickness) * 0.62
	_ellipse(image, previous, tip_radius, tip_radius, palette.base)

static func _draw_leg(image: Image, local_root: Vector2, d: Dictionary, palette: Dictionary, markings: Dictionary, transform: Dictionary) -> Dictionary:
	var side: float = -1.0 if local_root.x < 0.0 else 1.0
	var pair_sign: float = -1.0 if local_root.y < 0.0 else 1.0
	var length: float = float(d.leg_length)
	var local_knee := local_root + Vector2(side * length * float(d.leg_splay) * 0.55, pair_sign * length * 0.12)
	var local_end := local_root + Vector2(side * length * float(d.leg_splay), pair_sign * length * 0.3)
	var root := CENTER + _point(local_root, transform)
	var knee := CENTER + _point(local_knee, transform)
	var endpoint := CENTER + _point(local_end, transform)
	var thickness: int = maxi(2, roundi(float(d.leg_thickness)))
	_line(image, root, knee, thickness + 1, palette.shadow)
	_line(image, knee, endpoint, thickness + 1, palette.shadow)
	_line(image, root, knee, thickness, palette.base)
	_line(image, knee, endpoint, thickness, palette.base)
	_ellipse(image, endpoint, float(thickness) * 0.78 + 0.8, float(thickness) * 0.48 + 0.7, palette.shadow)
	var marking_pixels := 0
	if markings.enabled and markings.style == "socks":
		var marking_color := _marking_color(palette, markings)
		_line(image, knee.lerp(endpoint, 0.38), endpoint, maxi(1, thickness - 1), marking_color)
		marking_pixels = maxi(1, roundi(knee.distance_to(endpoint)))
	return {"endpoint": Vector2i(endpoint.round()), "marking_pixels": marking_pixels}

static func _draw_ears(image: Image, anatomy: Dictionary, head: Vector2, transform: Dictionary) -> void:
	_draw_ear(image, anatomy, head, transform, -1.0)
	_draw_ear(image, anatomy, head, transform, 1.0)

static func _draw_ear(image: Image, anatomy: Dictionary, head: Vector2, transform: Dictionary, side: float) -> void:
	var d: Dictionary = anatomy.dimensions
	var traits: Dictionary = anatomy.traits
	var palette: Dictionary = anatomy.palette
	var outward: float = 1.22 if traits.ear_orientation == "outward" else 0.96
	var offset := _point(Vector2(side * float(d.head_width) * 0.4 * outward, -float(d.head_size) * 0.34), transform)
	var ear_center := head + offset
	var ear_root := head + _point(Vector2(side * float(d.head_width) * 0.27, -float(d.head_size) * 0.18), transform)
	_line(image, ear_root, ear_center, maxi(2, roundi(float(d.ear_size) * 0.62)), palette.shadow)
	_line(image, ear_root, ear_center, maxi(1, roundi(float(d.ear_size) * 0.4)), palette.base)
	match traits.ear_shape:
		"pointed":
			_draw_tapered_ear(image, ear_center, side, float(d.ear_size), palette, transform)
		"long":
			_ellipse(image, ear_center, float(d.ear_size) * 0.38, float(d.ear_size) * 0.92, palette.shadow)
			_ellipse(image, ear_center, float(d.ear_size) * 0.25, float(d.ear_size) * 0.72, palette.base)
		_:
			_ellipse(image, ear_center, float(d.ear_size) * 0.62 + 0.7, float(d.ear_size) * 0.56 + 0.7, palette.shadow)
			_ellipse(image, ear_center, float(d.ear_size) * 0.56, float(d.ear_size) * 0.5, palette.base)

static func _draw_tapered_ear(image: Image, center: Vector2, side: float, size: float, palette: Dictionary, transform: Dictionary) -> void:
	var root := center + _point(Vector2(-side * size * 0.16, size * 0.3), transform)
	var tip := center + _point(Vector2(side * size * 0.18, -size * 0.85), transform)
	_line(image, root, tip, maxi(2, roundi(size * 0.62)), palette.shadow)
	_line(image, root, tip, maxi(1, roundi(size * 0.38)), palette.base)

static func _draw_head(image: Image, center: Vector2, d: Dictionary, traits: Dictionary, color: Color, transform: Dictionary, scale: float = 1.0) -> void:
	var rx: float = float(d.head_width) * 0.5 * scale
	var ry: float = float(d.head_size) * 0.5 * scale
	var radius: int = ceili(maxf(rx, ry) + 2.0)
	for y in range(maxi(0, floori(center.y - radius)), mini(image.get_height() - 1, ceili(center.y + radius)) + 1):
		for x in range(maxi(0, floori(center.x - radius)), mini(image.get_width() - 1, ceili(center.x + radius)) + 1):
			var local := _inverse_point(Vector2(x, y) - center, transform)
			var normal_y: float = local.y / maxf(ry, 0.1)
			if absf(normal_y) > 1.0:
				continue
			var half_width: float = rx * sqrt(maxf(0.0, 1.0 - normal_y * normal_y))
			if traits.head_shape == "wedge":
				half_width *= lerpf(1.08, 0.58, (normal_y + 1.0) * 0.5)
			elif traits.head_shape == "broad":
				half_width *= 1.08 - 0.08 * absf(normal_y)
			if absf(local.x) <= half_width:
				image.set_pixel(x, y, color)

static func _draw_head_highlight(image: Image, center: Vector2, d: Dictionary, traits: Dictionary, color: Color, transform: Dictionary) -> void:
	var point := center + _point(Vector2(-float(d.head_width) * 0.14, -float(d.head_size) * 0.18), transform)
	_ellipse(image, point, float(d.head_width) * 0.22, float(d.head_size) * 0.2, color)

static func _draw_face(image: Image, anatomy: Dictionary, center: Vector2, transform: Dictionary) -> void:
	var d: Dictionary = anatomy.dimensions
	var traits: Dictionary = anatomy.traits
	var palette: Dictionary = anatomy.palette
	var forward := _point(Vector2(0, 1), transform)
	var side_axis := _point(Vector2(1, 0), transform)
	var head_rx: float = float(d.head_width) * 0.5
	var head_ry: float = float(d.head_size) * 0.5
	var snout_length: float = float(d.snout_length)
	var snout_center := center + forward * (head_ry * 0.7 + snout_length * 0.32)
	var snout_rx: float = maxf(1.7, head_rx * float(d.snout_width))
	var snout_ry: float = maxf(1.4, snout_length * 0.48)
	_ellipse(image, snout_center + Vector2(1, 1), snout_rx + 0.7, snout_ry + 0.7, palette.shadow)
	_ellipse(image, snout_center, snout_rx, snout_ry, palette.base.darkened(0.08))
	var eye_line := center + forward * (head_ry * 0.02)
	var spacing: float = head_rx * float(traits.eye_spacing)
	_ellipse(image, eye_line - side_axis * spacing, 1.0, 1.0, palette.detail)
	_ellipse(image, eye_line + side_axis * spacing, 1.0, 1.0, palette.detail)
	_ellipse(image, snout_center + forward * (snout_ry * 0.42), 1.3, 0.9, palette.detail)

static func _draw_body_markings(image: Image, anatomy: Dictionary, center: Vector2, transform: Dictionary) -> int:
	var markings: Dictionary = anatomy.markings
	if not markings.enabled or markings.style in ["none", "socks"]:
		return 0
	var d: Dictionary = anatomy.dimensions
	var color := _marking_color(anatomy.palette, markings)
	var count := 0
	match markings.style:
		"spots":
			for spot: Dictionary in markings.spots:
				var local_center := Vector2(float(spot.u) * float(d.torso_width) * 0.5, float(spot.v) * float(d.torso_length) * 0.5)
				var radius: float = float(spot.radius)
				count += _paint_marking_ellipse(image, center + _point(local_center, transform), radius, radius, color, center, d, transform)
		"patches":
			for patch: Dictionary in markings.patches:
				var local_center := Vector2(float(patch.u) * float(d.torso_width) * 0.5, float(patch.v) * float(d.torso_length) * 0.5)
				count += _paint_marking_ellipse(image, center + _point(local_center, transform), float(patch.rx), float(patch.ry), color, center, d, transform)
		"stripes":
			var radius: int = ceili(maxf(float(d.torso_length), float(d.torso_width)) * 0.55)
			for y in range(maxi(0, floori(center.y - radius)), mini(image.get_height() - 1, ceili(center.y + radius)) + 1):
				for x in range(maxi(0, floori(center.x - radius)), mini(image.get_width() - 1, ceili(center.x + radius)) + 1):
					var point := Vector2(x, y)
					if not _inside_body(point, center, d, transform, 0.8):
						continue
					var local := _inverse_point(point - center, transform)
					for stripe_v in markings.stripes:
						var stripe_y: float = float(stripe_v) * float(d.torso_length) * 0.5
						if absf(local.y - stripe_y + local.x * 0.16) <= 0.85:
							image.set_pixel(x, y, color)
							count += 1
							break
	return count

static func _marking_color(palette: Dictionary, markings: Dictionary) -> Color:
	return Color(palette.highlight).lerp(Color(palette.shadow), 1.0 - float(markings.tone))

static func _paint_marking_ellipse(image: Image, point: Vector2, rx: float, ry: float, color: Color, body_center: Vector2, d: Dictionary, transform: Dictionary) -> int:
	var count := 0
	var radius := maxf(rx, ry)
	for y in range(maxi(0, floori(point.y - radius)), mini(image.get_height() - 1, ceili(point.y + radius)) + 1):
		for x in range(maxi(0, floori(point.x - radius)), mini(image.get_width() - 1, ceili(point.x + radius)) + 1):
			var delta := _inverse_point(Vector2(x, y) - point, transform)
			if delta.x * delta.x / (rx * rx) + delta.y * delta.y / (ry * ry) <= 1.0 and _inside_body(Vector2(x, y), body_center, d, transform, 0.8):
				image.set_pixel(x, y, color)
				count += 1
	return count

static func _paint_ellipse_clipped_to_body(image: Image, point: Vector2, rx: float, ry: float, color: Color, body_center: Vector2, d: Dictionary, transform: Dictionary) -> void:
	for y in range(maxi(0, floori(point.y - ry)), mini(image.get_height() - 1, ceili(point.y + ry)) + 1):
		for x in range(maxi(0, floori(point.x - rx)), mini(image.get_width() - 1, ceili(point.x + rx)) + 1):
			var local := Vector2((float(x) - point.x) / maxf(rx, 0.1), (float(y) - point.y) / maxf(ry, 0.1))
			if local.length_squared() <= 1.0 and _inside_body(Vector2(x, y), body_center, d, transform, 0.7):
				image.set_pixel(x, y, color)

static func _ellipse(image: Image, center: Vector2, rx: float, ry: float, color: Color) -> void:
	for y in range(maxi(0, floori(center.y - ry)), mini(image.get_height() - 1, ceili(center.y + ry)) + 1):
		for x in range(maxi(0, floori(center.x - rx)), mini(image.get_width() - 1, ceili(center.x + rx)) + 1):
			var dx: float = (float(x) - center.x) / maxf(rx, 0.1)
			var dy: float = (float(y) - center.y) / maxf(ry, 0.1)
			if dx * dx + dy * dy <= 1.0:
				image.set_pixel(x, y, color)

static func _line(image: Image, from: Vector2, to: Vector2, thickness: int, color: Color) -> void:
	var steps: int = maxi(1, ceili(from.distance_to(to) * 1.5))
	for index in range(steps + 1):
		var point := from.lerp(to, float(index) / float(steps))
		_ellipse(image, point, maxf(1.2, float(thickness) * 0.5), maxf(1.2, float(thickness) * 0.5), color)

static func _opaque_bounds(image: Image) -> Rect2i:
	var minimum := Vector2i(image.get_width(), image.get_height())
	var maximum := Vector2i(-1, -1)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.0:
				continue
			minimum = Vector2i(mini(minimum.x, x), mini(minimum.y, y))
			maximum = Vector2i(maxi(maximum.x, x), maxi(maximum.y, y))
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE) if maximum.x >= 0 else Rect2i()

static func silhouette_image(source: Image, color: Color = Color.WHITE) -> Image:
	var result := Image.create(source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8)
	result.fill(Color.TRANSPARENT)
	for y in range(source.get_height()):
		for x in range(source.get_width()):
			if source.get_pixel(x, y).a > 0.0:
				result.set_pixel(x, y, color)
	return result

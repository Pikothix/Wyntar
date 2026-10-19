extends "res://tests/phase1e_capture.gd"
## Reuses the Phase 1E fixtures and framing after Phase 1G replacement and
## retirement queues have fully settled.


func _capture_mode(label: String, zoom: float, refined: bool) -> void:
	terrain.set_refined_cliff_silhouettes_enabled(refined)
	await _wait_until_idle()
	while terrain.get_pending_chunk_retirement_count() > 0:
		await process_frame
	await _wait_frames(3)
	var mode: String = "refined" if refined else "phase1d"
	var zoom_label: String = "1_0x" if is_equal_approx(zoom, 1.0) else "3_0x"
	await _save("phase1g_%s_%s_%s" % [mode, label, zoom_label])

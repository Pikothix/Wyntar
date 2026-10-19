extends SceneTree
## Phase 8A-specific startup/cache benchmark. Camera streaming must reuse the
## single bounded atlas rather than invoking generators or growing a cache.

const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var startup_begin: int = Time.get_ticks_usec()
	var terrain = TerrainRenderer.new()
	root.add_child(terrain)
	await process_frame
	var startup_usec: int = Time.get_ticks_usec() - startup_begin
	var before: Dictionary = terrain.get_environment_atlas_metrics()
	var texture_id: int = int(before["texture_instance_id"])
	var routes: Array[Rect2] = [
		Rect2(Vector2(-640, -360), Vector2(1280, 720)),
		Rect2(Vector2(32000, 16000), Vector2(1280, 720)),
		Rect2(Vector2(-24000, 28000), Vector2(1280, 720)),
		Rect2(Vector2(-640, -360), Vector2(1280, 720)),
	]
	var route_begin: int = Time.get_ticks_usec()
	for visible_rect in routes:
		terrain.update_visible_world_rect(visible_rect)
		await _wait_until_idle(terrain)
	var route_usec: int = Time.get_ticks_usec() - route_begin
	var after: Dictionary = terrain.get_environment_atlas_metrics()
	assert(int(after["texture_instance_id"]) == texture_id,
		"streaming must retain the precomputed atlas texture")
	assert(int(after["variant_count"]) == int(before["variant_count"]),
		"streaming must not grow the procedural variant cache")
	print("PHASE8A_BENCHMARK startup_ms=%.3f atlas_generation_ms=%.3f variants=%d procedural_variants=%d atlas=%s four_route_stream_ms=%.3f memory_mib=%.2f" % [
		float(startup_usec) / 1000.0,
		float(before["generation_usec"]) / 1000.0,
		int(before["variant_count"]),
		int(before["procedural_variant_count"]),
		str(before["dimensions"]),
		float(route_usec) / 1000.0,
		float(OS.get_static_memory_usage()) / 1048576.0,
	])
	print("PHASE8A_BENCHMARK: PASS")
	terrain.queue_free()
	quit(0)


func _wait_until_idle(terrain, max_frames: int = 1200) -> void:
	for _frame in range(max_frames):
		await process_frame
		if terrain.get_pending_chunk_count() == 0:
			return
	assert(false, "streaming did not become idle")

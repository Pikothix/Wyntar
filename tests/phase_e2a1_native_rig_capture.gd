extends SceneTree
## Captures fixed native-rendered neutral, idle, and walk workshop poses.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1440, 900))
	var workshop = load("res://scenes/creatures/creature_workshop.tscn").instantiate()
	root.add_child(workshop)
	for _frame in range(8):
		await process_frame
	workshop.set_animation_playing(false)
	workshop.set_joint_overlay(false)
	workshop.set_review_scale(4)
	for state_time in [["neutral", 0.0], ["idle", 0.47], ["walk", 0.19]]:
		workshop.set_animation_state(state_time[0])
		workshop.set_animation_time(state_time[1])
		for _frame in range(2):
			await process_frame
		var path := "res://.artifacts/phase_e2a1_native_%s.png" % state_time[0]
		var error := root.get_texture().get_image().save_png(path)
		assert(error == OK, "Could not save native %s capture" % state_time[0])
	print("PHASE_E2A1_NATIVE_CAPTURE: PASS")
	quit(0)

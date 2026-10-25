extends SceneTree
## Captures native and enlarged selected-creature E2A workshop review states.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1440, 900))
	var workshop = load("res://scenes/creatures/creature_workshop.tscn").instantiate()
	root.add_child(workshop)
	for _frame in range(8):
		await process_frame
	workshop.set_animation_playing(false)
	workshop.set_animation_state("walk")
	workshop.set_animation_time(0.19)
	workshop.set_review_scale(1)
	await process_frame
	var native_error := root.get_texture().get_image().save_png("res://.artifacts/phase_e2a_rig_workshop_native.png")
	assert(native_error == OK, "Could not save native E2A workshop capture")
	workshop.set_animation_state("idle")
	workshop.set_animation_time(0.47)
	workshop.set_joint_overlay(true)
	workshop.set_review_scale(4)
	await process_frame
	var enlarged_error := root.get_texture().get_image().save_png("res://.artifacts/phase_e2a_rig_workshop_4x_joints.png")
	assert(enlarged_error == OK, "Could not save enlarged E2A workshop capture")
	print("PHASE_E2A_CAPTURE: PASS")
	quit(0)

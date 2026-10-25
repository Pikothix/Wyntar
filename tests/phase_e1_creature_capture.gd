extends SceneTree
## Captures the real E1B workshop at native and enlarged review scales.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var workshop = load("res://scenes/creatures/creature_workshop.tscn").instantiate()
	root.add_child(workshop)
	for _frame in range(5):
		await process_frame
	workshop.set_review_scale(1)
	await process_frame
	var native_error := root.get_texture().get_image().save_png("res://.artifacts/phase_e1b_creature_workshop_native.png")
	assert(native_error == OK, "Could not save native E1B workshop capture")
	workshop.set_review_scale(4)
	await process_frame
	var enlarged_error := root.get_texture().get_image().save_png("res://.artifacts/phase_e1b_creature_workshop_4x.png")
	assert(enlarged_error == OK, "Could not save enlarged E1B workshop capture")
	print("PHASE_E1B_CAPTURE: PASS")
	quit(0)

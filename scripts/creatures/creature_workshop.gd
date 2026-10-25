extends Control
## Standalone E1B/E2A visual workshop. This scene owns review and playback
## state only; generated anatomy, rig definitions, and cached art stay separate.

const Species = preload("res://scripts/creatures/creature_species.gd")
const Generator = preload("res://scripts/creatures/creature_generator.gd")
const AppearanceCache = preload("res://scripts/creatures/creature_appearance_cache.gd")
const Renderer = preload("res://scripts/creatures/creature_renderer.gd")
const Rig = preload("res://scripts/creatures/creature_rig.gd")
const PoseEvaluator = preload("res://scripts/creatures/creature_pose_evaluator.gd")
const RigVisualCache = preload("res://scripts/creatures/creature_rig_visual_cache.gd")
const RigPresenter = preload("res://scripts/creatures/creature_rig_presenter.gd")

const SAMPLE_COUNT := 48
const DEFAULT_REFERENCE_SEED := 84521
const DEFAULT_VARIATION := 0.6

var reference_seed := DEFAULT_REFERENCE_SEED
var selected_archetype := "mixed"
var variation_strength := DEFAULT_VARIATION
var markings_enabled := true
var generated_creatures: Array[Dictionary] = []
var generated_images: Array[Image] = []
var batch_metrics: Dictionary = {}
var preview_scale := 2
var silhouette_only := false
var animation_state := "idle"
var animation_playing := true
var animation_speed := 1.0
var animation_time := 0.0
var joint_overlay := false
var foot_contacts := false
var inspected_limb := ""
var transition_duration := 0.35
var _transition_from_state := "idle"
var _transition_elapsed := 0.0
var _transition_active := false

var _cache := AppearanceCache.new()
var _rig_visual_cache := RigVisualCache.new()
var _selected_rig: Dictionary = {}
var _selected_visual: Dictionary = {}
var _native_presenter: Node2D
var _preview_viewport: SubViewport
var _preview_container: SubViewportContainer
var _grid: GridContainer
var _inspector: RichTextLabel
var _metrics_label: Label
var _seed_spin: SpinBox
var _archetype_option: OptionButton
var _variation_slider: HSlider
var _variation_label: Label
var _markings_check: CheckButton
var _scale_option: OptionButton
var _silhouette_check: CheckButton
var _comparison_box: HBoxContainer
var _comparison_presenters: Array[Node2D] = []
var _comparison_viewports: Array[SubViewport] = []
var _comparison_rigs: Array[Dictionary] = []
var _animation_option: OptionButton
var _play_button: Button
var _speed_slider: HSlider
var _speed_label: Label
var _joint_check: CheckButton
var _foot_check: CheckButton
var _limb_option: OptionButton
var _transition_slider: HSlider
var _transition_label: Label
var _gait_label: Label
var _animation_diagnostics: Label
var _selected_index := 0

func _process(delta: float) -> void:
	if generated_creatures.is_empty() or _selected_rig.is_empty():
		return
	if animation_playing:
		animation_time += delta * animation_speed
		if _transition_active:
			_transition_elapsed += delta * animation_speed
			if _transition_elapsed >= transition_duration:
				_transition_active = false
		_update_animated_preview()

func _ready() -> void:
	_build_interface()
	regenerate()

func regenerate() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	generated_creatures.clear()
	generated_images.clear()
	var started: int = Time.get_ticks_usec()
	var worst_usec := 0
	for index in range(SAMPLE_COUNT):
		var creature_started: int = Time.get_ticks_usec()
		var archetype := Generator.mixed_archetype(reference_seed, index) if selected_archetype == "mixed" else selected_archetype
		var seed := Generator.individual_seed(reference_seed, index)
		var anatomy := Generator.generate_creature(Species.SPECIES_ID, seed, variation_strength, archetype, markings_enabled)
		var appearance := _cache.get_or_generate(anatomy)
		generated_creatures.append(anatomy)
		generated_images.append(appearance.image)
		_add_creature_card(index, anatomy, appearance.image)
		worst_usec = maxi(worst_usec, Time.get_ticks_usec() - creature_started)
	var total_usec: int = Time.get_ticks_usec() - started
	batch_metrics = {
		"total_generation_ms": float(total_usec) / 1000.0,
		"average_generation_ms": float(total_usec) / 1000.0 / SAMPLE_COUNT,
		"worst_generation_ms": float(worst_usec) / 1000.0,
		"cache_entries": _cache.entry_count(),
		"approximate_cache_memory_bytes": _cache.approximate_memory_bytes(),
	}
	_metrics_label.text = "48 creatures  |  %.2f ms total  |  %.3f ms avg  |  %.2f ms worst  |  %.2f MiB cache" % [batch_metrics.total_generation_ms, batch_metrics.average_generation_ms, batch_metrics.worst_generation_ms, float(batch_metrics.approximate_cache_memory_bytes) / 1048576.0]
	if not generated_creatures.is_empty():
		_show_details(0)

func _build_interface() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("101820")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 8)
	margin.add_child(root_box)
	var title := Label.new()
	title.text = "WYNTAR  /  E2B PROCEDURAL GAIT WORKSHOP"
	title.add_theme_font_size_override("font_size", 20)
	root_box.add_child(title)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	root_box.add_child(controls)
	controls.add_child(_label("Reference seed"))
	_seed_spin = SpinBox.new()
	_seed_spin.min_value = 0
	_seed_spin.max_value = 2147483647
	_seed_spin.value = reference_seed
	_seed_spin.custom_minimum_size.x = 125
	controls.add_child(_seed_spin)
	controls.add_child(_label("Archetype"))
	_archetype_option = OptionButton.new()
	for item in ["mixed", "compact", "elongated", "stocky"]:
		_archetype_option.add_item(item.capitalize())
	controls.add_child(_archetype_option)
	controls.add_child(_label("Variation"))
	_variation_slider = HSlider.new()
	_variation_slider.min_value = 0.0
	_variation_slider.max_value = 1.0
	_variation_slider.step = 0.05
	_variation_slider.value = variation_strength
	_variation_slider.custom_minimum_size.x = 95
	_variation_slider.value_changed.connect(_on_variation_changed)
	controls.add_child(_variation_slider)
	_variation_label = _label("0.60")
	controls.add_child(_variation_label)
	_markings_check = CheckButton.new()
	_markings_check.text = "Markings"
	_markings_check.button_pressed = markings_enabled
	controls.add_child(_markings_check)
	controls.add_child(_label("Preview"))
	_scale_option = OptionButton.new()
	for scale in [1, 2, 4, 8]:
		_scale_option.add_item("%d×" % scale)
	_scale_option.select(1)
	_scale_option.item_selected.connect(_on_scale_selected)
	controls.add_child(_scale_option)
	_silhouette_check = CheckButton.new()
	_silhouette_check.text = "Silhouette"
	_silhouette_check.toggled.connect(_on_silhouette_toggled)
	controls.add_child(_silhouette_check)
	var regenerate_button := Button.new()
	regenerate_button.text = "Regenerate"
	regenerate_button.pressed.connect(_read_controls_and_regenerate)
	controls.add_child(regenerate_button)
	_metrics_label = Label.new()
	_metrics_label.modulate = Color("b9c8cf")
	root_box.add_child(_metrics_label)
	var animation_controls := HBoxContainer.new()
	animation_controls.add_theme_constant_override("separation", 10)
	root_box.add_child(animation_controls)
	animation_controls.add_child(_label("Animation"))
	_animation_option = OptionButton.new()
	for state_name in PoseEvaluator.STATES:
		_animation_option.add_item(String(state_name).capitalize())
	_animation_option.select(PoseEvaluator.STATES.find(animation_state))
	_animation_option.item_selected.connect(_on_animation_selected)
	animation_controls.add_child(_animation_option)
	_play_button = Button.new()
	_play_button.text = "Pause"
	_play_button.pressed.connect(_toggle_animation_playback)
	animation_controls.add_child(_play_button)
	animation_controls.add_child(_label("Speed"))
	_speed_slider = HSlider.new()
	_speed_slider.min_value = 0.05
	_speed_slider.max_value = 2.5
	_speed_slider.step = 0.05
	_speed_slider.value = animation_speed
	_speed_slider.custom_minimum_size.x = 130
	_speed_slider.value_changed.connect(_on_animation_speed_changed)
	animation_controls.add_child(_speed_slider)
	_speed_label = _label("1.0×")
	animation_controls.add_child(_speed_label)
	_joint_check = CheckButton.new()
	_joint_check.text = "Joints / pivots"
	_joint_check.toggled.connect(_on_joint_overlay_toggled)
	animation_controls.add_child(_joint_check)
	_animation_diagnostics = _label("Pose -- µs  |  Compose -- µs")
	_animation_diagnostics.modulate = Color("91d8d0")
	animation_controls.add_child(_animation_diagnostics)
	var gait_controls := HBoxContainer.new()
	gait_controls.add_theme_constant_override("separation", 10)
	root_box.add_child(gait_controls)
	gait_controls.add_child(_label("Transition"))
	_transition_slider = HSlider.new()
	_transition_slider.min_value = 0.0
	_transition_slider.max_value = 0.8
	_transition_slider.step = 0.05
	_transition_slider.value = transition_duration
	_transition_slider.custom_minimum_size.x = 110
	_transition_slider.value_changed.connect(_on_transition_duration_changed)
	gait_controls.add_child(_transition_slider)
	_transition_label = _label("0.35 s")
	gait_controls.add_child(_transition_label)
	_foot_check = CheckButton.new()
	_foot_check.text = "Foot contacts"
	_foot_check.toggled.connect(_on_foot_contacts_toggled)
	gait_controls.add_child(_foot_check)
	gait_controls.add_child(_label("Inspect limb"))
	_limb_option = OptionButton.new()
	for limb_label in ["All", "Front left", "Front right", "Back left", "Back right"]:
		_limb_option.add_item(limb_label)
	_limb_option.item_selected.connect(_on_limb_selected)
	gait_controls.add_child(_limb_option)
	_gait_label = _label("Phase --")
	_gait_label.modulate = Color("d8c991")
	gait_controls.add_child(_gait_label)
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	root_box.add_child(content)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 8
	_grid.add_theme_constant_override("h_separation", 5)
	_grid.add_theme_constant_override("v_separation", 5)
	scroll.add_child(_grid)
	var review_panel := VBoxContainer.new()
	review_panel.custom_minimum_size.x = 280
	review_panel.add_theme_constant_override("separation", 4)
	content.add_child(review_panel)
	var preview_title := _label("SELECTED CREATURE")
	preview_title.add_theme_font_size_override("font_size", 12)
	review_panel.add_child(preview_title)
	var preview_scroll := ScrollContainer.new()
	preview_scroll.custom_minimum_size.y = 290
	preview_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	preview_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	review_panel.add_child(preview_scroll)
	_preview_container = SubViewportContainer.new()
	_preview_container.custom_minimum_size = Vector2(Renderer.CANVAS_SIZE * preview_scale, Renderer.CANVAS_SIZE * preview_scale)
	_preview_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview_container.stretch = false
	preview_scroll.add_child(_preview_container)
	_preview_viewport = SubViewport.new()
	_preview_viewport.size = Vector2i(Renderer.CANVAS_SIZE * preview_scale, Renderer.CANVAS_SIZE * preview_scale)
	_preview_viewport.transparent_bg = true
	_preview_viewport.disable_3d = true
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_preview_container.add_child(_preview_viewport)
	_native_presenter = RigPresenter.new()
	_native_presenter.position = Renderer.CENTER * preview_scale
	_native_presenter.scale = Vector2.ONE * preview_scale
	_preview_viewport.add_child(_native_presenter)
	var comparison_title := _label("SAME SEED / ARCHETYPE COMPARISON")
	comparison_title.add_theme_font_size_override("font_size", 11)
	review_panel.add_child(comparison_title)
	_comparison_box = HBoxContainer.new()
	_comparison_box.add_theme_constant_override("separation", 5)
	review_panel.add_child(_comparison_box)
	_inspector = RichTextLabel.new()
	_inspector.bbcode_enabled = true
	_inspector.fit_content = false
	_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	review_panel.add_child(_inspector)

func _add_creature_card(index: int, anatomy: Dictionary, image: Image) -> void:
	var card := VBoxContainer.new()
	card.custom_minimum_size = Vector2(105, 82)
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_theme_constant_override("separation", 0)
	var button := TextureButton.new()
	button.custom_minimum_size = Vector2(68, 60)
	var display_image := _review_image(image)
	display_image.resize(72, 72, Image.INTERPOLATE_NEAREST)
	button.texture_normal = ImageTexture.create_from_image(display_image)
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.tooltip_text = "Inspect creature #%02d" % (index + 1)
	button.pressed.connect(_show_details.bind(index))
	card.add_child(button)
	var label := Label.new()
	label.text = "#%02d %s\n%d" % [index + 1, String(anatomy.archetype).substr(0, 4).to_upper(), int(anatomy.individual_seed)]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 9)
	card.add_child(label)
	_grid.add_child(card)

func _show_details(index: int) -> void:
	_selected_index = index
	var anatomy: Dictionary = generated_creatures[index]
	var d: Dictionary = anatomy.dimensions
	var traits: Dictionary = anatomy.traits
	_selected_rig = Rig.build(anatomy)
	_selected_visual = _rig_visual_cache.get_or_generate(anatomy, _selected_rig)
	_native_presenter.configure(_selected_rig, _selected_visual)
	animation_time = 0.0
	_transition_active = false
	_inspector.text = "[font_size=18][b]Creature #%02d[/b][/font_size]\nSeed: %d\nArchetype: %s\nVersion: %s\nRig: %s\n\n[b]Torso[/b]\nLength %.1f  Width %.1f\nRoundness %.2f  Taper %.2f\n\n[b]Head[/b]\n%s, %.1f × %.1f\nSnout %.1f\n\n[b]Limbs[/b]\nLeg %.1f × %.1f\nEars %s / %s (%.1f)\nTail %.1f × %.1f\nCurve %.2f\n\n[b]Marking[/b]\n%s\n\n[b]Rig[/b]\n%d joints, %d optional tail segments\nGround contact %s\nArtwork generations %d\n\n[b]Animation anchors[/b]\n%s" % [index + 1, int(anatomy.individual_seed), anatomy.archetype, anatomy.generator_version, _selected_rig.version, d.torso_length, d.torso_width, d.torso_roundness, d.torso_taper, traits.head_shape, d.head_size, d.head_width, d.snout_length, d.leg_length, d.leg_thickness, traits.ear_shape, traits.ear_orientation, d.ear_size, d.tail_length, d.tail_thickness, traits.tail_curve, anatomy.markings.style, _selected_rig.joints.size(), _selected_rig.tail_segments.size(), str(_selected_rig.ground_contact), _rig_visual_cache.generation_count, str(anatomy.attachments)]
	_update_animated_preview()
	_update_archetype_comparison()

func _read_controls_and_regenerate() -> void:
	reference_seed = roundi(_seed_spin.value)
	selected_archetype = ["mixed", "compact", "elongated", "stocky"][_archetype_option.selected]
	variation_strength = float(_variation_slider.value)
	markings_enabled = _markings_check.button_pressed
	regenerate()

func _label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	return label

func _on_variation_changed(value: float) -> void:
	_variation_label.text = "%.2f" % value

func _on_scale_selected(index: int) -> void:
	preview_scale = [1, 2, 4, 8][index]
	_update_animated_preview()

func _on_silhouette_toggled(enabled: bool) -> void:
	silhouette_only = enabled
	regenerate()

func set_review_scale(scale: int) -> void:
	preview_scale = scale if scale in [1, 2, 4, 8] else 2
	if _scale_option != null:
		_scale_option.select([1, 2, 4, 8].find(preview_scale))
	_update_animated_preview()

func set_silhouette_only(enabled: bool) -> void:
	silhouette_only = enabled
	if _silhouette_check != null:
		_silhouette_check.button_pressed = enabled
	regenerate()

func _update_selected_preview() -> void:
	_update_animated_preview()

func _update_animated_preview() -> void:
	if _native_presenter == null or _selected_rig.is_empty():
		return
	var pose_started := Time.get_ticks_usec()
	var pose := _evaluate_workshop_pose(_selected_rig)
	var pose_usec := Time.get_ticks_usec() - pose_started
	var update_started := Time.get_ticks_usec()
	_native_presenter.apply_pose(pose)
	_native_presenter.set_joint_overlay(joint_overlay)
	_native_presenter.set_silhouette(silhouette_only)
	_native_presenter.set_foot_contacts(foot_contacts)
	_native_presenter.set_inspected_limb(inspected_limb)
	var update_usec := Time.get_ticks_usec() - update_started
	_preview_container.custom_minimum_size = Vector2(Renderer.CANVAS_SIZE * preview_scale, Renderer.CANVAS_SIZE * preview_scale)
	_preview_viewport.size = Vector2i(Renderer.CANVAS_SIZE * preview_scale, Renderer.CANVAS_SIZE * preview_scale)
	_native_presenter.position = Renderer.CENTER * preview_scale
	_native_presenter.scale = Vector2.ONE * preview_scale
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if _animation_diagnostics != null:
		_animation_diagnostics.text = "Pose %d µs  |  Native %d µs  |  update %d  |  textures %d" % [pose_usec, update_usec, _native_presenter.update_count, _rig_visual_cache.texture_creation_count]
	_update_gait_label(pose)
	_update_comparison_animation()

func _on_animation_selected(index: int) -> void:
	_begin_transition(PoseEvaluator.STATES[index])

func _toggle_animation_playback() -> void:
	animation_playing = not animation_playing
	_play_button.text = "Pause" if animation_playing else "Play"
	_update_animated_preview()

func _on_animation_speed_changed(value: float) -> void:
	animation_speed = value
	_speed_label.text = "%.2f×" % value

func _on_joint_overlay_toggled(enabled: bool) -> void:
	joint_overlay = enabled
	_update_animated_preview()

func _on_foot_contacts_toggled(enabled: bool) -> void:
	foot_contacts = enabled
	_update_animated_preview()

func _on_limb_selected(index: int) -> void:
	inspected_limb = ["", "leg_front_left", "leg_front_right", "leg_back_left", "leg_back_right"][index]
	_update_animated_preview()

func _on_transition_duration_changed(value: float) -> void:
	transition_duration = value
	_transition_label.text = "%.2f s" % value

func _begin_transition(state_name: String) -> void:
	var resolved := state_name if state_name in PoseEvaluator.STATES else "neutral"
	if resolved == animation_state:
		return
	_transition_from_state = animation_state
	animation_state = resolved
	_transition_elapsed = 0.0
	_transition_active = transition_duration > 0.0
	_update_animated_preview()

func _evaluate_workshop_pose(rig: Dictionary) -> Dictionary:
	if _transition_active:
		var progress := clampf(_transition_elapsed / maxf(transition_duration, 0.001), 0.0, 1.0)
		return PoseEvaluator.evaluate_transition(rig, _transition_from_state, animation_state, animation_time, progress, {"speed": 1.0, "intensity": 1.0})
	return PoseEvaluator.evaluate_pose(rig, animation_state, animation_time, {"speed": 1.0, "intensity": 1.0})

func _update_gait_label(pose: Dictionary) -> void:
	if _gait_label == null:
		return
	var gait: Dictionary = pose.gait
	var contacts: Array[String] = []
	for leg_data in [["FL", "leg_front_left"], ["FR", "leg_front_right"], ["BL", "leg_back_left"], ["BR", "leg_back_right"]]:
		contacts.append("%s:%s" % [leg_data[0], "●" if gait.legs[leg_data[1]].contact else "○"])
	var transition_text := "  blend %.0f%%" % (float(pose.transition.progress) * 100.0) if pose.has("transition") else ""
	_gait_label.text = "Phase %.2f  %s%s" % [float(gait.phase), " ".join(contacts), transition_text]

func set_animation_state(state_name: String) -> void:
	animation_state = state_name if state_name in PoseEvaluator.STATES else "neutral"
	_transition_active = false
	if _animation_option != null:
		_animation_option.select(PoseEvaluator.STATES.find(animation_state))
	_update_animated_preview()

func transition_to_state(state_name: String) -> void:
	_begin_transition(state_name)
	if _animation_option != null:
		_animation_option.select(PoseEvaluator.STATES.find(animation_state))

func set_animation_playing(enabled: bool) -> void:
	animation_playing = enabled
	if _play_button != null:
		_play_button.text = "Pause" if enabled else "Play"

func set_animation_time(value: float) -> void:
	animation_time = value
	_update_animated_preview()

func set_joint_overlay(enabled: bool) -> void:
	joint_overlay = enabled
	if _joint_check != null:
		_joint_check.button_pressed = enabled
	_update_animated_preview()

func set_foot_contacts(enabled: bool) -> void:
	foot_contacts = enabled
	if _foot_check != null:
		_foot_check.button_pressed = enabled
	_update_animated_preview()

func select_creature(index: int) -> void:
	if generated_creatures.is_empty():
		return
	_show_details(clampi(index, 0, generated_creatures.size() - 1))

func _update_archetype_comparison() -> void:
	if _comparison_box == null or generated_creatures.is_empty():
		return
	_comparison_presenters.clear()
	_comparison_viewports.clear()
	_comparison_rigs.clear()
	for child in _comparison_box.get_children():
		_comparison_box.remove_child(child)
		child.queue_free()
	var selected: Dictionary = generated_creatures[_selected_index]
	for archetype in ["compact", "elongated", "stocky"]:
		var anatomy := Generator.generate_creature(Species.SPECIES_ID, int(selected.individual_seed), variation_strength, archetype, markings_enabled)
		var rig := Rig.build(anatomy)
		var visual := _rig_visual_cache.get_or_generate(anatomy, rig)
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 0)
		var container := SubViewportContainer.new()
		container.custom_minimum_size = Vector2(82, 64)
		container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		container.stretch = false
		entry.add_child(container)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(64, 64)
		viewport.transparent_bg = true
		viewport.disable_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		container.add_child(viewport)
		var presenter := RigPresenter.new()
		var comparison_scale := 64.0 / float(Renderer.CANVAS_SIZE)
		presenter.position = Renderer.CENTER * comparison_scale
		presenter.scale = Vector2.ONE * comparison_scale
		presenter.configure(rig, visual)
		presenter.set_silhouette(silhouette_only)
		viewport.add_child(presenter)
		_comparison_presenters.append(presenter)
		_comparison_viewports.append(viewport)
		_comparison_rigs.append(rig)
		var label := _label(String(archetype).substr(0, 4).to_upper())
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 9)
		entry.add_child(label)
		_comparison_box.add_child(entry)
	_update_comparison_animation()

func _update_comparison_animation() -> void:
	for index in range(_comparison_presenters.size()):
		var presenter: Node2D = _comparison_presenters[index]
		if not is_instance_valid(presenter):
			continue
		var pose := _evaluate_workshop_pose(_comparison_rigs[index])
		presenter.apply_pose(pose)
		presenter.set_silhouette(silhouette_only)
		_comparison_viewports[index].render_target_update_mode = SubViewport.UPDATE_ONCE

func _review_image(source: Image) -> Image:
	return Renderer.silhouette_image(source, Color("d9edf2")) if silhouette_only else source.duplicate()

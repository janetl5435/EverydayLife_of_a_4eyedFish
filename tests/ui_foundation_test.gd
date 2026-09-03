extends Node

const BACKDROP_SCENE_PATH: String = "res://scenes/ui/components/sea_backdrop.tscn"
const ACHIEVEMENT_CARD_SCENE_PATH: String = "res://scenes/ui/achievement_card.tscn"
const THEME_PATH: String = "res://themes/game_ui_theme.tres"

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await _check_sea_backdrop()
	_check_button_theme()
	await _check_achievement_card()
	_finish()


func _check_sea_backdrop() -> void:
	var backdrop_scene: PackedScene = load(BACKDROP_SCENE_PATH) as PackedScene
	_expect_true(backdrop_scene != null, "The shared sea backdrop scene must load.")
	if backdrop_scene == null:
		return
	var swimming_backdrop: SeaBackdrop = backdrop_scene.instantiate() as SeaBackdrop
	_expect_true(swimming_backdrop != null, "The backdrop root must use SeaBackdrop.")
	if swimming_backdrop == null:
		return
	add_child(swimming_backdrop)
	await get_tree().process_frame
	var map_sprite: Sprite2D = swimming_backdrop.get_node(
		"World/MapTrack/MapPrimary"
	) as Sprite2D
	var repeated_map: Sprite2D = swimming_backdrop.get_node(
		"World/MapTrack/MapRepeat"
	) as Sprite2D
	var swimming_fish: PlayerFish = swimming_backdrop.get_node(
		"World/DecorativeFish"
	) as PlayerFish
	_expect_true(map_sprite.texture != null, "The shared backdrop must use the supplied sea map.")
	_expect_true(
		is_equal_approx(map_sprite.scale.x, 0.4),
		"The menu backdrop must preserve the project's 0.4 map display scale."
	)
	_expect_true(
		is_equal_approx(repeated_map.position.x, map_sprite.texture.get_width() * 0.4),
		"The repeated map must begin exactly after the primary map."
	)
	_expect_true(
		not swimming_backdrop.animate_map and not repeated_map.visible,
		"Shared backdrops must remain static unless a screen explicitly enables map motion."
	)
	_expect_true(
		swimming_fish.get_visual_animation_name() == &"swim",
		"The normal decorative fish must use its swimming pose."
	)
	swimming_backdrop.queue_free()
	await get_tree().process_frame
	var dead_backdrop: SeaBackdrop = backdrop_scene.instantiate() as SeaBackdrop
	dead_backdrop.fish_pose = SeaBackdrop.FishPose.DEAD
	add_child(dead_backdrop)
	await get_tree().process_frame
	var dead_fish: PlayerFish = dead_backdrop.get_node("World/DecorativeFish") as PlayerFish
	_expect_true(
		is_equal_approx(dead_fish.rotation, PI),
		"The shared backdrop must support a static belly-up fish pose."
	)
	_expect_true(
		dead_fish.get_visual_animation_name() == &"death",
		"The belly-up decorative fish must request the death visual."
	)
	dead_backdrop.queue_free()
	await get_tree().process_frame


func _check_button_theme() -> void:
	var game_theme: Theme = load(THEME_PATH) as Theme
	_expect_true(game_theme != null, "The shared game UI theme must load.")
	if game_theme == null:
		return
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus"]:
		_expect_true(
			game_theme.has_stylebox(state, &"Button"),
			"The button theme must define the %s state." % String(state)
		)
	var normal_style: StyleBoxTexture = game_theme.get_stylebox(
		&"normal",
		&"Button"
	) as StyleBoxTexture
	var hover_style: StyleBoxTexture = game_theme.get_stylebox(
		&"hover",
		&"Button"
	) as StyleBoxTexture
	_expect_true(
		normal_style != null and hover_style != null,
		"Normal and highlighted buttons must use the supplied texture atlas."
	)
	if normal_style != null and hover_style != null:
		_expect_true(
			normal_style.texture != hover_style.texture,
			"Hover/focus must visibly differ from the normal button state."
		)


func _check_achievement_card() -> void:
	var card_scene: PackedScene = load(ACHIEVEMENT_CARD_SCENE_PATH) as PackedScene
	_expect_true(card_scene != null, "The supplied achievement card scene must load.")
	if card_scene == null:
		return
	var definitions: Array[AchievementDefinition] = AchievementService.get_definitions()
	_expect_true(not definitions.is_empty(), "Achievement definitions must be available.")
	if definitions.is_empty():
		return
	var card: AchievementCard = card_scene.instantiate() as AchievementCard
	add_child(card)
	await get_tree().process_frame
	card.configure(definitions[0], false)
	_expect_true(
		card.title_label.text == definitions[0].display_name,
		"The card must display the planned achievement name."
	)
	_expect_true(
		card.condition_label.text == definitions[0].condition_text,
		"The card must display the planned achievement condition."
	)
	_expect_true(
		card.icon_rect.texture == definitions[0].icon,
		"The card must display the supplied achievement icon."
	)
	_expect_true(
		card.get_node_or_null("%StatusLabel") == null,
		"Achievement cards must not display unlock-status text."
	)
	var icon_material: ShaderMaterial = card.icon_rect.material as ShaderMaterial
	_expect_true(
		icon_material != null
		and is_zero_approx(float(icon_material.get_shader_parameter(&"saturation"))),
		"A locked achievement icon must be rendered without color."
	)
	card.queue_free()
	await get_tree().process_frame


func _expect_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("UI_FOUNDATION_TEST_OK")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	get_tree().quit(1)

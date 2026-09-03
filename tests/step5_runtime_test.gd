extends Node

const GAMEPLAY_SCENE_PATH: String = "res://scenes/gameplay/gameplay_root.tscn"

var _failures: Array[String] = []
var _wetting_accept_count: int = 0
var _interaction_attempt_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await _check_food_data_contract()
	await _check_benthic_food_placement()
	await _check_surface_shrimp_interaction()
	await _check_wetting_and_depth_state()
	await _check_underwater_interaction_and_independence()
	await _check_jump_contact_and_failure_stop()
	_finish()


func _check_benthic_food_placement() -> void:
	var gameplay: GameplayRoot = await _create_forage_gameplay()
	if gameplay == null:
		return
	var director: OpportunityDirector = gameplay.get_node("ModeHost/ForageModeController/OpportunityDirector") as OpportunityDirector
	var region_6_y: float = gameplay.region_layout.get_region_center_y(6)
	var region_8_y: float = gameplay.region_layout.get_region_center_y(8)
	for food_id: StringName in [&"algae", &"shellfish"]:
		var food: ForageFood = director.spawn_independent_food(
			food_id,
			8999,
			Vector2(400.0, region_6_y)
		)
		_expect_true(food != null, "%s must spawn for the benthic-placement test." % food_id)
		if food != null:
			_expect_float(food.global_position.y, region_8_y, "%s must be anchored to global region 8." % food_id)
	gameplay.queue_free()
	await get_tree().process_frame


func _check_surface_shrimp_interaction() -> void:
	var gameplay: GameplayRoot = await _create_forage_gameplay()
	if gameplay == null:
		return
	var forage: ForageModeController = gameplay.get_node("ModeHost/ForageModeController") as ForageModeController
	var director: OpportunityDirector = gameplay.get_node("ModeHost/ForageModeController/OpportunityDirector") as OpportunityDirector
	var region_controller: RegionController = gameplay.get_node("Systems/RegionController") as RegionController
	var player: PlayerFish = gameplay.get_node("World/ActorRoot/PlayerFish") as PlayerFish
	forage.interaction_attempted.connect(_on_interaction_attempted)
	await _press_region_action(&"move_down")
	_expect_equal(region_controller.get_current_region(), 6, "The surface shrimp test must reach surface region 6.")
	var shrimp: ForageFood = director.spawn_independent_food(
		&"shrimp",
		9001,
		player.get_mouth_world_position()
	)
	_expect_true(shrimp != null and shrimp.is_available(), "A surface-region shrimp must be available for the test.")
	var interact_event: InputEventAction = InputEventAction.new()
	interact_event.action = &"interact"
	interact_event.pressed = true
	_expect_true(
		forage.handle_unhandled_input(interact_event),
		"The forage controller must consume every F input."
	)
	_expect_equal(_interaction_attempt_count, 1, "The first F press must emit one bite attempt.")
	_expect_equal(forage.get_energy(), 28, "Eating a surface shrimp must add eight energy.")
	_expect_true(player.get_visual_animation_name() == &"eat", "Eating a surface shrimp with F must play eat.")
	_expect_true(
		forage.handle_unhandled_input(interact_event),
		"An F press without a food target must still be consumed."
	)
	_expect_equal(_interaction_attempt_count, 2, "An empty F press must still emit the bite attempt.")
	_expect_equal(forage.get_energy(), 28, "An empty F bite must award no energy.")
	_expect_true(player.get_visual_animation_name() == &"eat", "An empty surface F press must still play eat.")
	_expect_true(
		forage.get_interaction_depth_lock_remaining() > 0.0,
		"A successful surface interaction must start the 0.2-second depth lock."
	)
	_expect_true(not forage.request_depth_switch(), "The immediate post-eat depth switch must be blocked.")
	await get_tree().create_timer(forage.interaction_depth_lock_duration + 0.05).timeout
	_expect_true(forage.request_depth_switch(), "Depth switching must become available after the short eat lock.")
	await get_tree().create_timer(0.1).timeout
	_expect_equal(forage.get_state(), ForageModeController.State.DEEP_FORAGE, "The delayed switch must complete normally.")
	gameplay.queue_free()
	await get_tree().process_frame


func _check_food_data_contract() -> void:
	var expected: Array[Dictionary] = [
		{"path": "res://data/foods/insect.tres", "id": &"insect", "energy": 10, "region": 4, "method": FoodDefinition.CollectionMethod.CONTACT, "retained": false},
		{"path": "res://data/foods/algae.tres", "id": &"algae", "energy": 3, "region": 8, "method": FoodDefinition.CollectionMethod.INTERACT, "retained": true},
		{"path": "res://data/foods/shellfish.tres", "id": &"shellfish", "energy": 7, "region": 8, "method": FoodDefinition.CollectionMethod.INTERACT, "retained": true},
		{"path": "res://data/foods/shrimp.tres", "id": &"shrimp", "energy": 8, "region": 7, "method": FoodDefinition.CollectionMethod.INTERACT, "retained": false},
	]
	for entry: Dictionary in expected:
		var definition: FoodDefinition = load(entry.path) as FoodDefinition
		_expect_true(definition != null and definition.is_valid(), "Every Step 5 food definition must load and validate: %s" % entry.path)
		if definition == null:
			continue
		_expect_true(definition.food_id == entry.id, "Food ID mismatch for %s." % entry.path)
		_expect_equal(definition.energy_value, entry.energy, "Energy mismatch for %s." % entry.path)
		_expect_equal(definition.spawn_region, entry.region, "Spawn region mismatch for %s." % entry.path)
		_expect_equal(definition.collection_method, entry.method, "Collection method mismatch for %s." % entry.path)
		var food: ForageFood = definition.scene.instantiate() as ForageFood
		_expect_true(food != null, "Every food scene root must be ForageFood: %s" % entry.path)
		if food == null:
			continue
		add_child(food)
		await get_tree().process_frame
		var animated_visual: AnimatedSprite2D = food.get_node("AnimatedVisual") as AnimatedSprite2D
		_expect_true(animated_visual != null, "Every food needs an AnimatedSprite2D replacement slot.")
		if animated_visual != null:
			for animation_name: StringName in [&"idle", &"collected", &"retire"]:
				_expect_true(animated_visual.sprite_frames.has_animation(animation_name), "Food animation slot missing: %s" % animation_name)
		_expect_true(
			food.is_retained_after_collection() == bool(entry.retained),
			"Food retained-after-collection rule mismatch for %s." % entry.path
		)
		food.queue_free()
		await get_tree().process_frame


func _check_wetting_and_depth_state() -> void:
	var gameplay: GameplayRoot = await _create_forage_gameplay()
	if gameplay == null:
		return
	var region_controller: RegionController = gameplay.get_node("Systems/RegionController") as RegionController
	var wet_eye: WetEyeController = gameplay.get_node("Systems/WetEyeController") as WetEyeController
	var forage: ForageModeController = gameplay.get_node("ModeHost/ForageModeController") as ForageModeController
	wet_eye.set_process(false)
	wet_eye.dive_accepted.connect(_on_wetting_accepted)
	wet_eye.advance_time(2.0)
	var before_wrong_rise: float = wet_eye.get_remaining_time()
	await _press_region_action(&"move_up")
	_expect_float(wet_eye.get_remaining_time(), before_wrong_rise, "W/Up in surface region 5 must not wet the eyes.")
	_expect_equal(_wetting_accept_count, 0, "Wrong-direction W/Up must emit no wetting acceptance.")
	_expect_equal(forage.get_state(), ForageModeController.State.SURFACE_FORAGE, "Wrong-direction W/Up must keep SurfaceForage.")
	await _press_region_action(&"move_down")
	_expect_equal(region_controller.get_current_region(), 6, "S/Down from region 5 must enter region 6.")
	_expect_equal(_wetting_accept_count, 1, "Starting the 5-to-6 move must wet the eyes exactly once.")
	_expect_float(wet_eye.get_remaining_time(), wet_eye.get_maximum_time(), "The 5-to-6 movement start must refill the wet-eye timer.")
	await _press_region_action(&"move_down")
	_expect_equal(forage.get_state(), ForageModeController.State.DEEP_FORAGE, "The second S/Down at surface region 6 must enter DeepForage.")
	_expect_equal(_wetting_accept_count, 1, "The view transition after 5-to-6 must not wet the eyes a second time.")
	_expect_equal(region_controller.get_min_region(), 5, "Deep forage must keep the player out of sky region 4.")
	_expect_equal(region_controller.get_max_region(), 8, "Deep forage must keep the player out of soil region 9.")
	await _press_region_action(&"move_up")
	await _press_region_action(&"move_down")
	_expect_equal(_wetting_accept_count, 1, "A deep-state 5-to-6 move must not count as wetting.")
	gameplay.queue_free()
	await get_tree().process_frame


func _check_underwater_interaction_and_independence() -> void:
	var gameplay: GameplayRoot = await _create_forage_gameplay()
	if gameplay == null:
		return
	var forage: ForageModeController = gameplay.get_node("ModeHost/ForageModeController") as ForageModeController
	var director: OpportunityDirector = gameplay.get_node("ModeHost/ForageModeController/OpportunityDirector") as OpportunityDirector
	var region_controller: RegionController = gameplay.get_node("Systems/RegionController") as RegionController
	var player: PlayerFish = gameplay.get_node("World/ActorRoot/PlayerFish") as PlayerFish
	_expect_true(director.force_spawn_pair(&"algae"), "The test should spawn an insect/algae opportunity pair.")
	var air_food: ForageFood = director.get_current_air_food()
	var underwater_food: ForageFood = director.get_current_underwater_food()
	_expect_true(air_food != null and underwater_food != null, "An opportunity must create both water-surface and underwater choices.")
	if underwater_food != null:
		underwater_food.global_position = player.get_mouth_world_position()
		_expect_true(not forage.request_interaction(), "Surface forage must never collect underwater food, even at the mouth anchor.")
		_expect_true(underwater_food.is_available(), "A surface F press must leave underwater food available.")
		_expect_true(player.get_visual_animation_name() == &"eat", "Surface F must play eat without collecting underwater food.")
	await _press_region_action(&"move_down")
	await _press_region_action(&"move_down")
	await _press_region_action(&"move_down")
	await _press_region_action(&"move_down")
	_expect_equal(region_controller.get_current_region(), 8, "Deep forage should reach benthic region 8.")
	if air_food != null and underwater_food != null:
		underwater_food.global_position = player.global_position + Vector2(-240.0, 0.0)
		_expect_true(not forage.request_interaction(), "The fish body center must not collect food while the mouth anchor is outside its collision shape.")
		_expect_equal(forage.get_energy(), 20, "An eat animation without mouth contact must award no energy.")
		_expect_true(underwater_food.is_available(), "Food must remain available after an F press without mouth contact.")
		_expect_true(player.get_visual_animation_name() == &"eat", "Deep-forage F must play eat even when no food is collected.")
		await get_tree().create_timer(0.75).timeout
		_expect_true(player.get_visual_animation_name() == &"swim", "An unsuccessful eat animation must return to swim.")
		underwater_food.global_position = player.get_mouth_world_position()
		_expect_true(underwater_food.contains_world_point(player.get_mouth_world_position()), "The mouth anchor should now be inside the algae CollisionShape2D.")
		_expect_true(forage.request_interaction(), "F interaction should collect food when the mouth anchor enters its collision shape.")
		_expect_equal(forage.get_energy(), 23, "Collecting algae should add three run-energy points.")
		_expect_true(player.get_visual_animation_name() == &"eat", "Collecting algae with F must play the fish eat animation.")
		_expect_true(air_food.is_available(), "Collecting algae must leave the surface insect independently available.")
		var insect_visual: AnimatedSprite2D = air_food.get_node("AnimatedVisual") as AnimatedSprite2D
		_expect_true(insect_visual.visible, "The independent insect must keep its normal animated visual.")
		_expect_true(air_food.get_state() == ForageFood.State.AVAILABLE, "The independent insect must not enter the retiring placeholder state.")
		await get_tree().create_timer(0.75).timeout
		_expect_true(player.get_visual_animation_name() == &"swim", "The eat animation must return to swim after it finishes.")
		_expect_true(is_instance_valid(underwater_food), "Collected algae must remain present in retire.")
		if is_instance_valid(underwater_food):
			var algae_visual: AnimatedSprite2D = underwater_food.get_node("AnimatedVisual") as AnimatedSprite2D
			_expect_equal(underwater_food.get_state(), ForageFood.State.RETIRING, "Collected algae must enter the retained retire state.")
			_expect_true(algae_visual.animation == &"retire", "Collected algae must hold the retire animation state.")
	await _check_additional_underwater_eat_animation(
		forage,
		director,
		player,
		&"shellfish",
		30,
		true
	)
	await _press_region_action(&"move_up")
	_expect_equal(region_controller.get_current_region(), 7, "Deep forage should reach the shrimp region.")
	await _check_additional_underwater_eat_animation(
		forage,
		director,
		player,
		&"shrimp",
		38,
		false
	)
	gameplay.queue_free()
	await get_tree().process_frame


func _check_additional_underwater_eat_animation(
	forage: ForageModeController,
	director: OpportunityDirector,
	player: PlayerFish,
	food_id: StringName,
	expected_energy: int,
	expect_retained: bool
) -> void:
	_expect_true(director.force_spawn_pair(food_id), "The test should spawn underwater food: %s." % food_id)
	var underwater_food: ForageFood = director.get_current_underwater_food()
	_expect_true(underwater_food != null, "The underwater food should exist: %s." % food_id)
	if underwater_food == null:
		return
	underwater_food.global_position = player.get_mouth_world_position()
	_expect_true(
		underwater_food.contains_world_point(player.get_mouth_world_position()),
		"The mouth anchor should overlap the CollisionShape2D for %s." % food_id
	)
	var animated_visual: AnimatedSprite2D = underwater_food.get_node("AnimatedVisual") as AnimatedSprite2D
	_expect_true(animated_visual.animation == &"idle", "%s must remain idle before it is eaten." % food_id)
	_expect_true(forage.request_interaction(), "F interaction should collect underwater food: %s." % food_id)
	_expect_equal(forage.get_energy(), expected_energy, "Unexpected energy after collecting %s." % food_id)
	_expect_true(player.get_visual_animation_name() == &"eat", "Collecting %s with F must play the fish eat animation." % food_id)
	if animated_visual.sprite_frames.get_frame_count(&"collected") > 0:
		_expect_true(animated_visual.animation == &"collected", "%s must play collected when eaten." % food_id)
	await get_tree().create_timer(0.75).timeout
	_expect_true(player.get_visual_animation_name() == &"swim", "The eat animation for %s must return to swim." % food_id)
	if expect_retained:
		_expect_true(is_instance_valid(underwater_food), "Collected shellfish must remain present after collected finishes.")
		if is_instance_valid(underwater_food):
			_expect_equal(underwater_food.get_state(), ForageFood.State.RETIRING, "Shellfish must enter the retained retire state.")
			_expect_true(animated_visual.animation == &"retire", "Shellfish must hold the retire visual after collected finishes.")
			await get_tree().create_timer(0.2).timeout
			_expect_true(animated_visual.animation == &"retire", "Shellfish must continue holding retire until it leaves the scene.")
	else:
		_expect_true(not is_instance_valid(underwater_food), "%s must disappear after being eaten." % food_id)


func _check_jump_contact_and_failure_stop() -> void:
	var gameplay: GameplayRoot = await _create_forage_gameplay()
	if gameplay == null:
		return
	var forage: ForageModeController = gameplay.get_node("ModeHost/ForageModeController") as ForageModeController
	var director: OpportunityDirector = gameplay.get_node("ModeHost/ForageModeController/OpportunityDirector") as OpportunityDirector
	var player: PlayerFish = gameplay.get_node("World/ActorRoot/PlayerFish") as PlayerFish
	var region_controller: RegionController = gameplay.get_node("Systems/RegionController") as RegionController
	_expect_true(director.force_spawn_pair(&"shellfish"), "The jump test should spawn a paired insect.")
	var insect: ForageFood = director.get_current_air_food()
	_expect_true(insect != null, "The air half of every opportunity must be an insect.")
	var start_position: Vector2 = player.global_position
	if insect != null:
		insect.global_position = start_position + Vector2(125.0, -78.0)
	_expect_true(forage.begin_jump_charge(), "Jump charging should start only from surface-forage region 5.")
	_expect_true(not forage.request_interaction(), "F must not start eating during jump charge.")
	_expect_true(player.get_visual_animation_name() == &"jump_charge", "F during jump charge must preserve jump_charge.")
	_expect_true(not forage.set_jump_target(start_position + Vector2(-100.0, -200.0)), "A leftward jump target must be rejected.")
	_expect_true(not forage.set_jump_target(start_position + Vector2(300.0, -10.0)), "A direction too shallow to cross the surface must be rejected.")
	_expect_true(forage.set_jump_target(start_position + Vector2(300.0, -300.0)), "A right-and-up jump target must be accepted.")
	_expect_true(forage.release_jump_charge(), "Releasing a valid fixed-strength jump must launch the fish.")
	_expect_true(not forage.request_interaction(), "F must not start eating while the fish is airborne.")
	_expect_true(player.get_visual_animation_name() == &"jump_airborne", "F while airborne must preserve jump_airborne.")
	var normal_airborne_x_speed: float = player.velocity.x
	Input.action_press(&"accelerate")
	await get_tree().physics_frame
	await get_tree().process_frame
	_expect_true(player.is_speed_boost_active(), "Shift acceleration must remain available during an airborne forage jump.")
	_expect_float(
		player.velocity.x,
		normal_airborne_x_speed + gameplay.world_config.forward_speed * (gameplay.world_config.speed_boost_multiplier - 1.0),
		"Airborne acceleration should boost the continuous forward component without changing jump force."
	)
	Input.action_release(&"accelerate")
	var minimum_y: float = player.global_position.y
	for _frame: int in range(180):
		await get_tree().physics_frame
		minimum_y = minf(minimum_y, player.global_position.y)
		if not player.is_jump_active():
			break
	_expect_true(minimum_y < gameplay.region_layout.get_water_surface_y(), "The jump trajectory must cross above the water surface.")
	_expect_true(not player.is_jump_active(), "The fixed-strength jump must eventually land.")
	_expect_equal(region_controller.get_current_region(), 5, "Jump landing must restore surface-forage region 5.")
	_expect_true(player.is_fully_inside_current_region(), "After landing, the fish must return fully inside region 5.")
	_expect_true(player.is_region_input_enabled(), "Lane input must be restored after landing.")
	_expect_equal(forage.get_energy(), 30, "Touching the airborne insect should add ten energy to the initial twenty.")
	_expect_true(not is_instance_valid(insect), "Insect must disappear after being eaten.")
	_expect_true(gameplay.begin_failure(AppFlow.FAILURE_DEBUG), "The test failure should enter the unified failure flow.")
	await get_tree().process_frame
	_expect_true(not director.is_running(), "Failure must stop future opportunity generation.")
	_expect_equal(forage.get_state(), ForageModeController.State.FINISHED, "Failure must finish the forage state machine.")
	_expect_true(not player.is_region_input_enabled(), "Failure must leave player input disabled.")
	gameplay.queue_free()
	await get_tree().process_frame


func _create_forage_gameplay() -> GameplayRoot:
	AppFlow.current_mode = AppFlow.GameMode.FORAGE
	var gameplay_scene: PackedScene = load(GAMEPLAY_SCENE_PATH) as PackedScene
	if gameplay_scene == null:
		_fail("Could not load GameplayRoot for Step 5.")
		return null
	var gameplay: GameplayRoot = gameplay_scene.instantiate() as GameplayRoot
	var test_config: WorldConfig = gameplay.world_config.duplicate() as WorldConfig
	test_config.camera_vertical_transition_duration = 0.05
	test_config.death_animation_duration = 5.0
	test_config.normal_energy_drain_per_second = 0.0
	test_config.boosted_energy_drain_per_second = 0.0
	gameplay.world_config = test_config
	var director: OpportunityDirector = gameplay.get_node("ModeHost/ForageModeController/OpportunityDirector") as OpportunityDirector
	director.first_opportunity_distance = 100000.0
	var ecology: EcologyEventDirector = gameplay.get_node("ModeHost/EcologyEventDirector") as EcologyEventDirector
	ecology.set_automatic_spawning_enabled(false)
	add_child(gameplay)
	await get_tree().process_frame
	return gameplay


func _press_region_action(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().create_timer(0.15).timeout


func _on_wetting_accepted() -> void:
	_wetting_accept_count += 1


func _on_interaction_attempted() -> void:
	_interaction_attempt_count += 1


func _expect_equal(actual: int, expected: int, message: String) -> void:
	if actual != expected:
		_fail("%s Expected %d, received %d." % [message, expected, actual])


func _expect_float(actual: float, expected: float, message: String) -> void:
	if not is_equal_approx(actual, expected):
		_fail("%s Expected %.3f, received %.3f." % [message, expected, actual])


func _expect_true(actual: bool, message: String) -> void:
	if not actual:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("STEP5_RUNTIME_TEST_OK")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	get_tree().quit(1)

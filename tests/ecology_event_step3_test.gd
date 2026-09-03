extends Node

const GAMEPLAY_SCENE_PATH: String = "res://scenes/gameplay/gameplay_root.tscn"

var _failures: Array[String] = []
var _bird_evade_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var gameplay: GameplayRoot = await _create_gameplay()
	if gameplay == null:
		_finish()
		return
	var ecology: EcologyEventDirector = gameplay.get_node("ModeHost/EcologyEventDirector") as EcologyEventDirector
	var foods: OpportunityDirector = gameplay.get_node("ModeHost/ForageModeController/OpportunityDirector") as OpportunityDirector
	var player: PlayerFish = gameplay.get_node("World/ActorRoot/PlayerFish") as PlayerFish
	var camera: Camera2D = gameplay.get_node("World/CameraRig/Camera2D") as Camera2D
	ecology.bird_evaded.connect(_on_bird_evaded)
	_check_event_data(ecology)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect_int_array(ecology.get_started_event_ids(), [4], "The opening ecology event must always be event 4.")
	_expect_equal(ecology.get_active_threat_count(), 1, "Event 4 must begin with one predator fish.")
	_expect_equal(ecology.get_active_food_count(), 3, "Event 4 must begin with one insect, one algae and one shellfish.")
	_check_visible_caps(ecology)
	_check_food_independence(foods)
	await _advance_to_next_event(gameplay, ecology, ecology.event_4_length)
	_expect_int_array(ecology.get_started_event_ids(), [4, 1], "Event 1 must follow the fixed opening event.")
	await _check_bird_rules(ecology, player, camera)
	await _advance_to_next_event(gameplay, ecology, ecology.event_1_length)
	_expect_int_array(ecology.get_started_event_ids(), [4, 1, 2], "Event 2 must follow event 1.")
	await _advance_to_next_event(gameplay, ecology, ecology.event_2_length)
	_expect_int_array(ecology.get_started_event_ids(), [4, 1, 2, 3], "Event 3 must follow event 2.")
	var started_before_finish_buffer: Array[int] = ecology.get_started_event_ids()
	await _clear_active_entities(gameplay)
	player.global_position.x = 410.0 + gameplay.world_config.run_finish_distance - ecology.safe_finish_buffer + 1.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect_equal(ecology.get_active_threat_count(), 0, "The last 400 px must release every attack-capable predator.")
	_expect_int_array(
		ecology.get_started_event_ids(),
		started_before_finish_buffer,
		"No ecology event may be generated inside the final 800 px."
	)
	gameplay.queue_free()
	await get_tree().process_frame
	_finish()


func _check_event_data(ecology: EcologyEventDirector) -> void:
	_expect_float(ecology.warning_duration, 1.0, "Predator warning duration must remain one second.")
	_expect_float(ecology.bird_forward_vision_distance, 300.0, "Bird forward vision must begin at 300 px.")
	_expect_equal(ecology.maximum_visible_threats, 3, "The visible predator cap must be three.")
	_expect_equal(ecology.maximum_visible_foods, 4, "The visible food target must be four.")
	for event_id: int in range(1, 5):
		var length: float = ecology.get_event_length(event_id)
		_expect_true(length >= 1800.0 and length <= 2200.0, "Every ecology event length must stay in the 1800-2200 px tuning range.")
	_expect_equal(ecology.get_event_total_threat_count(1), 3, "Event 1 must contain one bird and two predator fish.")
	_expect_equal(ecology.get_event_bird_count(1), 1, "Event 1 must contain one bird.")
	_expect_equal(ecology.get_event_food_type_count(1, &"insect"), 2, "Event 1 must contain two insects.")
	_expect_equal(ecology.get_event_food_type_count(1, &"algae"), 2, "Event 1 must contain two algae.")
	_expect_equal(ecology.get_event_food_type_count(1, &"shellfish"), 2, "Event 1 must contain two shellfish.")
	_expect_equal(ecology.get_event_food_type_count(1, &"shrimp"), 2, "Event 1 must contain two shrimp.")
	_expect_equal(ecology.get_event_total_threat_count(2), 3, "Event 2 must contain one bird and two predator fish.")
	_expect_equal(ecology.get_event_food_type_count(2, &"shrimp"), 4, "Event 2 must contain four shrimp.")
	_expect_equal(ecology.get_event_total_food_count(2), 8, "Event 2 must contain all specified surface and underwater food.")
	_expect_equal(ecology.get_event_total_threat_count(3), 2, "Event 3 must contain two predator fish.")
	_expect_equal(ecology.get_event_bird_count(3), 0, "Event 3 must contain no bird.")
	_expect_equal(ecology.get_event_food_type_count(3, &"shrimp"), 3, "Event 3 must contain three shrimp.")
	_expect_equal(ecology.get_event_food_type_count(3, &"algae"), 2, "Event 3 must contain two algae.")
	_expect_equal(ecology.get_event_food_type_count(3, &"shellfish"), 2, "Event 3 must contain two shellfish.")
	_expect_equal(ecology.get_event_total_threat_count(4), 1, "Event 4 must contain one predator fish.")
	_expect_equal(ecology.get_event_total_food_count(4), 3, "Event 4 must contain three independent food entities.")


func _check_food_independence(food_service: OpportunityDirector) -> void:
	var algae: ForageFood
	var insect: ForageFood
	for food: ForageFood in food_service.get_active_foods():
		if food.get_food_id() == &"algae":
			algae = food
		elif food.get_food_id() == &"insect":
			insect = food
	_expect_true(algae != null and insect != null, "Event 4 must expose algae and insect as separate entities.")
	if algae == null or insect == null:
		return
	_expect_true(algae.collect(), "The test algae must be collectable.")
	_expect_true(insect.is_available(), "Eating algae must not retire the surface insect.")
	var insect_visual: AnimatedSprite2D = insect.get_node("AnimatedVisual") as AnimatedSprite2D
	var insect_placeholder: Node2D = insect.get_node("PlaceholderVisual") as Node2D
	_expect_true(insect_visual.visible, "The unaffected insect must keep its spritesheet visible.")
	_expect_true(not insect_placeholder.visible, "The unaffected insect must not reveal its placement placeholder.")


func _check_bird_rules(
	ecology: EcologyEventDirector,
	player: PlayerFish,
	camera: Camera2D
) -> void:
	var bird: PatrolThreat
	for threat: PatrolThreat in ecology.get_active_threats():
		if threat.get_animal_type() == ThreatEntry.AnimalType.BIRD:
			bird = threat
			break
	_expect_true(bird != null, "Event 1 must activate its bird in the first batch.")
	if bird == null:
		return
	camera.global_position.x = player.global_position.x
	_expect_float(bird.get_forward_vision_distance(), 300.0, "The event bird must receive the configured 300 px view length.")
	bird.global_position.x = player.global_position.x + 250.0
	await get_tree().physics_frame
	_expect_true(ecology.is_alert_active(), "A surface player inside the bird's forward 300 px must trigger alert.")
	_expect_true(
		AudioService.is_warning_loop_requested(),
		"A bird that actually sees the player must request the predator warning sound."
	)
	if DisplayServer.get_name() != "headless":
		_expect_true(
			AudioService.is_warning_loop_playing(),
			"The predator warning player must run while a bird sees the player."
		)
	bird.global_position.x = player.global_position.x + 520.0
	await get_tree().physics_frame
	_expect_true(not ecology.is_alert_active(), "A player beyond the bird's forward 300 px must leave alert.")
	_expect_true(
		not AudioService.is_warning_loop_requested(),
		"Leaving every predator view must stop the predator warning sound."
	)
	_expect_equal(_bird_evade_count, 1, "Leaving a bird that actually saw the player must emit one successful evasion.")
	bird.global_position.x = player.global_position.x + 250.0
	await get_tree().physics_frame
	_expect_true(ecology.is_alert_active(), "The bird must be able to lock the surface player again.")
	bird.global_position.x = player.global_position.x - 100.0
	await get_tree().physics_frame
	_expect_equal(_bird_evade_count, 1, "A bird merely flying past the player must not count as an active evasion.")
	ecology.set_player_view_profile(RegionLayout.ViewProfile.FORAGE_DEEP)
	var evade_count_before_underwater_wait: int = _bird_evade_count
	bird.global_position.x = player.global_position.x + 230.0
	var bird_x_before: float = bird.global_position.x
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect_true(not ecology.is_alert_active(), "A bird must not threaten the player in the underwater view.")
	_expect_true(not is_equal_approx(bird.global_position.x, bird_x_before), "The bird must keep flying naturally while the player is underwater.")
	_expect_equal(
		_bird_evade_count,
		evade_count_before_underwater_wait,
		"Waiting underwater without a new bird lock must not count as an evasion."
	)
	ecology.set_player_view_profile(RegionLayout.ViewProfile.FORAGE_SURFACE)


func _advance_to_next_event(
	gameplay: GameplayRoot,
	ecology: EcologyEventDirector,
	event_length: float
) -> void:
	var player: PlayerFish = gameplay.get_node("World/ActorRoot/PlayerFish") as PlayerFish
	var expected_started_count: int = ecology.get_started_event_ids().size() + 1
	player.global_position.x += event_length + 1.0
	for _attempt: int in range(6):
		await _clear_active_entities(gameplay)
		await get_tree().physics_frame
		_check_visible_caps(ecology)
		if ecology.get_started_event_ids().size() >= expected_started_count:
			return
	_fail("The ecology scheduler did not advance after all due batches received capacity.")


func _clear_active_entities(gameplay: GameplayRoot) -> void:
	var pool: ThreatPool = gameplay.get_node("World/ActorRoot/Animals/ThreatPool") as ThreatPool
	var foods: OpportunityDirector = gameplay.get_node("ModeHost/ForageModeController/OpportunityDirector") as OpportunityDirector
	pool.release_all()
	for food: ForageFood in foods.get_active_foods():
		if is_instance_valid(food):
			food.stop_and_free()
	await get_tree().process_frame


func _check_visible_caps(ecology: EcologyEventDirector) -> void:
	_expect_true(
		ecology.get_active_threat_count() <= ecology.maximum_visible_threats,
		"Ecology batches must never exceed the three-predator visible cap."
	)
	_expect_true(
		ecology.get_active_food_count() <= ecology.maximum_visible_foods,
		"Ecology batches must never exceed the four-food visible target."
	)


func _create_gameplay() -> GameplayRoot:
	AppFlow.current_mode = AppFlow.GameMode.FORAGE
	var packed: PackedScene = load(GAMEPLAY_SCENE_PATH) as PackedScene
	if packed == null:
		_fail("Could not load GameplayRoot for the ecology-event Step 3 test.")
		return null
	var gameplay: GameplayRoot = packed.instantiate() as GameplayRoot
	var config: WorldConfig = gameplay.world_config.duplicate() as WorldConfig
	config.run_finish_distance = 10000.0
	config.wet_eye_duration = 120.0
	config.normal_energy_drain_per_second = 0.0
	config.boosted_energy_drain_per_second = 0.0
	config.death_animation_duration = 5.0
	gameplay.world_config = config
	gameplay.route_scenes_after_settlement = false
	var ecology: EcologyEventDirector = gameplay.get_node("ModeHost/EcologyEventDirector") as EcologyEventDirector
	ecology.first_event_distance = 0.0
	add_child(gameplay)
	await get_tree().process_frame
	return gameplay


func _on_bird_evaded(_event_id: int) -> void:
	_bird_evade_count += 1


func _expect_equal(actual: int, expected: int, message: String) -> void:
	if actual != expected:
		_fail("%s Expected %d, received %d." % [message, expected, actual])


func _expect_float(actual: float, expected: float, message: String) -> void:
	if not is_equal_approx(actual, expected):
		_fail("%s Expected %.3f, received %.3f." % [message, expected, actual])


func _expect_int_array(actual: Array[int], expected: Array[int], message: String) -> void:
	if actual != expected:
		_fail("%s Expected %s, received %s." % [message, expected, actual])


func _expect_true(actual: bool, message: String) -> void:
	if not actual:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("ECOLOGY_EVENT_STEP3_TEST_OK")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	get_tree().quit(1)

extends Node

const GAMEPLAY_SCENE_PATH: String = "res://scenes/gameplay/gameplay_root.tscn"
const PATTERN_PATHS: Array[String] = [
	"res://data/encounters/bird_fish_mid.tres",
	"res://data/encounters/bird_two_fish.tres",
	"res://data/encounters/two_fish_deep.tres",
	"res://data/encounters/single_bird.tres",
	"res://data/encounters/single_fish_mid.tres",
	"res://data/encounters/single_fish_deep.tres",
]

var _failures: Array[String] = []
var _failure_reasons: Array[StringName] = []
var _predator_bite_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_pattern_data_and_safe_routes()
	await _check_animation_state_contract()
	await _check_forward_vision_alert_boundaries()
	await _check_patrol_escape_and_pool_recycling()
	await _check_three_threat_limit()
	await _check_distance_scheduling()
	await _check_forage_uses_unified_ecology_threats()
	await _check_repeated_alert_and_one_second_capture_flow()
	_finish()


func _check_pattern_data_and_safe_routes() -> void:
	var found_bird_and_fish: bool = false
	var found_bird_and_two_fish: bool = false
	var found_two_fish: bool = false
	var found_single_bird: bool = false
	var found_single_mid_fish: bool = false
	var found_single_deep_fish: bool = false
	for path: String in PATTERN_PATHS:
		var pattern: EncounterPattern = load(path) as EncounterPattern
		_expect_true(pattern != null, "Could not load encounter pattern: %s" % path)
		if pattern == null:
			continue
		_expect_true(pattern.is_valid(), "Encounter pattern should be structurally valid: %s" % path)
		_expect_float(pattern.warning_duration, 1.0, "Every predator must attack after one continuous second of sight.")
		_expect_true(pattern.threat_entries.size() <= 3, "A pattern must never contain more than three threats.")
		_expect_true(
			SafeRouteValidator.is_pattern_fair_for_threatened_starts(pattern, 5, 7, 0.1, 3),
			"Every threatened start lane needs a complete route with at most three moves: %s" % path
		)
		_expect_true(
			SafeRouteValidator.is_declared_minimum_route_valid(pattern, 5, 7, 0.1, 3),
			"The documented minimum route must end safely before the warning expires: %s" % path
		)
		var bird_count: int = 0
		var fish_count: int = 0
		for entry: ThreatEntry in pattern.threat_entries:
			if entry.animal_type == ThreatEntry.AnimalType.BIRD:
				bird_count += 1
				_expect_equal(entry.world_region, 3, "Birds must fly in global region 3.")
				_expect_equal(entry.get_danger_region(), 5, "Bird sight should threaten the surface water lane, region 5.")
			else:
				fish_count += 1
				_expect_true(entry.world_region >= 5 and entry.world_region <= 7, "Predator fish must remain in patrol lanes 5–7.")
		if bird_count == 1 and fish_count == 1:
			found_bird_and_fish = true
		elif bird_count == 1 and fish_count == 2:
			found_bird_and_two_fish = true
		elif bird_count == 0 and fish_count == 2:
			found_two_fish = true
		elif bird_count == 1 and fish_count == 0:
			found_single_bird = true
		elif bird_count == 0 and fish_count == 1:
			var single_fish_region: int = pattern.threat_entries[0].world_region
			if single_fish_region == 6:
				found_single_mid_fish = true
			elif single_fish_region == 7:
				found_single_deep_fish = true
	_expect_true(found_bird_and_fish, "Missing the one-bird plus one-fish preset type.")
	_expect_true(found_bird_and_two_fish, "Missing the one-bird plus two-fish preset type.")
	_expect_true(found_two_fish, "Missing the two-fish preset type.")
	_expect_true(found_single_bird, "Missing the simple single-bird preset.")
	_expect_true(found_single_mid_fish, "Missing the simple region-6 predator-fish preset.")
	_expect_true(found_single_deep_fish, "Missing the simple region-7 predator-fish preset.")


func _check_animation_state_contract() -> void:
	var player_scene: PackedScene = load("res://scenes/actors/player_fish.tscn") as PackedScene
	_expect_true(player_scene != null, "The player-fish scene must load for animation-slot testing.")
	if player_scene != null:
		var player: PlayerFish = player_scene.instantiate() as PlayerFish
		add_child(player)
		await get_tree().process_frame
		var player_animated_visual: AnimatedSprite2D = player.get_node("Visuals/AnimatedVisual") as AnimatedSprite2D
		_expect_true(player_animated_visual != null, "The four-eyed fish needs an AnimatedSprite2D visual slot.")
		if player_animated_visual != null:
			for player_animation_name: StringName in [
				&"swim", &"rise", &"dive", &"jump_charge", &"jump_airborne", &"eat", &"intro_swim", &"death"
			]:
				_expect_true(
					player_animated_visual.sprite_frames.has_animation(player_animation_name),
					"Missing four-eyed-fish animation slot: %s" % player_animation_name
				)
		player.queue_free()
		await get_tree().process_frame
	var predator_scene: PackedScene = load("res://scenes/actors/predator_fish_threat.tscn") as PackedScene
	_expect_true(predator_scene != null, "The predator-fish scene must load for animation-state testing.")
	if predator_scene == null:
		return
	var threat: PatrolThreat = predator_scene.instantiate() as PatrolThreat
	_expect_true(threat != null, "The predator-fish scene root must remain a PatrolThreat.")
	if threat == null:
		return
	add_child(threat)
	await get_tree().process_frame
	var animated_visual: AnimatedSprite2D = threat.get_node("VisualRoot/AnimatedVisual") as AnimatedSprite2D
	var placeholder_visual: Node2D = threat.get_node("VisualRoot/PlaceholderVisual") as Node2D
	_expect_true(animated_visual != null, "Every patrol predator needs an AnimatedSprite2D visual slot.")
	_expect_true(placeholder_visual != null, "White-box visuals must remain available until animation frames arrive.")
	if animated_visual != null:
		for animation_name: StringName in [&"idle", &"alert", &"chase", &"eat"]:
			_expect_true(
				animated_visual.sprite_frames.has_animation(animation_name),
				"Missing predator animation slot: %s" % animation_name
			)
	var entry: ThreatEntry = ThreatEntry.new()
	entry.animal_type = ThreatEntry.AnimalType.PREDATOR_FISH
	entry.world_region = 6
	entry.direction = -1
	entry.speed = 280.0
	entry.active_time = 2.4
	threat.activate(entry, Vector2.ZERO, null)
	_expect_equal(threat.get_visual_state(), PatrolThreat.VisualState.IDLE, "Activation should begin in idle state.")
	_expect_true(threat.is_player_in_forward_view(-100.0), "A left-moving predator fish must see positions ahead of its eye.")
	_expect_true(not threat.is_player_in_forward_view(0.0), "A left-moving predator fish must not see behind its eye.")
	entry.direction = 1
	threat.activate(entry, Vector2.ZERO, null)
	_expect_true(threat.is_player_in_forward_view(100.0), "A right-moving predator fish must see positions to the right of its eye.")
	_expect_true(not threat.is_player_in_forward_view(0.0), "A right-moving predator fish must not see positions left of its eye.")
	threat.set_warning_active(true)
	_expect_equal(threat.get_visual_state(), PatrolThreat.VisualState.ALERT, "A warning should use the alert state.")
	threat.set_warning_active(false)
	_expect_true(threat.is_encounter_danger_enabled(), "Leaving sight must not permanently disable the same predator.")
	_expect_equal(threat.get_visual_state(), PatrolThreat.VisualState.IDLE, "Leaving sight should return the predator to idle.")
	threat.set_warning_active(true)
	_expect_equal(threat.get_visual_state(), PatrolThreat.VisualState.ALERT, "The same predator must be able to enter alert again.")
	var target: Node2D = Node2D.new()
	target.position = Vector2(60.0, 0.0)
	add_child(target)
	threat.start_attack(target, 0.05, 0.3)
	_expect_equal(threat.get_visual_state(), PatrolThreat.VisualState.CHASING, "Pursuit should use the chase state.")
	await get_tree().create_timer(0.15).timeout
	_expect_equal(threat.get_visual_state(), PatrolThreat.VisualState.EATING, "Contact should switch to the eat state.")
	threat.deactivate()
	target.queue_free()
	threat.queue_free()
	await get_tree().process_frame
	var bird_scene: PackedScene = load("res://scenes/actors/bird_threat.tscn") as PackedScene
	_expect_true(bird_scene != null, "The bird scene must load without a separate warning label.")
	if bird_scene == null:
		return
	var bird: PatrolThreat = bird_scene.instantiate() as PatrolThreat
	add_child(bird)
	await get_tree().process_frame
	_expect_true(
		bird.get_node_or_null("WarningMarker") == null,
		"The bird alert spritesheet must replace the old exclamation label."
	)
	var bird_entry: ThreatEntry = ThreatEntry.new()
	bird_entry.animal_type = ThreatEntry.AnimalType.BIRD
	bird_entry.world_region = ThreatEntry.BIRD_WORLD_REGION
	bird_entry.direction = -1
	bird_entry.speed = 280.0
	bird_entry.active_time = 2.4
	bird.activate(bird_entry, Vector2.ZERO, null)
	bird.set_warning_active(true)
	_expect_equal(
		bird.get_visual_state(),
		PatrolThreat.VisualState.ALERT,
		"A bird without WarningMarker must still enter the alert animation state."
	)
	_expect_true(
		bird.get_visual_animation_name() == &"alert",
		"A bird without WarningMarker must play its alert spritesheet."
	)
	bird.deactivate()
	bird.queue_free()
	await get_tree().process_frame


func _check_forward_vision_alert_boundaries() -> void:
	var fish_gameplay: GameplayRoot = _create_gameplay(AppFlow.GameMode.PATROL, 5.0)
	if fish_gameplay == null:
		return
	await get_tree().process_frame
	var fish_director: EncounterDirector = fish_gameplay.get_node("ModeHost/EncounterDirector") as EncounterDirector
	var fish_player: PlayerFish = fish_gameplay.get_node("World/ActorRoot/PlayerFish") as PlayerFish
	var fish_regions: RegionController = fish_gameplay.get_node("Systems/RegionController") as RegionController
	_expect_true(fish_director.force_start_pattern(&"single_fish_mid"), "The directional-view test should spawn a region-6 predator fish.")
	await _press_region_action(&"move_down")
	_expect_equal(fish_regions.get_current_region(), 6, "The player should enter the predator fish's lane.")
	var predator: PatrolThreat = fish_director.get_active_threats()[0]
	predator.global_position.x = fish_player.global_position.x - 160.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect_true(not fish_director.is_alert_active(), "A player behind a left-moving predator fish's eye must not trigger alert.")
	_expect_equal(predator.get_visual_state(), PatrolThreat.VisualState.IDLE, "A predator fish must remain idle while the player is behind it.")
	predator.global_position.x = fish_player.global_position.x + 160.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect_true(fish_director.is_alert_active(), "A player ahead of a predator fish's eye in the same lane must trigger alert.")
	_expect_equal(predator.get_visual_state(), PatrolThreat.VisualState.ALERT, "A predator fish seeing forward must play alert.")
	fish_director.stop_all()
	fish_gameplay.queue_free()
	await get_tree().process_frame

	var bird_gameplay: GameplayRoot = _create_gameplay(AppFlow.GameMode.PATROL, 5.0)
	if bird_gameplay == null:
		return
	await get_tree().process_frame
	var bird_director: EncounterDirector = bird_gameplay.get_node("ModeHost/EncounterDirector") as EncounterDirector
	var bird_player: PlayerFish = bird_gameplay.get_node("World/ActorRoot/PlayerFish") as PlayerFish
	_expect_true(bird_director.force_start_pattern(&"single_bird"), "The directional-view test should spawn a bird.")
	var bird: PatrolThreat = bird_director.get_active_threats()[0]
	bird.global_position.x = bird_player.global_position.x - 160.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect_true(not bird_director.is_alert_active(), "A player behind a left-flying bird's eye must not trigger alert.")
	bird.global_position.x = bird_player.global_position.x + 160.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect_true(bird_director.is_alert_active(), "A player ahead of a bird's eye anywhere on the surface lane must trigger alert.")
	_expect_equal(bird.get_visual_state(), PatrolThreat.VisualState.ALERT, "A bird seeing forward must play alert.")
	bird_director.stop_all()
	bird_gameplay.queue_free()
	await get_tree().process_frame


func _check_patrol_escape_and_pool_recycling() -> void:
	var gameplay: GameplayRoot = _create_gameplay(AppFlow.GameMode.PATROL, 5.0)
	if gameplay == null:
		return
	await get_tree().process_frame
	var director: EncounterDirector = gameplay.get_node("ModeHost/EncounterDirector") as EncounterDirector
	var pool: ThreatPool = gameplay.get_node("World/ActorRoot/Animals/ThreatPool") as ThreatPool
	var region_controller: RegionController = gameplay.get_node("Systems/RegionController") as RegionController
	var warning_panel: PanelContainer = gameplay.get_node("Interface/HUD/EncounterWarningPanel") as PanelContainer
	var camera: Camera2D = gameplay.get_node("World/CameraRig/Camera2D") as Camera2D
	_expect_float(gameplay.world_config.region_move_duration, 0.1, "Lane changes should take 0.1 seconds.")
	_expect_true(director.is_enabled_for_patrol(), "EncounterDirector should only be active in patrol mode.")
	_expect_equal(pool.get_total_capacity(), 6, "The pool should prewarm enough predators for overlapping natural exits.")
	_expect_true(director.force_start_pattern(&"bird_fish_mid"), "The patrol test should start the bird-and-fish preset.")
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect_true(director.is_alert_active(), "Entering a patrol threat view should start the warning immediately.")
	_expect_true(warning_panel.visible, "The encounter warning panel should be visible during alert.")
	_expect_equal(director.get_active_threat_count(), 2, "The bird-and-fish preset should spawn both threats together.")
	for threat: PatrolThreat in director.get_active_threats():
		var expected_state: PatrolThreat.VisualState = (
			PatrolThreat.VisualState.ALERT
			if threat.get_danger_region() == 5
			else PatrolThreat.VisualState.IDLE
		)
		_expect_equal(threat.get_visual_state(), expected_state, "Only predators currently seeing the player should use alert.")
	await _press_region_action(&"move_down")
	await _press_region_action(&"move_down")
	_expect_equal(region_controller.get_current_region(), 7, "The escape route should reach global region 7.")
	_expect_true(not director.is_alert_active(), "Leaving every current attack view should cancel alert.")
	_expect_true(not gameplay.is_failure_active(), "A completed safe route must not trigger failure.")
	var naturally_exiting_threats: Array[PatrolThreat] = director.get_active_threats()
	_expect_equal(naturally_exiting_threats.size(), 2, "Avoided threats should remain visible until they naturally leave the camera.")
	var positions_before_motion: Array[float] = []
	for threat: PatrolThreat in naturally_exiting_threats:
		_expect_true(threat.is_pool_active(), "Threats outside attack view should stay active while naturally exiting.")
		_expect_true(threat.is_encounter_danger_enabled(), "Leaving sight must preserve the threat's ability to detect the player again.")
		_expect_equal(threat.get_visual_state(), PatrolThreat.VisualState.IDLE, "Threats outside attack view should return to idle animation.")
		positions_before_motion.append(threat.global_position.x)
	await _press_region_action(&"move_up")
	await _press_region_action(&"move_up")
	await get_tree().physics_frame
	_expect_equal(region_controller.get_current_region(), 5, "The player should be able to re-enter the bird's attack view.")
	_expect_true(director.is_alert_active(), "Re-entering the same visible predator's view must start alert again.")
	var found_realerted_bird: bool = false
	for threat: PatrolThreat in naturally_exiting_threats:
		if threat.get_animal_type() == ThreatEntry.AnimalType.BIRD:
			found_realerted_bird = threat.get_visual_state() == PatrolThreat.VisualState.ALERT
	_expect_true(found_realerted_bird, "The same bird must replay alert every time it sees the player.")
	await _press_region_action(&"move_down")
	await _press_region_action(&"move_down")
	_expect_true(not director.is_alert_active(), "Leaving the repeated sighting must reset alert again.")
	await get_tree().create_timer(0.1).timeout
	for index: int in range(naturally_exiting_threats.size()):
		_expect_true(
			not is_equal_approx(naturally_exiting_threats[index].global_position.x, positions_before_motion[index]),
			"Avoided threats should keep their original world movement."
		)
		naturally_exiting_threats[index].global_position.x = camera.global_position.x - 2000.0
	await get_tree().physics_frame
	await get_tree().process_frame
	_expect_equal(director.get_active_threat_count(), 0, "Threats should return to the pool only after leaving the camera margin.")
	gameplay.queue_free()
	await get_tree().process_frame


func _check_three_threat_limit() -> void:
	var gameplay: GameplayRoot = _create_gameplay(AppFlow.GameMode.PATROL, 5.0)
	if gameplay == null:
		return
	await get_tree().process_frame
	var director: EncounterDirector = gameplay.get_node("ModeHost/EncounterDirector") as EncounterDirector
	_expect_true(director.force_start_pattern(&"bird_two_fish"), "The three-threat preset should be startable.")
	_expect_equal(director.get_active_threat_count(), 3, "One bird and two fish should appear simultaneously.")
	_expect_true(director.get_active_threat_count() <= 3, "No encounter may exceed three simultaneous animals.")
	director.stop_all()
	gameplay.queue_free()
	await get_tree().process_frame


func _check_distance_scheduling() -> void:
	var gameplay: GameplayRoot = _create_gameplay(AppFlow.GameMode.PATROL, 5.0, false, true)
	if gameplay == null:
		return
	await get_tree().process_frame
	var director: EncounterDirector = gameplay.get_node("ModeHost/EncounterDirector") as EncounterDirector
	var player: PlayerFish = gameplay.get_node("World/ActorRoot/PlayerFish") as PlayerFish
	var camera: Camera2D = gameplay.get_node("World/CameraRig/Camera2D") as Camera2D
	_expect_equal(director.get_active_threat_count(), 0, "Patrol should not spawn before its distance threshold.")
	player.global_position.x += director.first_encounter_distance + 10.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect_true(director.is_alert_active(), "Crossing the configured world-distance threshold should select a legal preset.")
	_expect_true(director.get_active_threat_count() >= 2, "A distance-triggered encounter should spawn its preset together.")
	_expect_true(director.get_active_threat_count() <= 3, "Distance scheduling must preserve the three-animal limit.")
	await _press_region_action(&"move_down")
	await _press_region_action(&"move_down")
	var exiting_combination_count: int = director.get_active_threat_count()
	_expect_true(exiting_combination_count >= 2, "The first combination should remain on screen after being avoided.")
	_expect_equal(director.get_current_encounter_threat_count(), 0, "Animals outside attack view should no longer be alerting.")
	player.global_position.x += director.simple_followup_distance + 10.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect_true(director.is_alert_active(), "A simple encounter should fill the short interval after a combination.")
	_expect_equal(director.get_current_encounter_threat_count(), 1, "Exactly one visible predator should currently see the player.")
	_expect_true(director.get_active_threat_count() > exiting_combination_count, "The simple danger should overlap the naturally exiting combination.")
	await _press_region_action(&"move_up")
	var exiting_with_simple_count: int = director.get_active_threat_count()
	_expect_true(exiting_with_simple_count >= 3, "Both avoided groups should continue moving through the scene.")
	_expect_true(director.is_alert_active(), "An earlier fish must alert again when the player re-enters its attack view.")
	_expect_equal(director.get_current_encounter_threat_count(), 1, "Only the re-sighted fish should be alerting in region 6.")
	_expect_true(director.get_active_threat_count() <= director.maximum_visible_threats, "Overlapping natural exits must respect the visible-animal cap.")
	for threat: PatrolThreat in director.get_active_threats():
		threat.global_position.x = camera.global_position.x - 2000.0
	await get_tree().physics_frame
	await get_tree().process_frame
	_expect_equal(director.get_active_threat_count(), 0, "Naturally exiting animals should release their pool slots.")
	player.global_position.x += director.combination_followup_distance + 10.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect_true(director.is_alert_active(), "Automatic scheduling should resume after previous animals release capacity.")
	_expect_true(director.get_active_threat_count() >= 2, "Automatic scheduling should still alternate back to a complete combination.")
	_expect_true(director.get_active_threat_count() <= 3, "The resumed combination must preserve the three-animal limit.")
	director.stop_all()
	gameplay.queue_free()
	await get_tree().process_frame


func _check_forage_uses_unified_ecology_threats() -> void:
	var gameplay: GameplayRoot = _create_gameplay(AppFlow.GameMode.FORAGE, 5.0)
	if gameplay == null:
		return
	await get_tree().process_frame
	var director: EncounterDirector = gameplay.get_node("ModeHost/EncounterDirector") as EncounterDirector
	var ecology: EcologyEventDirector = gameplay.get_node("ModeHost/EcologyEventDirector") as EcologyEventDirector
	var player: PlayerFish = gameplay.get_node("World/ActorRoot/PlayerFish") as PlayerFish
	_expect_true(not director.is_enabled_for_patrol(), "Forage mode must keep patrol encounters disabled.")
	player.global_position.x += 5000.0
	await get_tree().physics_frame
	await get_tree().process_frame
	_expect_true(ecology.is_running(), "Forage mode must enable the unified ecology-event director.")
	_expect_true(director.get_active_threat_count() >= 1, "Unified forage must now reuse the predator pool for ecology events.")
	_expect_true(director.get_active_threat_count() <= ecology.maximum_visible_threats, "Unified forage ecology must preserve the three-predator cap.")
	gameplay.queue_free()
	await get_tree().process_frame


func _check_repeated_alert_and_one_second_capture_flow() -> void:
	var gameplay: GameplayRoot = _create_gameplay(AppFlow.GameMode.PATROL, 5.0, true)
	if gameplay == null:
		return
	gameplay.failure_started.connect(_on_failure_started)
	await get_tree().process_frame
	var director: EncounterDirector = gameplay.get_node("ModeHost/EncounterDirector") as EncounterDirector
	var player: PlayerFish = gameplay.get_node("World/ActorRoot/PlayerFish") as PlayerFish
	var mode_host: Node = gameplay.get_node("ModeHost")
	var threat_pool: ThreatPool = gameplay.get_node("World/ActorRoot/Animals/ThreatPool") as ThreatPool
	threat_pool.threat_bite_started.connect(_on_threat_bite_started)
	await _press_region_action(&"move_down")
	_expect_true(director.force_start_pattern(&"single_fish_mid"), "The capture test should start a region-6 predator fish.")
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect_true(director.is_alert_active(), "The fish should alert while the player remains in its attack view.")
	await get_tree().create_timer(0.55).timeout
	_expect_true(not gameplay.is_predator_capture_active(), "Exposure shorter than one second must not capture the player.")
	var active_fish: PatrolThreat = director.get_active_threats()[0]
	_expect_equal(active_fish.get_visual_state(), PatrolThreat.VisualState.ALERT, "A fish that still sees the player must remain in alert.")
	var active_fish_visual: AnimatedSprite2D = active_fish.get_node("VisualRoot/AnimatedVisual") as AnimatedSprite2D
	_expect_true(active_fish_visual.is_playing(), "The alert spritesheet must keep playing throughout continuous sight.")
	await _press_region_action(&"move_up")
	_expect_true(not director.is_alert_active(), "Leaving sight before one second must cancel the current alert.")
	await _press_region_action(&"move_down")
	_expect_true(director.is_alert_active(), "The same fish must alert again after the player re-enters its view.")
	active_fish.global_position.x = player.global_position.x + 700.0
	await get_tree().physics_frame
	await get_tree().create_timer(0.55).timeout
	_expect_true(not gameplay.is_predator_capture_active(), "The second sighting must restart from zero rather than reuse earlier exposure.")
	_expect_true(not gameplay.is_failure_active(), "Two sub-second sightings must not be combined into a failure.")
	await get_tree().create_timer(0.4).timeout
	_expect_true(gameplay.is_failure_active(), "One continuous second in the same fish's view should enter the unified failure flow.")
	_expect_equal(_predator_bite_count, 1, "The attacking predator must emit one bite when eating begins.")
	_expect_true(not player.is_region_input_enabled(), "Predator capture should disable lane input.")
	_expect_equal(mode_host.process_mode, Node.PROCESS_MODE_DISABLED, "Predator failure should stop the encounter host.")
	_expect_true(_failure_reasons.has(AppFlow.FAILURE_PREDATOR), "Predator capture should report the predator failure reason.")
	var stopped_x: float = player.global_position.x
	await get_tree().create_timer(0.15).timeout
	_expect_float(player.global_position.x, stopped_x, "The world should stop advancing during predator capture and failure.")
	gameplay.queue_free()
	await get_tree().process_frame


func _create_gameplay(
	mode: AppFlow.GameMode,
	death_duration: float,
	instant_attack: bool = false,
	automatic_spawning: bool = false
) -> GameplayRoot:
	AppFlow.current_mode = mode
	var gameplay_scene: PackedScene = load(GAMEPLAY_SCENE_PATH) as PackedScene
	if gameplay_scene == null:
		_fail("Could not load GameplayRoot for step 4.")
		return null
	var gameplay: GameplayRoot = gameplay_scene.instantiate() as GameplayRoot
	var test_config: WorldConfig = gameplay.world_config.duplicate() as WorldConfig
	test_config.death_animation_duration = death_duration
	test_config.run_finish_distance = 100000.0
	gameplay.world_config = test_config
	gameplay.route_scenes_after_settlement = false
	var director: EncounterDirector = gameplay.get_node("ModeHost/EncounterDirector") as EncounterDirector
	director.set_automatic_spawning_enabled(automatic_spawning)
	if instant_attack:
		director.attack_charge_duration = 0.0
		director.consume_duration = 0.0
	add_child(gameplay)
	return gameplay


func _press_region_action(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().create_timer(0.15).timeout


func _on_failure_started(reason: StringName) -> void:
	_failure_reasons.append(reason)


func _on_threat_bite_started(_threat: PatrolThreat) -> void:
	_predator_bite_count += 1


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
		print("STEP4_RUNTIME_TEST_OK")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	get_tree().quit(1)

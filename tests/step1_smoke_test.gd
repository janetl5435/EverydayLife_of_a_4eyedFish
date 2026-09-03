extends SceneTree

const EXPECTED_ACTIONS: Array[StringName] = [
	&"move_up",
	&"move_down",
	&"interact",
	&"jump",
	&"accelerate",
	&"pause",
]
const EXPECTED_SCENES: Array[String] = [
	"res://scenes/app/bootstrap.tscn",
	"res://scenes/ui/intro.tscn",
	"res://scenes/ui/main_menu.tscn",
	"res://scenes/ui/compendium.tscn",
	"res://scenes/ui/settings_screen.tscn",
	"res://scenes/gameplay/gameplay_root.tscn",
	"res://scenes/ui/result_screen.tscn",
	"res://scenes/ui/death_restart.tscn",
]
const EXPECTED_COLLISION_LAYERS: Array[String] = [
	"Player",
	"Hazard",
	"Food",
	"Interactable",
	"WorldBoundary",
]


func _initialize() -> void:
	var failures: Array[String] = []
	_check_main_scene(failures)
	_check_input_actions(failures)
	_check_collision_layers(failures)
	_check_scenes(failures)
	if failures.is_empty():
		print("STEP1_SMOKE_TEST_OK")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _check_main_scene(failures: Array[String]) -> void:
	var main_scene: String = String(ProjectSettings.get_setting("application/run/main_scene", ""))
	if main_scene != "res://scenes/app/bootstrap.tscn":
		failures.append("Unexpected main scene: %s" % main_scene)


func _check_input_actions(failures: Array[String]) -> void:
	for action: StringName in EXPECTED_ACTIONS:
		if not InputMap.has_action(action):
			failures.append("Missing input action: %s" % action)
			continue
		if InputMap.action_get_events(action).is_empty():
			failures.append("Input action has no events: %s" % action)
	_expect_key(&"move_up", KEY_W, failures)
	_expect_key(&"move_up", KEY_UP, failures)
	_expect_key(&"move_down", KEY_S, failures)
	_expect_key(&"move_down", KEY_DOWN, failures)
	if InputMap.has_action(&"switch_depth"):
		failures.append("The retired Q depth-switch action must be removed.")
	_expect_key(&"interact", KEY_F, failures)
	_expect_key(&"jump", KEY_SPACE, failures)
	_expect_key(&"accelerate", KEY_SHIFT, failures)
	_expect_key(&"pause", KEY_ESCAPE, failures)


func _expect_key(action: StringName, keycode: int, failures: Array[String]) -> void:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey and event.keycode == keycode:
			return
	failures.append("Input action %s is missing keycode %d" % [action, keycode])


func _check_collision_layers(failures: Array[String]) -> void:
	for index: int in range(EXPECTED_COLLISION_LAYERS.size()):
		var setting_path: String = "layer_names/2d_physics/layer_%d" % (index + 1)
		var layer_name: String = String(ProjectSettings.get_setting(setting_path, ""))
		if layer_name != EXPECTED_COLLISION_LAYERS[index]:
			failures.append("Unexpected collision layer %d: %s" % [index + 1, layer_name])


func _check_scenes(failures: Array[String]) -> void:
	for scene_path: String in EXPECTED_SCENES:
		var resource: Resource = load(scene_path)
		if resource is not PackedScene:
			failures.append("Could not load scene: %s" % scene_path)

extends Node


func _ready() -> void:
	AppFlow.open_intro.call_deferred()

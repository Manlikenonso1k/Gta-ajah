extends PanelContainer
## In-game phone pause menu. It must keep receiving input while the world pauses.

signal resume_requested


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel") and not event.is_echo():
		resume_requested.emit()
		get_viewport().set_input_as_handled()

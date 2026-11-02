extends Control
## First screen: the player's name, then solo, online (cloud server), host on
## Wi-Fi or join a Wi-Fi host. Online choices connect through the Net
## autoload (scripts/net.gd) before the city loads.

const GAME_SCENE := "res://scenes/main.tscn"
const GOLD := Color(0.95, 0.77, 0.34)
const MINT := Color(0.55, 0.84, 0.72)

var _name_edit: LineEdit
var _server_edit: LineEdit
var _join_edit: LineEdit
var _status: Label
var _buttons: Array[Button] = []
var _waiting := false


func _ready() -> void:
	get_tree().paused = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not OS.has_feature("mobile"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var background := ColorRect.new()
	background.color = Color(0.045, 0.075, 0.08)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 520
	column.add_theme_constant_override("separation", 12)
	center.add_child(column)

	_label(column, "GARDEN CITY STORIES", 34, GOLD)
	_label(column, "Port Harcourt", 16, MINT)
	column.add_child(_spacer(8))

	var prefs: Dictionary = Net.load_prefs()
	_label(column, "YOUR NAME", 14, MINT, HORIZONTAL_ALIGNMENT_LEFT)
	_name_edit = _edit(column, str(prefs.get("name", "")), "Player")
	_name_edit.max_length = 16

	_button(column, "PLAY SOLO", _play_solo)
	column.add_child(_spacer(6))

	_label(column, "ONLINE  •  anywhere with internet", 14, MINT, HORIZONTAL_ALIGNMENT_LEFT)
	_server_edit = _edit(column, Net.default_server_url(), "wss://your-server.onrender.com")
	_button(column, "PLAY ONLINE", _play_online)
	column.add_child(_spacer(6))

	_label(column, "SAME WI-FI  •  no server needed", 14, MINT, HORIZONTAL_ALIGNMENT_LEFT)
	_button(column, "HOST ON THIS PHONE", _host_wifi)
	_join_edit = _edit(column, str(prefs.get("join_address", "")), "Host's address, e.g. 192.168.1.5")
	_button(column, "JOIN HOST", _join_wifi)

	_status = _label(column, "Everyone online starts outside HOPE MEDICAL POINT.", 14, Color(0.88, 0.92, 0.89))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	Net.connected.connect(_on_connected)
	Net.disconnected.connect(_on_disconnected)
	# Coming back here from a game always starts offline
	if Net.online():
		Net.leave()


func _play_solo() -> void:
	_save_prefs()
	get_tree().change_scene_to_file(GAME_SCENE)


func _play_online() -> void:
	var url := _server_edit.text.strip_edges()
	if url.is_empty():
		_show("Enter the online server address first (see docs/ONLINE.md).", true)
		return
	_save_prefs()
	if Net.join(url, _name_edit.text) != OK:
		_show("That server address doesn't look right.", true)
		return
	_wait("Connecting… a sleeping free server can take up to a minute to wake.")


func _host_wifi() -> void:
	_save_prefs()
	var err := Net.host(_name_edit.text)
	if err != OK:
		_show("Couldn't host on this phone (error %d)." % err, true)
		return
	get_tree().change_scene_to_file(GAME_SCENE)


func _join_wifi() -> void:
	var address := _join_edit.text.strip_edges()
	if address.is_empty():
		_show("Type the address shown at the top of the host's screen.", true)
		return
	_save_prefs()
	if Net.join(address, _name_edit.text) != OK:
		_show("That address doesn't look right.", true)
		return
	_wait("Joining %s…" % address)


func _on_connected(_id: int) -> void:
	if _waiting:
		_waiting = false
		get_tree().change_scene_to_file(GAME_SCENE)


func _on_disconnected(reason: String) -> void:
	if _waiting:
		_waiting = false
		_set_buttons_enabled(true)
		_show(reason + ". Check the address and your internet, then try again.", true)


func _wait(text: String) -> void:
	_waiting = true
	_set_buttons_enabled(false)
	_show(text, false)


func _show(text: String, error: bool) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45) if error else Color(0.88, 0.92, 0.89))


func _save_prefs() -> void:
	var prefs: Dictionary = Net.load_prefs()
	prefs["name"] = _name_edit.text.strip_edges()
	prefs["join_address"] = _join_edit.text.strip_edges()
	# Only remember a server typed here, so a new build's default still applies
	var typed := _server_edit.text.strip_edges()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(Net.CONFIG_PATH))
	var baked := str(parsed.get("server_url", "")) if parsed is Dictionary else ""
	prefs["server_url"] = typed if typed != baked else ""
	Net.save_prefs(prefs)


func _set_buttons_enabled(enabled: bool) -> void:
	for button in _buttons:
		button.disabled = not enabled


func _label(parent: Control, text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _edit(parent: Control, text: String, placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = text
	edit.placeholder_text = placeholder
	edit.custom_minimum_size.y = 46
	edit.add_theme_font_size_override("font_size", 18)
	parent.add_child(edit)
	return edit


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 52
	button.add_theme_font_size_override("font_size", 19)
	button.pressed.connect(action)
	parent.add_child(button)
	_buttons.append(button)
	return button


func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	return spacer

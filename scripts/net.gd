extends Node
## Online play: the connection (autoload "Net").
##
## Every player sends small JSON messages over WebSockets. A relay gives each
## connection an id, stamps it on the messages it receives and forwards them
## to everyone else. The relay is either the cloud server (server/server.js) or
## a phone hosting on the same Wi-Fi (HOST mode below runs the same relay in
## this script and plays as id 1).
##
##   Net.join("wss://example.onrender.com", "Ada")   # cloud or Wi-Fi host
##   Net.host("Ada")                                  # this phone is the relay
##   Net.send({"t": "state", ...})                    # to every other player
##
## Messages (all have "t"; the relay adds "id" to forwarded ones):
##   hello   {n}            client -> relay, first message
##   welcome {id, v}        relay -> client, the client's id
##   state   {n, p, y, s, a, c}   a player's position and car, ~12 times a second
##   leave   {id}           relay -> everyone, a player disconnected

signal connected(my_id: int)
signal disconnected(reason: String)
signal message(from_id: int, data: Dictionary)
signal peer_left(id: int)

enum Mode { OFFLINE, CLIENT, HOST }

const PROTOCOL := 1
const LAN_PORT := 8910
const CONFIG_PATH := "res://net_config.json"
const PREFS_PATH := "user://net_prefs.json"
## A sleeping free cloud server can take most of a minute to wake up
const CONNECT_TIMEOUT := 75.0

var mode := Mode.OFFLINE
var my_id := 0
var player_name := "Player"
var is_connected := false

var _client: WebSocketPeer
var _connect_time := 0.0
var _welcomed := false
## HOST mode: the listening socket and connections by id
var _server: TCPServer
var _pending: Array[WebSocketPeer] = []
var _peers := {}   # id -> WebSocketPeer
var _named := {}   # id -> true once its hello arrived
var _next_id := 2


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func online() -> bool:
	return mode != Mode.OFFLINE


## The cloud server address baked into the build (net_config.json), unless
## the player typed another one in the start menu.
func default_server_url() -> String:
	var prefs := load_prefs()
	if str(prefs.get("server_url", "")) != "":
		return str(prefs["server_url"])
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	return str(parsed.get("server_url", "")) if parsed is Dictionary else ""


func load_prefs() -> Dictionary:
	if not FileAccess.file_exists(PREFS_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PREFS_PATH))
	return parsed if parsed is Dictionary else {}


func save_prefs(prefs: Dictionary) -> void:
	var file := FileAccess.open(PREFS_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(prefs))


## Connects to a relay: "wss://host" (cloud), "ws://192.168.1.5:8910" or a
## bare Wi-Fi address like "192.168.1.5".
func join(address: String, name_: String) -> Error:
	leave()
	player_name = _clean_name(name_)
	var url := address.strip_edges()
	if not url.begins_with("ws://") and not url.begins_with("wss://"):
		url = "ws://%s:%d" % [url, LAN_PORT] if not ":" in url else "ws://" + url
	_client = WebSocketPeer.new()
	_client.inbound_buffer_size = 1 << 20
	var err := _client.connect_to_url(url)
	if err != OK:
		_client = null
		return err
	mode = Mode.CLIENT
	_connect_time = 0.0
	_welcomed = false
	return OK


## This phone becomes the Wi-Fi relay and plays as id 1.
func host(name_: String, port := LAN_PORT) -> Error:
	leave()
	player_name = _clean_name(name_)
	_server = TCPServer.new()
	var err := _server.listen(port)
	if err != OK:
		_server = null
		return err
	mode = Mode.HOST
	my_id = 1
	_next_id = 2
	is_connected = true
	connected.emit(my_id)
	return OK


func leave() -> void:
	if _client != null:
		_client.close()
	_client = null
	if _server != null:
		_server.stop()
	_server = null
	for peer: WebSocketPeer in _peers.values():
		peer.close()
	_peers.clear()
	_named.clear()
	_pending.clear()
	var was_online := mode != Mode.OFFLINE
	mode = Mode.OFFLINE
	my_id = 0
	is_connected = false
	if was_online:
		disconnected.emit("left")


## Sends to every other player.
func send(data: Dictionary) -> void:
	if mode == Mode.CLIENT and _welcomed and _client.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_client.send_text(JSON.stringify(data))
	elif mode == Mode.HOST:
		var stamped := data.duplicate()
		stamped["id"] = 1
		_broadcast(JSON.stringify(stamped), -1)


## Wi-Fi addresses other phones can type to join this host.
static func lan_addresses() -> Array[String]:
	var found: Array[String] = []
	for address in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10.") or (address.begins_with("172.") and address.split(".")[1].to_int() >= 16 and address.split(".")[1].to_int() <= 31):
			found.append(address)
	return found


func _process(delta: float) -> void:
	if mode == Mode.CLIENT:
		_poll_client(delta)
	elif mode == Mode.HOST:
		_poll_host()


func _poll_client(delta: float) -> void:
	_client.poll()
	var state := _client.get_ready_state()
	if state == WebSocketPeer.STATE_CONNECTING:
		_connect_time += delta
		if _connect_time > CONNECT_TIMEOUT:
			_drop_client("Could not reach the server")
		return
	if state == WebSocketPeer.STATE_CLOSED:
		_drop_client("Connection closed" if _welcomed else "Could not reach the server")
		return
	if state != WebSocketPeer.STATE_OPEN:
		return
	if _connect_time >= 0.0 and not _welcomed:
		# First moment open: introduce ourselves once
		_connect_time = -1.0
		_client.send_text(JSON.stringify({"t": "hello", "n": player_name, "v": PROTOCOL}))
	while _client.get_available_packet_count() > 0:
		var data := _parse(_client.get_packet().get_string_from_utf8())
		if data.is_empty():
			continue
		match str(data.get("t", "")):
			"welcome":
				my_id = int(data.get("id", 0))
				_welcomed = true
				is_connected = true
				connected.emit(my_id)
			"leave":
				peer_left.emit(int(data.get("id", 0)))
			_:
				if _welcomed and data.has("id"):
					message.emit(int(data["id"]), data)


func _drop_client(reason: String) -> void:
	_client = null
	mode = Mode.OFFLINE
	my_id = 0
	is_connected = false
	_welcomed = false
	disconnected.emit(reason)


func _poll_host() -> void:
	while _server.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = 1 << 20
		if ws.accept_stream(_server.take_connection()) == OK:
			_pending.append(ws)
	for ws: WebSocketPeer in _pending.duplicate():
		ws.poll()
		var state := ws.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			_pending.erase(ws)
			_peers[_next_id] = ws
			_next_id += 1
		elif state == WebSocketPeer.STATE_CLOSED:
			_pending.erase(ws)
	for id: int in _peers.keys():
		var ws: WebSocketPeer = _peers[id]
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_peers.erase(id)
			var was_named: bool = _named.has(id)
			_named.erase(id)
			if was_named:
				_broadcast(JSON.stringify({"t": "leave", "id": id}), -1)
				peer_left.emit(id)
			continue
		while ws.get_available_packet_count() > 0:
			var data := _parse(ws.get_packet().get_string_from_utf8())
			if data.is_empty():
				continue
			if str(data.get("t", "")) == "hello":
				_named[id] = true
				ws.send_text(JSON.stringify({"t": "welcome", "id": id, "v": PROTOCOL}))
				continue
			if not _named.has(id):
				continue
			data["id"] = id
			_broadcast(JSON.stringify(data), id)
			message.emit(id, data)


## To every welcomed connection except `skip_id`.
func _broadcast(text: String, skip_id: int) -> void:
	for id: int in _peers:
		if id != skip_id and _named.has(id):
			var ws: WebSocketPeer = _peers[id]
			if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
				ws.send_text(text)


static func _parse(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


static func _clean_name(name_: String) -> String:
	var cleaned := name_.strip_edges().substr(0, 16)
	return cleaned if cleaned != "" else "Player"

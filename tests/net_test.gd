extends SceneTree
## Online play check, headless:
##   godot --headless --path . --script tests/net_test.gd
##   godot --headless --path . --script tests/net_test.gd -- --relay ws://127.0.0.1:8920
## 1. Wi-Fi host: Net hosts, a raw WebSocket client joins, messages both ways.
## 2. Relay (with --relay, e.g. server/server.js running): Net and a raw client
##    both join it and exchange messages.
## 3. In game: main.tscn as Wi-Fi host. The player spawns at the clinic and
##    sends its state; a fake remote player appears, drives a parked car
##    (frozen, follows the messages, can't be entered) and gets out again.

const PORT := 8911
const StreetPlaces = preload("res://scripts/street_places.gd")
const VehiclePersistence = preload("res://scripts/vehicle_persistence.gd")

var net: Node
var failures := 0
var received: Array = []


func _initialize() -> void:
	VehiclePersistence.SAVE_PATH = "user://net_test_vehicle_state.json"
	VehiclePersistence.TEMP_PATH = "user://net_test_vehicle_state.json.tmp"
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1


## JSON numbers come back as floats; compare position arrays by value.
func _same(a: Variant, b: Array) -> bool:
	if not a is Array or a.size() != b.size():
		return false
	for i in b.size():
		if not is_equal_approx(float(a[i]), float(b[i])):
			return false
	return true


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## Polls `ws` until a message with t == `type` arrives (or ~5 s pass).
func _read(ws: WebSocketPeer, type: String) -> Dictionary:
	for i in 300:
		ws.poll()
		while ws.get_available_packet_count() > 0:
			var data: Variant = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if data is Dictionary and str(data.get("t", "")) == type:
				return data
		await process_frame
	return {}


func _raw_join(url: String) -> WebSocketPeer:
	var ws := WebSocketPeer.new()
	ws.connect_to_url(url)
	for i in 300:
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send_text(JSON.stringify({"t": "hello", "n": "Raw", "v": 1}))
			return ws
		await process_frame
	return ws


func _on_message(from_id: int, data: Dictionary) -> void:
	received.append([from_id, data])


func _wait_received(type: String) -> Array:
	for i in 300:
		for item in received:
			if str(item[1].get("t", "")) == type:
				return item
		await process_frame
	return []


func _run() -> void:
	net = root.get_node_or_null("Net")
	_check(net != null, "Net autoload present")
	if net == null:
		quit(1)
		return
	net.message.connect(_on_message)
	await _test_host()
	var args := OS.get_cmdline_user_args()
	var relay_at := args.find("--relay")
	if relay_at >= 0 and relay_at + 1 < args.size():
		await _test_relay(args[relay_at + 1])
	await _test_game()
	print("net test: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
	quit(1 if failures > 0 else 0)


func _test_host() -> void:
	_check(net.host("Host", PORT) == OK, "host listens on %d" % PORT)
	var ws := await _raw_join("ws://127.0.0.1:%d" % PORT)
	var welcome := await _read(ws, "welcome")
	_check(int(welcome.get("id", 0)) == 2, "client welcomed as id 2")
	await _frames(2)
	net.send({"t": "state", "n": "Host", "p": [1, 2, 3]})
	var state := await _read(ws, "state")
	_check(int(state.get("id", 0)) == 1 and _same(state.get("p"), [1, 2, 3]), "host state reaches client with id 1")
	received.clear()
	ws.send_text(JSON.stringify({"t": "state", "n": "Raw", "p": [4, 5, 6]}))
	var got := await _wait_received("state")
	_check(not got.is_empty() and got[0] == 2 and _same(got[1].get("p"), [4, 5, 6]), "client state reaches host from id 2")
	ws.close()
	await _frames(30)
	net.leave()


func _test_relay(url: String) -> void:
	received.clear()
	var connected := [0]
	var on_connected := func(id: int) -> void: connected[0] = id
	net.connected.connect(on_connected)
	_check(net.join(url, "NetClient") == OK, "join relay " + url)
	for i in 300:
		if connected[0] != 0:
			break
		await process_frame
	net.connected.disconnect(on_connected)
	_check(connected[0] >= 2, "welcomed by relay (id %d)" % connected[0])
	var ws := await _raw_join(url)
	var welcome := await _read(ws, "welcome")
	var raw_id := int(welcome.get("id", 0))
	_check(raw_id >= 2 and raw_id != connected[0], "second client gets its own id %d" % raw_id)
	net.send({"t": "state", "n": "NetClient", "p": [7, 8, 9]})
	var state := await _read(ws, "state")
	_check(int(state.get("id", 0)) == connected[0] and _same(state.get("p"), [7, 8, 9]), "relay forwards Net's state with its id")
	ws.send_text(JSON.stringify({"t": "state", "n": "Raw", "p": [1, 1, 1]}))
	var got := await _wait_received("state")
	_check(not got.is_empty() and got[0] == raw_id, "relay forwards the raw client's state to Net")
	received.clear()
	ws.close()
	var left := await _wait_received("leave")
	_check(left.is_empty(), "leave is reported through peer_left, not message")
	net.leave()
	await _frames(10)


func _test_game() -> void:
	_check(net.host("Host", PORT) == OK, "host again for the game test")
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 90:
		await physics_frame
	for traffic in get_nodes_in_group("traffic"):
		traffic.queue_free()
	var player: CharacterBody3D = main._player
	var spawn := StreetPlaces.clinic_spawn(1)
	_check(Vector2(player.global_position.x - spawn.origin.x, player.global_position.z - spawn.origin.z).length() < 1.5, "player spawned outside the clinic %s" % player.global_position)
	_check(player.is_on_floor(), "player standing at the spawn")
	_check(main.get_node_or_null("NetSync") != null, "NetSync running")

	var ws := await _raw_join("ws://127.0.0.1:%d" % PORT)
	var welcome := await _read(ws, "welcome")
	var friend := int(welcome.get("id", 0))
	var state := await _read(ws, "state")
	_check(state.get("n") == "Host" and state.get("a") in ["idle", "walk"] and not state.has("c"), "game sends the player's state")

	# The friend appears on foot near the clinic
	var near := spawn.origin + Vector3(0, 0, 3)
	ws.send_text(JSON.stringify({"t": "state", "n": "Friend", "p": [near.x, near.y, near.z], "y": 0.0, "s": 3.0, "a": "walk"}))
	await _frames(20)
	ws.poll()
	var puppet: Node3D = main.get_node_or_null("RemotePlayer_%d" % friend)
	_check(puppet != null and puppet.visible, "friend's puppet appears")
	_check(puppet != null and puppet.global_position.distance_to(near) < 0.5, "puppet at the friend's position")
	_check(main._net_sync.player_count() == 2, "status counts 2 players")

	# The friend drives the second parked car along the road
	var car: VehicleBody3D
	for candidate in get_nodes_in_group("persistent_vehicles"):
		if candidate.persistent_id != "corolla_000":
			car = candidate
			break
	var start: Vector3 = car.global_position
	var q := car.global_basis.get_rotation_quaternion()
	for step in 12:
		var pos := start + Vector3(0, 0.3, step * 0.8)
		ws.send_text(JSON.stringify({"t": "state", "n": "Friend", "p": [pos.x, pos.y, pos.z], "y": 0.0, "s": 0.0, "a": "idle",
			"c": {"k": car.persistent_id, "m": car.model, "x": [pos.x, pos.y, pos.z], "q": [q.x, q.y, q.z, q.w], "v": [0, 0, 10]}}))
		await _frames(5)
		ws.poll()
	await _frames(20)
	_check(car.freeze and car.has_meta("net_remote_driver"), "driven car is frozen and marked remote")
	_check(car.global_position.distance_to(start + Vector3(0, 0.3, 11 * 0.8)) < 1.5, "car follows the friend (moved %.1f m)" % car.global_position.distance_to(start))
	_check(not puppet.visible, "puppet hidden while driving")

	# Out of the car: it stays and is simulated here again
	var stop := car.global_position
	ws.send_text(JSON.stringify({"t": "state", "n": "Friend", "p": [stop.x + 2, 0.1, stop.z], "y": 0.0, "s": 0.0, "a": "idle"}))
	await _frames(20)
	_check(not car.has_meta("net_remote_driver") and not car.freeze, "car released when the friend gets out")
	_check(puppet.visible, "puppet visible again")

	# The friend's own traffic car: a stand-in copy appears and goes away
	ws.send_text(JSON.stringify({"t": "state", "n": "Friend", "p": [stop.x + 6, 0.6, stop.z], "y": 0.0, "s": 0.0, "a": "idle",
		"c": {"k": "", "m": "hiace", "x": [stop.x + 6, 0.6, stop.z], "q": [0, 0, 0, 1], "v": [0, 0, 0]}}))
	await _frames(20)
	var ghost: Node = main.get_node_or_null("RemoteCar_%d" % friend)
	_check(ghost != null and ghost.model == "hiace", "stand-in car for a traffic car")
	ws.send_text(JSON.stringify({"t": "state", "n": "Friend", "p": [stop.x + 8, 0.1, stop.z], "y": 0.0, "s": 0.0, "a": "idle"}))
	await _frames(20)
	_check(not is_instance_valid(ghost) or ghost.is_queued_for_deletion(), "stand-in removed after getting out")

	ws.close()
	await _frames(60)
	_check(not is_instance_valid(puppet), "puppet removed when the friend disconnects")
	net.leave()
	main.queue_free()
	await _frames(5)

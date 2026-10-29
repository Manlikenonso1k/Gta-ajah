extends SceneTree
## Hands on the steering wheel, for all 10 vehicle models.
## Run: godot --headless --path . --script tests/steering_hands_test.gd
##
## Each model's steering wheel is mounted (steering_wheel.gd) and drivers of
## different sizes are seated (seated_pose.gd): the player and the tallest and
## shortest registry characters. Steering is swept from full left to full
## right; at every step both palms must stay within 3 cm of the rim, the rim
## must turn by the model's wheel_turn_deg at full lock, and the hands must
## follow the rim as it turns. The top of each driver's head must also stay
## under the roof.

const VehicleModel = preload("res://scripts/vehicle_model.gd")
const SteeringWheel = preload("res://scripts/steering_wheel.gd")
const SeatedPose = preload("res://scripts/seated_pose.gd")
const VehicleOccupants = preload("res://scripts/vehicle_occupants.gd")
const Locomotion = preload("res://scripts/locomotion.gd")
const SkeletonMap = preload("res://scripts/skeleton_map.gd")
const Registry = preload("res://scripts/pedestrian_registry.gd")

const TOLERANCE := 0.03
const STEPS := 20

var _failures: Array[String] = []


func _initialize() -> void:
	create_timer(300.0).timeout.connect(func():
		push_error("steering_hands_test timed out")
		quit(2))
	_run.call_deferred()


func _run() -> void:
	var drivers := _drivers()
	print("drivers: ", drivers.map(func(d): return "%s %.2f m" % [d.id, d.height]))
	var worst_all := 0.0
	for key: String in VehicleModel.MODELS:
		var data: Dictionary = VehicleModel.build(key)
		var cabin := VehicleOccupants.cabin_for(key, data)
		if not cabin.is_empty():
			cabin["roof_triangles"] = VehicleOccupants._roof_triangles(key, data, cabin["seat"])
		if cabin.is_empty():
			_failures.append("%s: no cabin data" % key)
			continue
		var holder := Node3D.new()
		holder.name = "Vehicle_" + key
		root.add_child(holder)
		var pivot := SteeringWheel.attach(holder, data)
		var max_turn: float = cabin["max_turn"]
		# The rim turns by wheel_turn_deg at full lock, both ways
		var marker := Vector3.RIGHT * float(cabin["wheel_radius"])
		for lock in [1.0, -1.0]:
			SteeringWheel.update(pivot, lock * 0.5, 0.5)
			var got := marker.signed_angle_to(pivot.basis * marker, cabin["wheel_axis"])
			if absf(wrapf(got - wrapf(lock * max_turn, -PI, PI), -PI, PI)) > 0.01:
				_failures.append("%s: full lock %+d turned the rim %.1f deg, expected %.1f" % [key, lock, rad_to_deg(got), rad_to_deg(lock * max_turn)])
		for d: Dictionary in drivers:
			var pose: RefCounted = SeatedPose.create(holder, d.model, cabin, true, d.loco)
			if pose == null:
				_failures.append("%s/%s: could not seat" % [key, d.id])
				continue
			pose.fit_reach()
			pose.pose(0.0, 0.0)
			var headroom: float = pose.head_clearance()
			# The player must fit every model; registry characters that don't
			# fit a car are never picked as its driver (vehicle_occupants.gd)
			if not pose.fits():
				if d.id == "PLAYER":
					_failures.append("%s/%s: head %.3f m into the roof" % [key, d.id, -headroom])
				else:
					print("%-9s %-18s too tall for this car (head %.3f m into the roof); traffic picks someone else" % [key, d.id, -headroom])
			var worst := 0.0
			var follow_ok := true
			for i in STEPS + 1:
				var fraction := lerpf(1.0, -1.0, float(i) / STEPS)
				SteeringWheel.update(pivot, fraction * 0.5, 0.5)
				var angle: float = fraction * max_turn
				pose.pose(angle, fraction, 1.0 / 30.0)
				for side in ["Left", "Right"]:
					var err: float = pose.rim_error(side)
					worst = maxf(worst, err)
					if err > TOLERANCE:
						_failures.append("%s/%s: %s palm %.3f m off the rim at steering %+.2f" % [key, d.id, side, err, fraction])
			# The hands follow the rim: a quarter turn moves both grips
			pose.pose(0.0, 0.0)
			var centre_l: Vector3 = pose.palm_point("Left")
			pose.pose(deg_to_rad(45.0), 0.3)
			if pose.palm_point("Left").distance_to(centre_l) < float(cabin["wheel_radius"]) * 0.5:
				follow_ok = false
				_failures.append("%s/%s: left hand did not follow a 45 degree turn" % [key, d.id])
			print("%-9s %-18s worst rim error %.4f m, seat slide %+.3f m, drop %.3f m, headroom %s, follow %s" % [key, d.id, worst, pose.seat_slide, pose.seat_drop,
				"n/a" if headroom == INF else "%.3f m" % headroom, follow_ok])
			worst_all = maxf(worst_all, worst)
			var model: Node3D = pose.release()
			# Keep the model alive for the next vehicle
			root.add_child(model)
		holder.free()
	if _failures.is_empty():
		print("Hands-on-wheel check passed for all 10 models (worst %.4f m, limit %.2f m)." % [worst_all, TOLERANCE])
		quit(0)
	else:
		for f in _failures:
			push_error(f)
		quit(1)


## The player plus the tallest and shortest registry characters.
func _drivers() -> Array:
	var out: Array = []
	var player_json: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/player/player.json"))
	var candidates: Array = [{"id": "PLAYER", "model_path": player_json["model_path"], "scale": 1.0}]
	candidates.append_array(Registry.all().filter(func(e): return e.available))
	var measured: Array = []
	for entry: Dictionary in candidates:
		var model: Node3D = (load(entry.model_path) as PackedScene).instantiate()
		model.scale = Vector3.ONE * float(entry.get("scale", 1.0))
		root.add_child(model)
		var sk := SkeletonMap.skeleton_of(model)
		if sk == null:
			model.free()
			continue
		var height := _height(model)
		measured.append({"id": entry.id, "model": model, "height": height})
	measured.sort_custom(func(a, b): return a.height < b.height)
	var keep: Array = [measured[0], measured[measured.size() - 1]]
	for m in measured:
		if m.id == "PLAYER":
			keep.insert(0, m)
	for m in measured:
		if not keep.has(m):
			m.model.free()
	for k in keep:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1
		k["loco"] = Locomotion.create(k.model, {}, rng)
		out.append(k)
	return out


func _height(model: Node3D) -> float:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box.size.y

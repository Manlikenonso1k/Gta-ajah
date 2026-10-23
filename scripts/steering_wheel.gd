extends RefCounted
## Turnable steering wheel for a car built by scripts/vehicle_model.gd.
##
## vehicle_model.gd cuts the steering-wheel triangles out of the body (or
## generates a low-poly wheel for models without one) and returns them in
## build()["steering_wheel"]. attach() mounts them on a pivot at the rim
## centre; update() turns the rim with the car's steering value.


## Adds the steering wheel to `car` and returns its pivot (null if the model
## has no cabin data).
static func attach(car: Node3D, data: Dictionary) -> Node3D:
	var sw: Dictionary = data.get("steering_wheel", {})
	if sw.is_empty() or sw["parts"].is_empty():
		return null
	var pivot := Node3D.new()
	pivot.name = "SteeringWheel"
	pivot.position = sw["center"]
	pivot.set_meta("axis", sw["axis"])
	pivot.set_meta("max_turn", sw["max_turn"])
	for part in sw["parts"]:
		var mesh := MeshInstance3D.new()
		mesh.mesh = part[0]
		mesh.transform = part[1]
		pivot.add_child(mesh)
	car.add_child(pivot)
	return pivot


## Turns the rim: full steering lock (`steering` == `max_steer`, radians, as
## VehicleBody3D.steering) gives the model's wheel_turn_deg. Positive steering
## is a left turn, which turns the rim anticlockwise as the driver sees it.
static func update(pivot: Node3D, steering: float, max_steer: float) -> void:
	if pivot == null:
		return
	var turn := clampf(steering / maxf(max_steer, 0.001), -1.0, 1.0) * float(pivot.get_meta("max_turn"))
	pivot.basis = Basis(pivot.get_meta("axis"), turn)


## Current rim angle in radians (positive = turned left).
static func angle(pivot: Node3D, steering: float, max_steer: float) -> float:
	return clampf(steering / maxf(max_steer, 0.001), -1.0, 1.0) * float(pivot.get_meta("max_turn"))

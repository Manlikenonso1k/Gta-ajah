extends CharacterBody3D
## Wandering pedestrian. Turns into a ragdoll when hit by a car.

const Ragdoll = preload("res://scripts/ragdoll.gd")

const SPEED := 1.4

var colors: Dictionary

var _direction := Vector3.FORWARD
var _turn_timer := 0.0
var _limbs: Dictionary
var _phase := 0.0


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	var visual := Node3D.new()
	add_child(visual)
	_limbs = Ragdoll.build_visual(visual, colors)
	_phase = randf() * TAU
	_pick_direction()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	_turn_timer -= delta
	if _turn_timer <= 0.0 or is_on_wall():
		_pick_direction()
	velocity.x = _direction.x * SPEED
	velocity.z = _direction.z * SPEED
	move_and_slide()
	rotation.y = lerp_angle(rotation.y, atan2(-_direction.x, -_direction.z), 6.0 * delta)
	_phase += SPEED * 2.2 * delta
	Ragdoll.animate(_limbs, _phase, 0.6)


func _pick_direction() -> void:
	_direction = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	_turn_timer = randf_range(3.0, 8.0)


func hit_by_vehicle(vehicle_velocity: Vector3) -> void:
	Ragdoll.spawn(get_parent(), global_transform, colors, vehicle_velocity * 0.8 + Vector3.UP * 3.0)
	queue_free()

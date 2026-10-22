extends CharacterBody3D
## On-foot player: walk/run/jump relative to the camera, enter cars,
## and go ragdoll (R key or hit by a car), getting back up after a few seconds.

const Ragdoll = preload("res://scripts/ragdoll.gd")

const WALK_SPEED := 3.0
const RUN_SPEED := 7.0
const JUMP_VELOCITY := 5.0
const ENTER_DISTANCE := 4.0
const RAGDOLL_TIME := 4.0

var camera_rig: Node3D
var colors := {"skin": Color(0.3, 0.18, 0.11), "shirt": Color(0.1, 0.45, 0.25), "pants": Color(0.2, 0.25, 0.4)}
var car: Node = null

var _limbs: Dictionary
var _phase := 0.0
var _ragdoll_pelvis: RigidBody3D = null
var _ragdoll_timer := 0.0
var _enter_cooldown := 0.0


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
	camera_rig.follow(self, 1.6)


func _physics_process(delta: float) -> void:
	_enter_cooldown -= delta
	if _ragdoll_pelvis != null:
		_ragdoll_timer -= delta
		if _ragdoll_timer <= 0.0 or not is_instance_valid(_ragdoll_pelvis):
			_get_up()
		return

	if not is_on_floor():
		velocity += get_gravity() * delta

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var forward := Vector3.FORWARD.rotated(Vector3.UP, camera_rig.yaw)
	var right := Vector3.RIGHT.rotated(Vector3.UP, camera_rig.yaw)
	var direction := (right * input.x - forward * input.y).normalized()
	var speed := RUN_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED

	velocity.x = move_toward(velocity.x, direction.x * speed, 30.0 * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, 30.0 * delta)
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	move_and_slide()

	if direction.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), 10.0 * delta)
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	_phase += ground_speed * 2.2 * delta
	Ragdoll.animate(_limbs, _phase, clampf(ground_speed / RUN_SPEED * 1.5, 0, 1))

	if Input.is_action_just_pressed("ragdoll"):
		go_ragdoll(velocity + Vector3.UP * 2.0)
	elif Input.is_action_just_pressed("interact") and _enter_cooldown <= 0.0:
		_try_enter_car()


func _try_enter_car() -> void:
	var nearest: Node3D = null
	for c in get_tree().get_nodes_in_group("cars"):
		var d := global_position.distance_to(c.global_position)
		if d < ENTER_DISTANCE and (nearest == null or d < global_position.distance_to(nearest.global_position)):
			nearest = c
	if nearest == null:
		return
	car = nearest
	_set_active(false)
	car.start_driving(self)
	camera_rig.follow(car, 1.4, true)


func exit_car(position_: Vector3) -> void:
	car = null
	global_position = position_
	velocity = Vector3.ZERO
	_enter_cooldown = 0.3
	_set_active(true)
	camera_rig.follow(self, 1.6)


func hit_by_vehicle(vehicle_velocity: Vector3) -> void:
	go_ragdoll(vehicle_velocity * 0.8 + Vector3.UP * 3.0)


func go_ragdoll(launch_velocity: Vector3) -> void:
	_ragdoll_pelvis = Ragdoll.spawn(get_parent(), global_transform, colors, launch_velocity)
	_ragdoll_timer = RAGDOLL_TIME
	visible = false
	collision_layer = 0
	collision_mask = 1
	camera_rig.follow(_ragdoll_pelvis, 0.6)


func _get_up() -> void:
	if is_instance_valid(_ragdoll_pelvis):
		global_position = Vector3(_ragdoll_pelvis.global_position.x, maxf(_ragdoll_pelvis.global_position.y, 0.1), _ragdoll_pelvis.global_position.z)
		_ragdoll_pelvis.get_parent().queue_free()
	_ragdoll_pelvis = null
	velocity = Vector3.ZERO
	visible = true
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	camera_rig.follow(self, 1.6)


func _set_active(active: bool) -> void:
	visible = active
	collision_layer = 4 if active else 0
	collision_mask = (1 | 2 | 4) if active else 0
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED

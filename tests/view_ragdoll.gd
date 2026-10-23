extends SceneTree
## Renders vehicles hitting realistic characters, 10 frames over 2 s each,
## saved as one contact sheet per hit (5 × 2 frames, left to right, top row
## first) plus the single frames:
##   godot --path . --script tests/view_ragdoll.gd
##   godot --path . --script tests/view_ragdoll.gd -- corolla PED_BA_M01
## Default: corolla (sedan), vw_t3 (danfo) and coach against PED_BA_M01
## (MPFB), PED_WH_SF01 (Renderpeople) and PED_BA_SF02 (Sketchfab Mixamo).
## Images go to user://ragdoll_views/.

const Car = preload("res://scripts/car.gd")
const Registry = preload("res://scripts/pedestrian_registry.gd")
const Walk = preload("res://scripts/humanoid_walk.gd")
const RealisticRagdoll = preload("res://scripts/realistic_ragdoll.gd")

const SPEED := 11.0
const FRAMES := 10
const FRAME_GAP := 12
const OUT := "user://ragdoll_views/"


class Victim extends CharacterBody3D:
	var model: Node3D
	var ragdoll: Node3D

	func _ready() -> void:
		collision_layer = 4
		collision_mask = 1
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.3
		capsule.height = 1.8
		shape.shape = capsule
		shape.position.y = 0.9
		add_child(shape)

	func hit_by_vehicle(vehicle_velocity: Vector3, impact_point := Vector3.INF, vehicle_mass := 1200.0) -> void:
		if ragdoll != null:
			return
		ragdoll = RealisticRagdoll.spawn(model, get_parent(), velocity, vehicle_velocity, impact_point, vehicle_mass)
		collision_layer = 0


func _initialize() -> void:
	create_timer(600.0).timeout.connect(func() -> void: print("TIMEOUT"); quit(1))
	_run.call_deferred()


func _run() -> void:
	var vehicles := ["corolla", "vw_t3", "coach"]
	var characters := ["PED_BA_M01", "PED_WH_SF01", "PED_BA_SF02"]
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2:
		vehicles = [args[0]]
		characters = [args[1]]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for vehicle: String in vehicles:
		for id: String in characters:
			await _shoot(vehicle, id)
	quit()


func _shoot(vehicle: String, id: String) -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.65, 0.75)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1, 1, 1)
	world.add_child(env)
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300, 1, 300)
	ground_shape.shape = box
	ground_shape.position.y = -0.5
	ground.add_child(ground_shape)
	var ground_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(300, 300)
	ground_mesh.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.32, 0.32, 0.3)
	ground_mesh.material_override = ground_material
	ground.add_child(ground_mesh)
	# Metre grid lines so throw distance can be judged
	for i in range(-5, 30, 5):
		var line := MeshInstance3D.new()
		var line_mesh := BoxMesh.new()
		line_mesh.size = Vector3(0.05, 0.01, 6)
		line.mesh = line_mesh
		line.position = Vector3(i, 0.005, 0)
		var line_material := StandardMaterial3D.new()
		line_material.albedo_color = Color(0.9, 0.85, 0.3)
		line.material_override = line_material
		ground.add_child(line)
	world.add_child(ground)

	var entry := Registry.by_id(id)
	var victim := Victim.new()
	victim.rotation.y = 0.0
	victim.velocity = Vector3(0, 0, -1.4)
	world.add_child(victim)
	var model: Node3D = load(entry.model_path).instantiate()
	model.scale = Vector3.ONE * float(entry.scale)
	model.rotation.y = PI
	victim.add_child(model)
	victim.model = model
	var walker = Walk.create(model)
	if walker != null:
		walker.pose(1.3, 1.0)

	var car := Car.new()
	car.model = vehicle
	world.add_child(car)
	# Car forward is +Z; drive along +X towards the victim
	var half_length := float(car.get("_half_length")) if car.get("_half_length") != null else 2.5
	car.global_transform = Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(-half_length - 7.0, 0.4, 0))

	var camera := Camera3D.new()
	world.add_child(camera)
	camera.fov = 55.0
	camera.look_at_from_position(Vector3(3.5, 2.2, 11.0), Vector3(3.5, 0.8, 0), Vector3.UP)

	var images := []
	var frame := 0
	var after_hit := -1
	while images.size() < FRAMES and frame < 600:
		if victim.ragdoll == null and car.linear_velocity.length() < SPEED:
			var forward := car.global_basis.z
			car.linear_velocity = forward * SPEED
		await physics_frame
		frame += 1
		if victim.ragdoll != null and after_hit < 0:
			after_hit = 0
			images.append(await _grab())
		elif after_hit >= 0:
			after_hit += 1
			if after_hit % FRAME_GAP == 0:
				images.append(await _grab())
	if victim.ragdoll == null:
		print("FAIL %s %s: no hit" % [vehicle, id])
	else:
		var pelvis: Vector3 = victim.ragdoll.pelvis.global_position
		print("%s %s: thrown to x=%.1f m, pelvis y %.2f, joint gap %.3f" % [vehicle, id, pelvis.x, pelvis.y, victim.ragdoll.joint_error()])
	if not images.is_empty():
		var first: Image = images[0]
		var w := first.get_width() / 2
		var h := first.get_height() / 2
		var sheet := Image.create(w * 5, h * 2, false, first.get_format())
		for i in images.size():
			var small: Image = images[i]
			small.resize(w, h)
			sheet.blit_rect(small, Rect2i(0, 0, w, h), Vector2i((i % 5) * w, (i / 5) * h))
		var path := ProjectSettings.globalize_path(OUT + "%s_%s.png" % [vehicle, id])
		sheet.save_png(path)
		print("saved ", path)
	world.queue_free()
	if is_instance_valid(victim.ragdoll):
		victim.ragdoll.queue_free()
	await process_frame


func _grab() -> Image:
	await process_frame
	await process_frame
	return root.get_texture().get_image()

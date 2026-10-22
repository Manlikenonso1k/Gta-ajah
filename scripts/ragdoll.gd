extends RefCounted
## Humanoid body shared by the player and pedestrians: an animated visual
## while alive, and a jointed rigid-body ragdoll when knocked down.
## Positions are in metres from the feet, character facing -Z.

const LAYER_RAGDOLL := 8
const MASK_RAGDOLL := 1 | 2 | 8
const MAX_RAGDOLLS := 25

# name: [shape, size, centre, mass, colour slot]
# box size = extents, capsule size = (radius, height), sphere size = (radius)
const PARTS := {
	"pelvis": ["box", Vector3(0.32, 0.22, 0.2), Vector3(0, 0.95, 0), 10.0, "pants"],
	"chest": ["box", Vector3(0.38, 0.42, 0.22), Vector3(0, 1.29, 0), 18.0, "shirt"],
	"head": ["sphere", Vector3(0.12, 0, 0), Vector3(0, 1.65, 0), 5.0, "skin"],
	"upper_arm_l": ["capsule", Vector3(0.055, 0.3, 0), Vector3(-0.26, 1.33, 0), 2.5, "shirt"],
	"lower_arm_l": ["capsule", Vector3(0.05, 0.28, 0), Vector3(-0.26, 1.05, 0), 2.0, "skin"],
	"upper_arm_r": ["capsule", Vector3(0.055, 0.3, 0), Vector3(0.26, 1.33, 0), 2.5, "shirt"],
	"lower_arm_r": ["capsule", Vector3(0.05, 0.28, 0), Vector3(0.26, 1.05, 0), 2.0, "skin"],
	"upper_leg_l": ["capsule", Vector3(0.075, 0.42, 0), Vector3(-0.1, 0.63, 0), 8.0, "pants"],
	"lower_leg_l": ["capsule", Vector3(0.065, 0.42, 0), Vector3(-0.1, 0.22, 0), 5.0, "pants"],
	"upper_leg_r": ["capsule", Vector3(0.075, 0.42, 0), Vector3(0.1, 0.63, 0), 8.0, "pants"],
	"lower_leg_r": ["capsule", Vector3(0.065, 0.42, 0), Vector3(0.1, 0.22, 0), 5.0, "pants"],
}

# Limb pivots used to swing arms and legs while walking.
const LIMBS := {
	"arm_l": [Vector3(-0.26, 1.47, 0), ["upper_arm_l", "lower_arm_l"]],
	"arm_r": [Vector3(0.26, 1.47, 0), ["upper_arm_r", "lower_arm_r"]],
	"leg_l": [Vector3(-0.1, 0.84, 0), ["upper_leg_l", "lower_leg_l"]],
	"leg_r": [Vector3(0.1, 0.84, 0), ["upper_leg_r", "lower_leg_r"]],
}

# [type, body a, body b, pivot, axis, limit a (deg), limit b (deg)]
# cone: axis = cone direction, limits = swing span, twist span
# hinge: axis = hinge axis, limits = lower, upper
const JOINTS := [
	["cone", "pelvis", "chest", Vector3(0, 1.08, 0), Vector3.UP, 25.0, 20.0],
	["cone", "chest", "head", Vector3(0, 1.52, 0), Vector3.UP, 35.0, 40.0],
	["cone", "chest", "upper_arm_l", Vector3(-0.26, 1.47, 0), Vector3.DOWN, 80.0, 40.0],
	["cone", "chest", "upper_arm_r", Vector3(0.26, 1.47, 0), Vector3.DOWN, 80.0, 40.0],
	["hinge", "upper_arm_l", "lower_arm_l", Vector3(-0.26, 1.19, 0), Vector3.RIGHT, 0.0, 140.0],
	["hinge", "upper_arm_r", "lower_arm_r", Vector3(0.26, 1.19, 0), Vector3.RIGHT, 0.0, 140.0],
	["cone", "pelvis", "upper_leg_l", Vector3(-0.1, 0.84, 0), Vector3.DOWN, 50.0, 20.0],
	["cone", "pelvis", "upper_leg_r", Vector3(0.1, 0.84, 0), Vector3.DOWN, 50.0, 20.0],
	["hinge", "upper_leg_l", "lower_leg_l", Vector3(-0.1, 0.43, 0), Vector3.RIGHT, -130.0, 0.0],
	["hinge", "upper_leg_r", "lower_leg_r", Vector3(0.1, 0.43, 0), Vector3.RIGHT, -130.0, 0.0],
]

static var _materials := {}


static func material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.8
		_materials[color] = mat
	return _materials[color]


static func random_colors(rng: RandomNumberGenerator) -> Dictionary:
	var skins := [Color(0.24, 0.14, 0.09), Color(0.33, 0.2, 0.12), Color(0.42, 0.27, 0.17)]
	var shirts := [Color(0.85, 0.85, 0.82), Color(0.1, 0.45, 0.25), Color(0.7, 0.15, 0.12),
		Color(0.15, 0.25, 0.6), Color(0.9, 0.7, 0.2), Color(0.5, 0.2, 0.5)]
	var pants := [Color(0.12, 0.12, 0.14), Color(0.2, 0.25, 0.4), Color(0.45, 0.38, 0.28)]
	return {
		"skin": skins[rng.randi() % skins.size()],
		"shirt": shirts[rng.randi() % shirts.size()],
		"pants": pants[rng.randi() % pants.size()],
	}


static func _mesh(def: Array) -> Mesh:
	var size: Vector3 = def[1]
	match def[0]:
		"box":
			var box := BoxMesh.new()
			box.size = size
			return box
		"capsule":
			var cap := CapsuleMesh.new()
			cap.radius = size.x
			cap.height = size.y
			return cap
		_:
			var sphere := SphereMesh.new()
			sphere.radius = size.x
			sphere.height = size.x * 2.0
			return sphere


static func _shape(def: Array) -> Shape3D:
	var size: Vector3 = def[1]
	match def[0]:
		"box":
			var box := BoxShape3D.new()
			box.size = size
			return box
		"capsule":
			var cap := CapsuleShape3D.new()
			cap.radius = size.x
			cap.height = size.y
			return cap
		_:
			var sphere := SphereShape3D.new()
			sphere.radius = size.x
			return sphere


## Adds body meshes under `parent` and returns the limb pivots for animate().
static func build_visual(parent: Node3D, colors: Dictionary) -> Dictionary:
	var limbs := {}
	var limb_parts := {}
	for limb in LIMBS:
		var pivot := Node3D.new()
		pivot.position = LIMBS[limb][0]
		parent.add_child(pivot)
		limbs[limb] = pivot
		for part in LIMBS[limb][1]:
			limb_parts[part] = pivot
	for part in PARTS:
		var def: Array = PARTS[part]
		var mesh := MeshInstance3D.new()
		mesh.mesh = _mesh(def)
		mesh.material_override = material(colors[def[4]])
		var holder: Node3D = limb_parts.get(part, parent)
		holder.add_child(mesh)
		mesh.position = def[2] - (holder.position if holder != parent else Vector3.ZERO)
	return limbs


## Swings arms and legs; `amount` 0 = standing, 1 = full stride.
static func animate(limbs: Dictionary, phase: float, amount: float) -> void:
	var swing := sin(phase) * 0.6 * amount
	limbs["arm_l"].rotation.x = swing
	limbs["arm_r"].rotation.x = -swing
	limbs["leg_l"].rotation.x = -swing
	limbs["leg_r"].rotation.x = swing


## Spawns a physics ragdoll matching a character at `xform` and returns its pelvis.
static func spawn(parent: Node, xform: Transform3D, colors: Dictionary, velocity: Vector3) -> RigidBody3D:
	var old := parent.get_tree().get_nodes_in_group("ragdolls")
	if old.size() >= MAX_RAGDOLLS:
		old[0].queue_free()

	var root := Node3D.new()
	root.add_to_group("ragdolls")
	parent.add_child(root)
	root.global_transform = xform

	var bodies := {}
	for part in PARTS:
		var def: Array = PARTS[part]
		var body := RigidBody3D.new()
		body.mass = def[3]
		body.collision_layer = LAYER_RAGDOLL
		body.collision_mask = MASK_RAGDOLL
		body.angular_damp = 0.8
		body.position = def[2]
		var shape := CollisionShape3D.new()
		shape.shape = _shape(def)
		body.add_child(shape)
		var mesh := MeshInstance3D.new()
		mesh.mesh = _mesh(def)
		mesh.material_override = material(colors[def[4]])
		body.add_child(mesh)
		root.add_child(body)
		body.linear_velocity = velocity
		body.angular_velocity = Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2))
		bodies[part] = body

	for j in JOINTS:
		var joint: Joint3D
		if j[0] == "cone":
			var cone := ConeTwistJoint3D.new()
			cone.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(j[5]))
			cone.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(j[6]))
			cone.transform = Transform3D(Basis(Quaternion(Vector3.RIGHT, j[4])), j[3])
			joint = cone
		else:
			var hinge := HingeJoint3D.new()
			hinge.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
			hinge.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(j[5]))
			hinge.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(j[6]))
			hinge.transform = Transform3D(Basis(Quaternion(Vector3.BACK, j[4])), j[3])
			joint = hinge
		root.add_child(joint)
		joint.node_a = joint.get_path_to(bodies[j[1]])
		joint.node_b = joint.get_path_to(bodies[j[2]])

	return bodies["pelvis"]

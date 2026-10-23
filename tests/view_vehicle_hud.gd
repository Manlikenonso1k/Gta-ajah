extends SceneTree
## Capture sample vehicle HUDs. Run with a window, not --headless:
## godot --path . --script tests/view_vehicle_hud.gd

const VehicleHud = preload("res://scripts/vehicle_hud.gd")

class FakeCar:
	extends Node
	var model := "camry"
	var linear_velocity := Vector3(0, 0, 20)
	var estimated_rpm := 3200.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var output := "user://vehicle_views/hud_"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://vehicle_views"))
	var hud := Control.new()
	hud.set_script(VehicleHud)
	root.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var car := FakeCar.new()
	root.add_child(car)
	hud.set_vehicle(car)
	for model in ["camry", "benz_g", "bmw_e30", "vw_t3"]:
		car.model = model
		car.linear_velocity = Vector3(0, 0, 23)
		car.estimated_rpm = 3900.0
		hud.queue_redraw()
		for frame in 4:
			await process_frame
		var filename: String = output + model + ".png"
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(filename))
		print("saved HUD: ", ProjectSettings.globalize_path(filename))
	quit()

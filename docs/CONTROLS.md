# Controls and settings

Open the in-game phone (**MENU** button, or Esc / Back), then **Controls & settings**.
Everything is saved on the device in `user://controls.json`
(`scripts/control_settings.gd`).

## Phones and tablets

| Setting | What it does |
|---|---|
| **Steering** | *Joystick* (as before) or *Tilt*: in a car, turn the phone like a steering wheel. The joystick is replaced by **GAS** (green) and **BRAKE** (red) pedals. Brake also reverses, and the handbrake stays on the Jump button. |
| **Tilt sensitivity / Reverse tilt direction** | Use the live **Tilt test** bar to check that tilting right shows "steering RIGHT". If it's backwards on your phone, turn on Reverse. |
| **Gyroscope camera** | Turn the phone to aim the camera, like the gyroscope option in mobile shooters. Dragging still works. It is paused while you tilt-steer, because the phone is then the wheel. Each direction can be reversed separately. |
| **See-through** | How transparent the on-screen buttons are. |
| **Move & resize buttons** | Drag any button or the joystick to a new spot. Tap one, then use **SIZE**. **SHOW: ON FOOT / IN CAR** switches between the walking layout and the driving layout (the pedals). **RESET** restores the default layout. |
| **Look sensitivity** | How fast a drag (or the mouse on a computer) turns the camera. |

The joystick still floats: a thumb anywhere on its side of the screen takes it,
centred where it lands.

## Computers

Keyboard and mouse are unchanged (see the phone menu's quick guide). The settings
screen offers look sensitivity only. The phone rows are hidden when there's no
touchscreen.

## For developers

- `scripts/touch_controls.gd`: elements, edit mode (`edit_mode`, `edit_view`,
  `set_element`), tilt (`tilt_amount`) and gyroscope camera. The project enables
  the accelerometer, gravity and gyroscope sensors (`input_devices/sensors/*`
  in `project.godot`).
- `scripts/controls_editor.gd`: the toolbar used while moving buttons.
- `scripts/settings_menu.gd`: the settings screen.
- Tests: `tests/controls_test.gd` (headless; it uses its own settings file).
  `tests/view_controls.gd -- --touch` saves screenshots of the HUD, the settings
  screen and the layout editor.

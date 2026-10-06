## Player ship controller — participates in the same simulation state.
class_name PlayerController
extends Node

signal mode_changed(observe: bool)

var sim: StarSystemSim
var ship: Dictionary = {}
var observe_mode: bool = true
var camera: Camera3D
var yaw: float = 0.0
var pitch: float = 0.0
var mouse_sensitivity: float = 0.0025
var thrust: float = 90.0
var observe_distance: float = 900.0
var observe_yaw: float = 0.4
var observe_pitch: float = -0.35
var _capture_mouse: bool = false


func setup(p_sim: StarSystemSim, p_camera: Camera3D) -> void:
	sim = p_sim
	camera = p_camera
	# Reuse first ship as player vessel, or spawn dedicated one.
	if sim.world["ships"].is_empty():
		return
	ship = sim.world["ships"][0]
	ship["is_player"] = true
	ship["ship_class"] = SimEntities.ShipClass.TRADER
	ship["speed"] = 95.0
	ship["cargo_capacity"] = 80.0
	ship["credits"] = 2500.0
	ship["activity"] = SimEntities.Activity.IDLE
	ship["job"] = {}
	ship["docked_station_id"] = -1
	_place_near_station()


func _place_near_station() -> void:
	if sim.world["stations"].is_empty():
		return
	var st: Dictionary = sim.world["stations"][0]
	ship["position"] = st["position"] + Vector3(80, 40, 80)
	ship["heading"] = Vector3(0, 0, -1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1:
				observe_mode = not observe_mode
				mode_changed.emit(observe_mode)
				_capture_mouse = not observe_mode
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _capture_mouse else Input.MOUSE_MODE_VISIBLE
			KEY_ESCAPE:
				_capture_mouse = false
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_F2:
				_try_dock_trade()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not observe_mode:
			_capture_mouse = true
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and _capture_mouse and not observe_mode:
		yaw -= event.relative.x * mouse_sensitivity
		pitch = clampf(pitch - event.relative.y * mouse_sensitivity, -1.2, 1.2)


func _process(dt: float) -> void:
	if ship.is_empty() or camera == null:
		return
	if observe_mode:
		_update_observe_camera(dt)
	else:
		_update_flight(dt)
		_update_chase_camera()


func _update_observe_camera(dt: float) -> void:
	# Orbit the star / system center, optionally follow mouse drag via arrows.
	if Input.is_action_pressed("ui_left"):
		observe_yaw -= dt * 0.7
	if Input.is_action_pressed("ui_right"):
		observe_yaw += dt * 0.7
	if Input.is_action_pressed("ui_up"):
		observe_pitch = clampf(observe_pitch - dt * 0.5, -1.2, 0.2)
	if Input.is_action_pressed("ui_down"):
		observe_pitch = clampf(observe_pitch + dt * 0.5, -1.2, 0.2)
	if Input.is_physical_key_pressed(KEY_EQUAL) or Input.is_physical_key_pressed(KEY_KP_ADD):
		observe_distance = maxf(200.0, observe_distance - dt * 400.0)
	if Input.is_physical_key_pressed(KEY_MINUS) or Input.is_physical_key_pressed(KEY_KP_SUBTRACT):
		observe_distance = minf(5000.0, observe_distance + dt * 400.0)

	var focus := Vector3.ZERO
	# Soft focus on densest activity: average of first 32 ships.
	var ships: Array = sim.world["ships"]
	var n := mini(32, ships.size())
	if n > 0:
		var acc := Vector3.ZERO
		for i in n:
			acc += ships[i]["position"]
		focus = acc / float(n)

	var cp := cos(observe_pitch)
	var offset := Vector3(
		sin(observe_yaw) * cp,
		sin(observe_pitch),
		cos(observe_yaw) * cp
	) * observe_distance
	camera.global_position = focus + offset
	camera.look_at(focus, Vector3.UP)


func _update_flight(dt: float) -> void:
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var forward := -basis.z
	var right := basis.x
	var up := basis.y
	ship["heading"] = forward

	var wish := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		wish += forward
	if Input.is_physical_key_pressed(KEY_S):
		wish -= forward
	if Input.is_physical_key_pressed(KEY_D):
		wish += right
	if Input.is_physical_key_pressed(KEY_A):
		wish -= right
	if Input.is_physical_key_pressed(KEY_SPACE):
		wish += up
	if Input.is_physical_key_pressed(KEY_C):
		wish -= up

	var vel: Vector3 = ship["velocity"]
	if wish.length_squared() > 0.001:
		wish = wish.normalized()
		vel = vel.lerp(wish * thrust, clampf(dt * 2.5, 0.0, 1.0))
	else:
		vel = vel.lerp(Vector3.ZERO, clampf(dt * 0.8, 0.0, 1.0))
	ship["velocity"] = vel
	ship["position"] = ship["position"] + vel * dt
	ship["docked_station_id"] = -1
	ship["activity"] = SimEntities.Activity.TRAVEL if vel.length() > 1.0 else SimEntities.Activity.IDLE


func _update_chase_camera() -> void:
	var heading: Vector3 = ship["heading"]
	if heading.length_squared() < 0.001:
		heading = Vector3(0, 0, -1)
	var back := -heading.normalized() * 28.0 + Vector3.UP * 10.0
	camera.global_position = ship["position"] + back
	camera.look_at(ship["position"] + heading * 40.0, Vector3.UP)


func _try_dock_trade() -> void:
	if observe_mode or ship.is_empty():
		return
	var st := sim.find_nearest_station(ship["position"])
	if st.is_empty():
		return
	if ship["position"].distance_to(st["position"]) > 120.0:
		return
	# Sell all cargo, buy a bit of whatever is cheapest relative to base.
	for item in Commodities.ALL:
		sim.economy.sell_to_station(sim.world, ship, st, item)
	var best_item := ""
	var best_score := INF
	for item in Commodities.ALL:
		var price := SimEntities.station_sell_price(st, item)
		var score := price / Commodities.base_price_of(item)
		if score < best_score:
			best_score = score
			best_item = item
	if best_item != "":
		var want := SimEntities.cargo_free(ship) / Commodities.mass_of(best_item)
		sim.economy.buy_from_station(sim.world, ship, st, best_item, want * 0.5)
	ship["position"] = st["position"] + Vector3(60, 20, 0)

## Goal-oriented ship AI: sample economy jobs (LT Think) and execute action steps.
class_name ShipAI
extends RefCounted

var rng: SeededRNG
var economy: EconomySystem


func _init(p_economy: EconomySystem, p_rng: SeededRNG) -> void:
	economy = p_economy
	rng = p_rng


func tick_ship(world: Dictionary, ship: Dictionary, dt: float) -> void:
	if ship.get("is_player", false):
		return
	if int(ship["ship_class"]) == SimEntities.ShipClass.PATROL:
		_tick_patrol(world, ship, dt)
		return

	match int(ship["activity"]):
		SimEntities.Activity.IDLE:
			_think(world, ship)
		SimEntities.Activity.TRAVEL:
			_travel(world, ship, dt)
		SimEntities.Activity.MINE:
			_mine(world, ship, dt)
		SimEntities.Activity.DOCK:
			_dock(world, ship, dt)
		SimEntities.Activity.TRADE:
			_trade(world, ship, dt)
		SimEntities.Activity.UNDOCK:
			_undock(world, ship, dt)


func _think(world: Dictionary, ship: Dictionary) -> void:
	var job := economy.sample_best_job(ship, rng)
	if job.is_empty():
		return
	ship["job"] = job
	if job["type"] == "mine":
		ship["target_id"] = int(job["src_id"])
		ship["target_kind"] = "yield"
		ship["activity"] = SimEntities.Activity.TRAVEL
	elif job["type"] == "transport":
		ship["target_id"] = int(job["src_id"])
		ship["target_kind"] = "station"
		ship["activity"] = SimEntities.Activity.TRAVEL


func _travel(world: Dictionary, ship: Dictionary, dt: float) -> void:
	var target_pos: Variant = target_position(world, ship)
	if typeof(target_pos) != TYPE_VECTOR3:
		ship["activity"] = SimEntities.Activity.IDLE
		ship["job"] = {}
		return
	var pos: Vector3 = ship["position"]
	var dest: Vector3 = target_pos
	var to: Vector3 = dest - pos
	var dist: float = to.length()
	var arrive: float = arrive_radius(ship)
	if dist <= arrive:
		on_arrive(world, ship)
		return
	var dir: Vector3 = to / dist
	ship["heading"] = dir
	var speed: float = float(ship["speed"])
	var step: float = minf(dist - arrive * 0.5, speed * dt)
	ship["position"] = pos + dir * step
	ship["velocity"] = dir * speed


func arrive_radius(ship: Dictionary) -> float:
	return 35.0 if ship["target_kind"] == "station" else 45.0


func target_position(world: Dictionary, ship: Dictionary) -> Variant:
	return _target_position(world, ship)


func on_arrive(world: Dictionary, ship: Dictionary) -> void:
	_on_arrive(world, ship)


func _on_arrive(world: Dictionary, ship: Dictionary) -> void:
	var job: Dictionary = ship.get("job", {})
	if job.is_empty():
		ship["activity"] = SimEntities.Activity.IDLE
		return
	if job["type"] == "mine":
		if ship["target_kind"] == "yield":
			ship["activity"] = SimEntities.Activity.MINE
			ship["action_timer"] = 0.0
		elif ship["target_kind"] == "station":
			ship["activity"] = SimEntities.Activity.DOCK
			ship["action_timer"] = 0.6
	elif job["type"] == "transport":
		ship["activity"] = SimEntities.Activity.DOCK
		ship["action_timer"] = 0.6


func _mine(world: Dictionary, ship: Dictionary, dt: float) -> void:
	var y := economy.find_yield(world, int(ship["target_id"]))
	if y.is_empty() or float(y["remaining"]) <= 0.0:
		ship["activity"] = SimEntities.Activity.IDLE
		ship["job"] = {}
		return
	var free := SimEntities.cargo_free(ship)
	if free < Commodities.mass_of(Commodities.ORE):
		# Full — deliver to destination station.
		var job: Dictionary = ship["job"]
		ship["target_id"] = int(job["dst_id"])
		ship["target_kind"] = "station"
		ship["activity"] = SimEntities.Activity.TRAVEL
		return
	var rate: float = float(ship["mine_rate"]) * float(y["richness"]) * dt
	var extracted := minf(rate, float(y["remaining"]))
	var taken := SimEntities.add_cargo(ship, Commodities.ORE, extracted)
	y["remaining"] = float(y["remaining"]) - taken
	if taken <= 0.0:
		var job2: Dictionary = ship["job"]
		ship["target_id"] = int(job2["dst_id"])
		ship["target_kind"] = "station"
		ship["activity"] = SimEntities.Activity.TRAVEL


func _dock(world: Dictionary, ship: Dictionary, dt: float) -> void:
	ship["action_timer"] = float(ship["action_timer"]) - dt
	if float(ship["action_timer"]) > 0.0:
		return
	var st := economy.find_station(world, int(ship["target_id"]))
	if st.is_empty():
		ship["activity"] = SimEntities.Activity.IDLE
		return
	ship["docked_station_id"] = int(st["id"])
	ship["position"] = st["position"] + Vector3(0, 8, 0)
	ship["velocity"] = Vector3.ZERO
	ship["activity"] = SimEntities.Activity.TRADE
	ship["action_timer"] = 0.2


func _trade(world: Dictionary, ship: Dictionary, dt: float) -> void:
	ship["action_timer"] = float(ship["action_timer"]) - dt
	if float(ship["action_timer"]) > 0.0:
		return
	var st := economy.find_station(world, int(ship["docked_station_id"]))
	var job: Dictionary = ship.get("job", {})
	if st.is_empty() or job.is_empty():
		ship["activity"] = SimEntities.Activity.UNDOCK
		return

	if job["type"] == "mine":
		economy.sell_to_station(world, ship, st, Commodities.ORE)
		ship["activity"] = SimEntities.Activity.UNDOCK
		ship["action_timer"] = 0.4
		ship["job"] = {}
		return

	if job["type"] == "transport":
		var item: String = str(job["item"])
		if int(ship["target_id"]) == int(job["src_id"]) and SimEntities.cargo_used(ship) < 1.0:
			# Buy at source.
			var want := SimEntities.cargo_free(ship) / Commodities.mass_of(item)
			economy.buy_from_station(world, ship, st, item, want)
			ship["docked_station_id"] = -1
			ship["target_id"] = int(job["dst_id"])
			ship["target_kind"] = "station"
			ship["activity"] = SimEntities.Activity.TRAVEL
			return
		# Sell at destination.
		economy.sell_to_station(world, ship, st, item)
		ship["activity"] = SimEntities.Activity.UNDOCK
		ship["action_timer"] = 0.4
		ship["job"] = {}


func _undock(world: Dictionary, ship: Dictionary, dt: float) -> void:
	ship["action_timer"] = float(ship["action_timer"]) - dt
	if float(ship["action_timer"]) > 0.0:
		return
	var sid: int = int(ship["docked_station_id"])
	if sid >= 0:
		var st := economy.find_station(world, sid)
		if not st.is_empty():
			var away := rng.dir2() * 50.0
			ship["position"] = st["position"] + away + Vector3(0, 10, 0)
	ship["docked_station_id"] = -1
	ship["activity"] = SimEntities.Activity.IDLE
	ship["velocity"] = Vector3.ZERO


func _tick_patrol(world: Dictionary, ship: Dictionary, dt: float) -> void:
	if ship["activity"] != SimEntities.Activity.TRAVEL or ship["target_id"] < 0:
		var st: Dictionary = rng.choose(world["stations"])
		ship["target_id"] = int(st["id"])
		ship["target_kind"] = "station"
		ship["activity"] = SimEntities.Activity.TRAVEL
	_travel(world, ship, dt)
	if ship["activity"] != SimEntities.Activity.TRAVEL:
		# Arrived — pick a new patrol point after a short linger.
		ship["activity"] = SimEntities.Activity.IDLE
		ship["action_timer"] = 1.0
	if float(ship.get("action_timer", 0.0)) > 0.0:
		ship["action_timer"] = float(ship["action_timer"]) - dt
		if float(ship["action_timer"]) <= 0.0:
			ship["target_id"] = -1


func _target_position(world: Dictionary, ship: Dictionary) -> Variant:
	if ship["target_kind"] == "station":
		var st := economy.find_station(world, int(ship["target_id"]))
		if st.is_empty():
			return null
		return st["position"]
	if ship["target_kind"] == "yield":
		var y := economy.find_yield(world, int(ship["target_id"]))
		if y.is_empty():
			return null
		return y["position"]
	return null

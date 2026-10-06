## Headless-capable star-system simulation (data only — no Nodes).
class_name StarSystemSim
extends RefCounted

signal economy_updated(metrics: Dictionary)

var world: Dictionary = {}
var economy: EconomySystem = EconomySystem.new()
var ai: ShipAI
var rng: SeededRNG
var seed_value: int = 42

# Perf instrumentation
var perf: Dictionary = {
	"sim_ms": 0.0,
	"economy_ms": 0.0,
	"ai_ms": 0.0,
	"ships_total": 0,
	"ships_active": 0,
	"ships_mining": 0,
	"ships_trading": 0,
	"ships_idle": 0,
}

var _ai_cursor: int = 0
var _ship_batch: int = 120


func generate(p_seed: int = 42, ship_count: int = 400) -> void:
	seed_value = p_seed
	rng = SeededRNG.new(SeededRNG.combine_seeds(p_seed, 991))
	var gen := SystemGenerator.new(p_seed)
	world = gen.generate(ship_count)
	ai = ShipAI.new(economy, SeededRNG.new(SeededRNG.combine_seeds(p_seed, 777)))
	economy.last_refresh_time = -999.0
	economy.tick(world, 0.0)


func tick(dt: float) -> void:
	if world.is_empty():
		return
	var t0 := Time.get_ticks_usec()

	world["sim_time"] = float(world["sim_time"]) + dt
	world["tick"] = int(world["tick"]) + 1

	var t_econ := Time.get_ticks_usec()
	economy.tick(world, dt)
	perf["economy_ms"] = float(Time.get_ticks_usec() - t_econ) / 1000.0

	var t_ai := Time.get_ticks_usec()
	_tick_ships(dt)
	perf["ai_ms"] = float(Time.get_ticks_usec() - t_ai) / 1000.0

	perf["sim_ms"] = float(Time.get_ticks_usec() - t0) / 1000.0
	perf["ships_total"] = world["ships"].size()
	if int(world["tick"]) % 30 == 0:
		economy_updated.emit(economy.metrics)


func _tick_ships(dt: float) -> void:
	var ships: Array = world["ships"]
	var n := ships.size()
	if n == 0:
		return
	# Update all ships for movement correctness; stagger is optional later.
	var active := 0
	var mining := 0
	var trading := 0
	var idle := 0
	for ship in ships:
		ai.tick_ship(world, ship, dt)
		var act: int = int(ship["activity"])
		if act == SimEntities.Activity.IDLE:
			idle += 1
		else:
			active += 1
		if act == SimEntities.Activity.MINE:
			mining += 1
		if act == SimEntities.Activity.TRADE or act == SimEntities.Activity.DOCK:
			trading += 1
	perf["ships_active"] = active
	perf["ships_mining"] = mining
	perf["ships_trading"] = trading
	perf["ships_idle"] = idle


func get_ship(id: int) -> Dictionary:
	for s in world["ships"]:
		if int(s["id"]) == id:
			return s
	return {}


func find_nearest_station(pos: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for st in world["stations"]:
		var d: float = pos.distance_squared_to(st["position"])
		if d < best_d:
			best_d = d
			best = st
	return best


func snapshot_hash() -> int:
	# Lightweight determinism fingerprint for tests.
	var h := seed_value
	h = hash(str(h) + str(world.get("tick", 0)))
	if world.has("stations") and not world["stations"].is_empty():
		var st: Dictionary = world["stations"][0]
		h = hash(str(h) + str(st["inventory"]))
	if world.has("ships") and not world["ships"].is_empty():
		var sh: Dictionary = world["ships"][0]
		h = hash(str(h) + str(sh["position"]) + str(sh["activity"]))
	return h

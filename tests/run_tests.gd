## Headless test runner — no rendering required.
## Usage: godot --headless --path . -s res://tests/run_tests.gd
extends SceneTree

var _failed: int = 0
var _passed: int = 0


func _init() -> void:
	print("=== Limit Theory Prototype Tests ===")
	_test_seeded_rng()
	_test_system_determinism()
	_test_economy_runs()
	_test_ships_become_active()
	_test_prices_respond_to_supply()
	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("PASS  ", name)
	else:
		_failed += 1
		print("FAIL  ", name, "  ", detail)


func _test_seeded_rng() -> void:
	var a := SeededRNG.new(123)
	var b := SeededRNG.new(123)
	var same := true
	for _i in 50:
		if not is_equal_approx(a.randf(), b.randf()):
			same = false
			break
	_ok("SeededRNG identical sequences", same)
	var c := SeededRNG.new(999)
	_ok("SeededRNG different seeds diverge", not is_equal_approx(SeededRNG.new(123).randf(), c.randf()))


func _test_system_determinism() -> void:
	var g1 := SystemGenerator.new(42)
	var g2 := SystemGenerator.new(42)
	var w1 := g1.generate(50)
	var w2 := g2.generate(50)
	_ok("Same seed → same planet count", w1["planets"].size() == w2["planets"].size())
	_ok("Same seed → same station count", w1["stations"].size() == w2["stations"].size())
	_ok("Same seed → same system name", w1["name"] == w2["name"])
	var p1: Vector3 = w1["planets"][0]["position"]
	var p2: Vector3 = w2["planets"][0]["position"]
	_ok("Same seed → same first planet position", p1.is_equal_approx(p2))

	var g3 := SystemGenerator.new(99)
	var w3 := g3.generate(50)
	_ok("Different seed → different name or layout", w3["name"] != w1["name"] or not w3["planets"][0]["position"].is_equal_approx(p1))


func _test_economy_runs() -> void:
	var sim := StarSystemSim.new()
	sim.generate(7, 80)
	var cycles0: int = int(sim.economy.metrics.get("production_cycles", 0))
	for _i in 120:
		sim.tick(0.25)
	var cycles1: int = int(sim.economy.metrics.get("production_cycles", 0))
	_ok("Factories produce over time", cycles1 > cycles0)
	_ok("Job board non-empty", int(sim.economy.metrics.get("job_count", 0)) > 0)
	_ok("Avg prices present", sim.economy.metrics.get("avg_prices", {}).has(Commodities.ORE))


func _test_ships_become_active() -> void:
	var sim := StarSystemSim.new()
	sim.generate(11, 200)
	var ever_active := false
	var ever_mining := false
	var ever_trade := false
	for _i in 600:
		sim.tick(0.25)
		if int(sim.perf.get("ships_active", 0)) > 10:
			ever_active = true
		if int(sim.perf.get("ships_mining", 0)) > 0:
			ever_mining = true
		if int(sim.economy.metrics.get("transactions", 0)) > 0:
			ever_trade = true
		if ever_active and ever_mining and ever_trade:
			break
	_ok("Ships leave idle for work", ever_active)
	_ok("Some ships mine", ever_mining)
	_ok("Transactions occur", ever_trade)


func _test_prices_respond_to_supply() -> void:
	var sim := StarSystemSim.new()
	sim.generate(13, 100)
	# Snapshot ore price, drain ore from all stations, tick prices.
	for st in sim.world["stations"]:
		st["inventory"][Commodities.ORE] = 2.0
	for _i in 20:
		sim.economy._update_prices(sim.world)
	var scarce: float = float(sim.world["stations"][0]["prices"][Commodities.ORE])
	for st in sim.world["stations"]:
		st["inventory"][Commodities.ORE] = 400.0
	for _i in 20:
		sim.economy._update_prices(sim.world)
	var glut: float = float(sim.world["stations"][0]["prices"][Commodities.ORE])
	_ok("Scarce ore priced higher than glut", scarce > glut)

	# Determinism of sim ticks
	var a := StarSystemSim.new()
	var b := StarSystemSim.new()
	a.generate(55, 60)
	b.generate(55, 60)
	for _i in 40:
		a.tick(0.1)
		b.tick(0.1)
	_ok("Parallel sims stay in sync", a.snapshot_hash() == b.snapshot_hash())

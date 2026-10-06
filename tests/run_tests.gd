## Headless test runner — no rendering required.
## Usage: godot --headless --path . -s res://tests/run_tests.gd
extends SceneTree

var _failed: int = 0
var _passed: int = 0


func _init() -> void:
	print("=== Limit Theory Prototype Tests ===")
	_test_seeded_rng()
	_test_seed_hash()
	_test_system_determinism()
	_test_hierarchical_independence()
	_test_visual_metadata()
	_test_mesh_generators()
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


func _test_seed_hash() -> void:
	var a := SeedHash.derive(42, "planet:0")
	var b := SeedHash.derive(42, "planet:0")
	var c := SeedHash.derive(42, "planet:1")
	_ok("SeedHash stable", a == b and a != 0)
	_ok("SeedHash differs by tag", a != c)
	_ok("SeedHash differs by parent", SeedHash.derive(42, "star") != SeedHash.derive(99, "star"))


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
	_ok("Same seed → same planet class", w1["planets"][0]["planet_class"] == w2["planets"][0]["planet_class"])
	_ok("Same seed → same star type", w1["star"]["star_type"] == w2["star"]["star_type"])

	var g3 := SystemGenerator.new(99)
	var w3 := g3.generate(50)
	_ok("Different seed → different name or layout", w3["name"] != w1["name"] or not w3["planets"][0]["position"].is_equal_approx(p1))


func _test_hierarchical_independence() -> void:
	# Planet seeds are derived from index tags — changing how we *use* planet 1's
	# RNG must not change planet 0's stored seed identity.
	var w := SystemGenerator.new(42).generate(20)
	var s0: int = int(w["planets"][0]["seed"])
	var s1: int = int(w["planets"][1]["seed"])
	_ok("Planet seeds differ", s0 != s1)
	_ok("Planet seed matches SeedHash", s0 == SeedHash.derive_i(42, "planet", 0))
	_ok("Station seed matches SeedHash", int(w["stations"][0]["seed"]) == SeedHash.derive_i(42, "station", 0))
	# Regenerating planet content from child seed alone is stable
	var a := SeededRNG.new(s0)
	var b := SeededRNG.new(s0)
	_ok("Child planet RNG reproducible", is_equal_approx(a.randf(), b.randf()))


func _test_visual_metadata() -> void:
	var w := SystemGenerator.new(7).generate(80)
	_ok("Star has type + luminosity", w["star"].has("star_type") and w["star"].has("luminosity"))
	var has_class := true
	for p in w["planets"]:
		if not SimEntities.PLANET_CLASSES.has(p.get("planet_class", "")):
			has_class = false
			break
	_ok("Planets have valid classes", has_class)
	var st: Dictionary = w["stations"][0]
	_ok("Station has role + modules", st.has("role") and st["modules"].size() >= 3)
	var sh: Dictionary = w["ships"][0]
	_ok("Ship has design dict", sh.has("design") and sh["design"].has("style"))
	var y: Dictionary = w["yields"][0]
	_ok("Yield has composition", y.has("composition") and y.has("asteroid_count"))


func _test_mesh_generators() -> void:
	MeshCache.clear()
	var ship_mesh := ShipMeshGen.build({
		"seed": 12345,
		"ship_class": SimEntities.ShipClass.MINER,
		"style": "mining",
		"color": Color(0.8, 0.5, 0.2),
		"accent": Color(0.4, 0.3, 0.2),
	})
	_ok("Ship mesh builds", ship_mesh != null and ship_mesh.get_surface_count() > 0)
	var ship_mesh2 := ShipMeshGen.build({
		"seed": 12345,
		"ship_class": SimEntities.ShipClass.MINER,
		"style": "mining",
		"color": Color(0.8, 0.5, 0.2),
		"accent": Color(0.4, 0.3, 0.2),
	})
	_ok("Ship mesh cache hit", ship_mesh == ship_mesh2)
	var st_mesh := StationMeshGen.build({
		"seed": 99,
		"role": "mining",
		"style": "mining",
		"color": Color(0.6, 0.5, 0.3),
	})
	_ok("Station mesh builds", st_mesh != null and st_mesh.get_surface_count() > 0)
	var ast := AsteroidMeshGen.build(42, 1)
	_ok("Asteroid mesh builds", ast != null and ast.get_surface_count() > 0)
	var desc := ShipMeshGen.describe({"seed": 12345, "ship_class": SimEntities.ShipClass.MINER, "style": "mining"})
	_ok("Ship describe has hull dims", float(desc.get("length", 0)) > 0.0 and int(desc.get("engines", 0)) >= 1)
	var mm := StarfieldGen.build_multimesh(42, 100)
	_ok("Starfield MultiMesh", mm != null and mm.instance_count == 100)


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

	var a := StarSystemSim.new()
	var b := StarSystemSim.new()
	a.generate(55, 60)
	b.generate(55, 60)
	for _i in 40:
		a.tick(0.1)
		b.tick(0.1)
	_ok("Parallel sims stay in sync", a.snapshot_hash() == b.snapshot_hash())

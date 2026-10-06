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
	_test_ship_design_grammar()
	_test_station_design_graph()
	_test_asteroid_families()
	_test_lod_consistency()
	_test_stellar_colour()
	_test_sky_composition()
	_test_economy_runs()
	_test_ships_become_active()
	_test_prices_respond_to_supply()
	_test_perf_benchmarks()
	_test_native_kernels()
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
	_ok("Planet has terrain/atmosphere seeds", w["planets"][0].has("terrain_seed") and w["planets"][0].has("atmosphere_seed"))
	_ok("Ship design has child seeds", sh["design"].has("hull_seed") and sh["design"].has("engine_seed"))


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
	var patrol := ShipMeshGen.build({
		"seed": 99,
		"ship_class": SimEntities.ShipClass.PATROL,
		"style": "military",
		"color": Color(0.7, 0.7, 0.8),
		"accent": Color(0.5, 0.2, 0.2),
	})
	_ok("Patrol mesh distinct from miner", patrol != null and patrol != ship_mesh)
	var st_mesh := StationMeshGen.build({
		"seed": 99,
		"role": "mining",
		"style": "mining",
		"color": Color(0.6, 0.5, 0.3),
	})
	_ok("Station mesh builds", st_mesh != null and st_mesh.get_surface_count() > 0)
	var trade_st := StationMeshGen.build({
		"seed": 99,
		"role": "trade",
		"style": "civilian",
		"color": Color(0.6, 0.5, 0.3),
	})
	_ok("Trade station mesh differs by role", trade_st != null and trade_st != st_mesh)
	var ast := AsteroidMeshGen.build(42, 1)
	_ok("Asteroid mesh builds", ast != null and ast.get_surface_count() > 0)
	var desc := ShipMeshGen.describe({"seed": 12345, "ship_class": SimEntities.ShipClass.MINER, "style": "mining"})
	_ok("Ship describe has hull dims", float(desc.get("length", 0)) > 0.0 and int(desc.get("engines", 0)) >= 1)
	var mm := StarfieldGen.build_multimesh(42, 100)
	_ok("Starfield MultiMesh", mm != null and mm.instance_count == 100)
	_ok("Starfield uses QuadMesh billboards", mm.mesh is QuadMesh)
	# Seed → mesh key stability across styles
	MeshCache.clear()
	var a := ShipMeshGen.build({"seed": 7, "ship_class": 0, "style": "civilian", "color": Color.WHITE, "accent": Color.GRAY})
	var b := ShipMeshGen.build({"seed": 7, "ship_class": 0, "style": "civilian", "color": Color.WHITE, "accent": Color.GRAY})
	_ok("Design seed mesh stable", a == b)


func _test_ship_design_grammar() -> void:
	var d1 := {
		"seed": 4242,
		"ship_class": SimEntities.ShipClass.MINER,
		"style": "mining",
		"color": Color(0.8, 0.5, 0.2),
		"accent": Color(0.4, 0.3, 0.2),
	}
	var a := ShipDesign.build(d1)
	var b := ShipDesign.build(d1)
	_ok("ShipDesign deterministic", int(a["hull_seed"]) == int(b["hull_seed"]) and float(a["length"]) == float(b["length"]))
	_ok("ShipDesign hierarchical child seeds", int(a["hull_seed"]) != int(a["engine_seed"]) and int(a["module_seed"]) != int(a["detail_seed"]))
	var d2 := d1.duplicate()
	d2["seed"] = 9999
	var c := ShipDesign.build(d2)
	_ok("Different design seed → different hull", int(a["hull_seed"]) != int(c["hull_seed"]))
	# Role consistency: miners look industrial
	var miner_types: Array = []
	for seed in [10, 20, 30, 40, 50]:
		var md := ShipDesign.build({"seed": seed, "ship_class": SimEntities.ShipClass.MINER, "style": "mining", "color": Color.WHITE, "accent": Color.GRAY})
		for m in md["modules"]:
			var t: String = str(m["type"])
			if not miner_types.has(t):
				miner_types.append(t)
	_ok("Miners share mining module vocabulary", miner_types.has("drill") or miner_types.has("ore_bay"))
	var patrol := ShipDesign.build({"seed": 11, "ship_class": SimEntities.ShipClass.PATROL, "style": "military", "color": Color.WHITE, "accent": Color.GRAY})
	var hauler := ShipDesign.build({"seed": 11, "ship_class": SimEntities.ShipClass.HAULER, "style": "civilian", "color": Color.WHITE, "accent": Color.GRAY})
	_ok("Patrol vs hauler different silhouette dims", float(patrol["length"]) < float(hauler["length"]))
	# Isolation: changing one design seed does not alter another object's seed derivation from parent
	var parent := 100
	var ship_a := SeedHash.derive_i(parent, "ship", 0)
	var ship_b := SeedHash.derive_i(parent, "ship", 1)
	var hull_a := SeedHash.derive(SeedHash.derive(ship_a, "design"), "hull")
	var hull_b1 := SeedHash.derive(SeedHash.derive(ship_b, "design"), "hull")
	# "regenerate" A with extra work — B unchanged
	var _ignored := ShipDesign.build({"seed": SeedHash.derive(ship_a, "design"), "ship_class": 0, "style": "mining", "color": Color.WHITE, "accent": Color.GRAY})
	var hull_b2 := SeedHash.derive(SeedHash.derive(ship_b, "design"), "hull")
	_ok("Hierarchical isolation ship B hull stable", hull_b1 == hull_b2 and hull_a != hull_b1)


func _test_station_design_graph() -> void:
	var st := {
		"seed": 77,
		"role": "industrial",
		"style": "mining",
		"modules": ["core", "docking", "factories", "cargo", "power", "habitation"],
		"color": Color(0.6, 0.5, 0.3),
	}
	var a := StationDesign.build(st)
	var b := StationDesign.build(st)
	_ok("StationDesign deterministic", int(a["layout_seed"]) == int(b["layout_seed"]) and (a["nodes"] as Array).size() == (b["nodes"] as Array).size())
	_ok("StationDesign has edges from core", (a["edges"] as Array).size() >= 1)
	var types: Array = []
	for n in a["nodes"]:
		types.append(str(n["type"]))
	_ok("StationDesign includes factories module", types.has("factories"))
	var mesh := StationMeshGen.build(st, VisualLOD.LOD_FULL)
	var mesh_low := StationMeshGen.build(st, VisualLOD.LOD_BATCH)
	_ok("Station LOD meshes build", mesh != null and mesh_low != null)


func _test_asteroid_families() -> void:
	var ice := AsteroidMeshGen.build(42, 1, "ice")
	var iron := AsteroidMeshGen.build(42, 1, "iron")
	_ok("Ice vs iron asteroid families differ", ice != null and iron != null and ice != iron)
	_ok("Asteroid family name stable", AsteroidMeshGen.family_name(42, "ice") == AsteroidMeshGen.family_name(42, "ice"))
	var families: Dictionary = {}
	for s in range(20):
		families[AsteroidMeshGen.family_name(s, "silicate")] = true
	_ok("Silicate uses multiple families across seeds", families.size() >= 2)


func _test_lod_consistency() -> void:
	var design := {
		"seed": 555,
		"ship_class": SimEntities.ShipClass.TRADER,
		"style": "civilian",
		"color": Color(0.7, 0.7, 0.8),
		"accent": Color(0.4, 0.4, 0.5),
	}
	var full := ShipMeshGen.describe(design)
	var mesh0 := ShipMeshGen.build(design, VisualLOD.LOD_FULL)
	var mesh3 := ShipMeshGen.build(design, VisualLOD.LOD_BATCH)
	_ok("LOD meshes both build", mesh0 != null and mesh3 != null)
	_ok("LOD meshes are distinct cache entries", mesh0 != mesh3)
	# Same underlying design dims regardless of LOD mesh
	var full2 := ShipMeshGen.describe(design)
	_ok("LOD does not change design descriptor", float(full["length"]) == float(full2["length"]))
	_ok("VisualLOD distance tiers ordered", VisualLOD.for_distance(100) < VisualLOD.for_distance(800) and VisualLOD.for_distance(800) < VisualLOD.for_distance(5000))


func _test_stellar_colour() -> void:
	var cool := StellarColour.from_temperature(3000.0)
	var hot := StellarColour.from_temperature(12000.0)
	_ok("Cool stars redder than hot", cool.r >= hot.r * 0.9 and cool.b < hot.b)
	_ok("Hot stars bluish", hot.b > 0.85)


func _test_sky_composition() -> void:
	var a := SkyComposition.build(42)
	var b := SkyComposition.build(42)
	_ok("SkyComposition deterministic mood", str(a["mood"]) == str(b["mood"]))
	_ok("SkyComposition has masses", (a["masses"] as Array).size() >= 2)
	_ok("SkyComposition has voids", (a["voids"] as Array).size() >= 2)
	_ok("SkyComposition has gems", (a["gems"] as Array).size() >= 4)
	_ok("SkyComposition palette keys", a["palette"].has("primary") and a["palette"].has("bg"))
	var c := SkyComposition.build(99)
	_ok("Different seed can change mood or axis", str(a["mood"]) != str(c["mood"]) or not a["galaxy_normal"].is_equal_approx(c["galaxy_normal"]))
	var packs := StarfieldGen.build_from_composition(a)
	_ok("Starfield populations build", packs.has("field") and packs.has("micro") and packs.has("gems"))
	_ok("Field MultiMesh count", packs["field"].instance_count == int(a["star_field_count"]))


func _test_perf_benchmarks() -> void:
	print("--- Perf benchmarks ---")
	print("  native_backend=%s  version=%s" % [NativeBridge.backend_name(), NativeBridge.version()])
	var sizes := [400, 1000]
	for n in sizes:
		MeshCache.clear()
		var t0 := Time.get_ticks_usec()
		var sim := StarSystemSim.new()
		sim.generate(42, n)
		var gen_ms := (Time.get_ticks_usec() - t0) / 1000.0
		t0 = Time.get_ticks_usec()
		# Build a sample of visual meshes (ships by class + stations + asteroids)
		for sc in [0, 1, 2, 3]:
			ShipMeshGen.build({"seed": 50 + sc * 17, "ship_class": sc, "style": "civilian", "color": Color.WHITE, "accent": Color.GRAY}, VisualLOD.LOD_BATCH)
		for st in sim.world["stations"]:
			StationMeshGen.build(st, VisualLOD.LOD_FULL)
		for y in sim.world["yields"]:
			AsteroidMeshGen.build(int(y["seed"]), 1, str(y.get("composition", "iron")))
		var mesh_ms := (Time.get_ticks_usec() - t0) / 1000.0
		t0 = Time.get_ticks_usec()
		for _i in 60:
			sim.tick(0.05)
		var tick_ms := (Time.get_ticks_usec() - t0) / 1000.0
		print("  ships=%d  gen=%.1fms  mesh=%.1fms  60ticks=%.1fms  econ=%.2f ai=%.2f travel_batch=%.2f (n=%d) backend=%s" % [
			n, gen_ms, mesh_ms, tick_ms, float(sim.perf.get("economy_ms", 0)), float(sim.perf.get("ai_ms", 0)),
			float(sim.perf.get("travel_batch_ms", 0)), int(sim.perf.get("travel_batch_n", 0)),
			str(sim.perf.get("native_backend", "?")),
		])
		_ok("Perf gen ships=%d under 5s" % n, gen_ms < 5000.0)
		_ok("Perf mesh ships=%d under 10s" % n, mesh_ms < 10000.0)
	var rust_ms := NativeBridge.bench_travel_ms(2000, 200)
	print("  travel microbench n=2000 iters=200 → %.3fms (%s)" % [rust_ms, NativeBridge.backend_name()])
	_ok("Travel microbench finishes", rust_ms >= 0.0)
	print("  (5000/10000/50000 ship targets: measure locally; extend native/ew_kernels for new SoA kernels)")


func _test_native_kernels() -> void:
	print("--- Native kernels ---")
	_ok("NativeBridge reports a backend", NativeBridge.backend_name() in ["rust", "gdscript"])
	# Travel math equivalence: one ship toward a far destination.
	var ships: Array = [{
		"position": Vector3.ZERO,
		"heading": Vector3(0, 0, -1),
		"velocity": Vector3.ZERO,
		"speed": 100.0,
	}]
	var dests: Array = [Vector3(1000, 0, 0)]
	var arrive := PackedFloat32Array([35.0])
	var status: PackedInt32Array = NativeBridge.integrate_travel_ships(ships, dests, arrive, 0.05)
	_ok("Travel status traveling", status.size() == 1 and int(status[0]) == NativeBridge.STATUS_TRAVELING)
	var p: Vector3 = ships[0]["position"]
	_ok("Travel stepped ~5 units", absf(p.x - 5.0) < 0.01, "pos=%s" % p)
	# Arrive
	ships[0]["position"] = Vector3(10, 0, 0)
	status = NativeBridge.integrate_travel_ships(ships, dests, arrive, 0.05)
	# dest still 1000 — not arrived. Place near dest.
	ships[0]["position"] = Vector3(980, 0, 0)
	status = NativeBridge.integrate_travel_ships(ships, [Vector3(1000, 0, 0)], arrive, 0.05)
	_ok("Travel arrives within radius", int(status[0]) == NativeBridge.STATUS_ARRIVED)
	# Sim uses batch path and stays deterministic across backends for seed.
	var sim := StarSystemSim.new()
	sim.generate(99, 120)
	for _i in 40:
		sim.tick(0.05)
	_ok("Sim ticks with native travel batch", int(sim.world["tick"]) == 40)
	_ok("Travel batch recorded", int(sim.perf.get("travel_batch_n", -1)) >= 0)


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

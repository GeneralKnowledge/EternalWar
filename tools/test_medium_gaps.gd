extends SceneTree
## Smoke: SystemBasic layout, SeededRNG.exp_rand, asteroid LOD bands.


func _init() -> void:
	var fails := 0
	var rng := SeededRNG.new(42)
	var e0 := rng.exp_rand()
	var e1 := rng.exp_rand()
	if e0 <= 0.0 or e1 <= 0.0:
		push_error("exp_rand non-positive")
		fails += 1

	var gen := SystemGenerator.new(42)
	var world: Dictionary = gen.generate(40)
	var planets: Array = world["planets"]
	var yields: Array = world["yields"]
	var stations: Array = world["stations"]
	if planets.is_empty() or yields.is_empty() or stations.is_empty():
		push_error("empty system collections")
		fails += 1

	var field_n := 0
	var belt_n := 0
	for y in yields:
		var layout := str(y.get("layout", ""))
		if layout == "field":
			field_n += 1
			var p: Vector3 = y["position"]
			# Exp-ball field centers should not all sit on a tiny ring.
			if p.length() < 10.0:
				push_error("field center too close to origin")
				fails += 1
		elif layout == "belt":
			belt_n += 1
			if not y.has("belt_rc") or not y.has("belt_rw"):
				push_error("belt missing rc/rw")
				fails += 1
	if field_n < 4 or belt_n < 1:
		push_error("expected field+belt yields, got field=%d belt=%d" % [field_n, belt_n])
		fails += 1

	# Stations on ~SYSTEM_SCALE disc
	var scale := SystemGenerator.SYSTEM_SCALE
	for s in stations:
		var sp: Vector3 = s["position"]
		var xz := Vector2(sp.x, sp.z).length()
		if absf(xz - scale) > scale * 0.08:
			push_error("station not on SYSTEM_SCALE disc: xz=%s" % xz)
			fails += 1

	# Asteroid LOD meshes build
	for d in range(4):
		var mesh: ArrayMesh = ShapeLibAsteroid.generate_mesh(99, d, Color(0.4, 0.4, 0.4))
		if mesh == null or mesh.get_surface_count() < 1:
			push_error("asteroid LOD detail %d failed" % d)
			fails += 1

	var near_d := ShapeLibAsteroid.lod_detail_for_distance(100.0, 750.0)
	var far_d := ShapeLibAsteroid.lod_detail_for_distance(5000.0, 750.0)
	if near_d <= far_d:
		push_error("LOD detail should drop with distance")
		fails += 1

	if fails == 0:
		print("MEDIUM_GAPS_SMOKE_OK fields=%d belts=%d planets=%d stations=%d" % [
			field_n, belt_n, planets.size(), stations.size(),
		])
		quit(0)
	else:
		print("MEDIUM_GAPS_SMOKE_FAIL fails=", fails)
		quit(1)

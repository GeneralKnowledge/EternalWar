## Optional Rust GDExtension bridge with GDScript fallbacks.
## Prefer native kernels when ClassDB has NativeKernels; otherwise identical SoA math in GDScript.
class_name NativeBridge
extends RefCounted

const STATUS_TRAVELING := 0
const STATUS_ARRIVED := 1
const STATUS_INVALID := 2

static var _kernels: RefCounted = null
static var _checked := false
static var _available := false
static var _version := "gdscript-fallback"


static func available() -> bool:
	_ensure()
	return _available


static func version() -> String:
	_ensure()
	return _version


static func backend_name() -> String:
	_ensure()
	return "rust" if _available else "gdscript"


static func _ensure() -> void:
	if _checked:
		return
	_checked = true
	if ClassDB.class_exists("NativeKernels"):
		_kernels = ClassDB.instantiate("NativeKernels")
		if _kernels != null and _kernels.has_method("is_available") and bool(_kernels.call("is_available")):
			_available = true
			_version = str(_kernels.call("version"))
			return
	_kernels = null
	_available = false
	_version = "gdscript-fallback"


## Integrate TRAVEL for a batch. Mutates ship dictionaries in `ships` (Array of Dictionary).
## `destinations` is Array of Vector3 (same length). Returns PackedInt32Array status codes.
static func integrate_travel_ships(ships: Array, destinations: Array, arrive_radii: PackedFloat32Array, dt: float) -> PackedInt32Array:
	var n := ships.size()
	var positions := PackedFloat32Array()
	var headings := PackedFloat32Array()
	var velocities := PackedFloat32Array()
	var dests := PackedFloat32Array()
	var speeds := PackedFloat32Array()
	positions.resize(n * 3)
	headings.resize(n * 3)
	velocities.resize(n * 3)
	dests.resize(n * 3)
	speeds.resize(n)
	for i in n:
		var s: Dictionary = ships[i]
		var p: Vector3 = s["position"]
		var h: Vector3 = s.get("heading", Vector3(0, 0, -1))
		var v: Vector3 = s.get("velocity", Vector3.ZERO)
		var d: Vector3 = destinations[i]
		var i3 := i * 3
		positions[i3] = p.x
		positions[i3 + 1] = p.y
		positions[i3 + 2] = p.z
		headings[i3] = h.x
		headings[i3 + 1] = h.y
		headings[i3 + 2] = h.z
		velocities[i3] = v.x
		velocities[i3 + 1] = v.y
		velocities[i3 + 2] = v.z
		dests[i3] = d.x
		dests[i3 + 1] = d.y
		dests[i3 + 2] = d.z
		speeds[i] = float(s["speed"])

	var status: PackedInt32Array
	if available():
		var result: Dictionary = _kernels.call(
			"integrate_travel", positions, headings, velocities, dests, speeds, arrive_radii, dt
		)
		if not bool(result.get("ok", false)):
			return _integrate_travel_gdscript(ships, destinations, arrive_radii, dt)
		positions = result["positions"]
		headings = result["headings"]
		velocities = result["velocities"]
		status = result["status"]
	else:
		var fb := _integrate_travel_core(positions, headings, velocities, dests, speeds, arrive_radii, dt)
		positions = fb["positions"]
		headings = fb["headings"]
		velocities = fb["velocities"]
		status = fb["status"]

	for i in n:
		var s2: Dictionary = ships[i]
		var j := i * 3
		s2["position"] = Vector3(positions[j], positions[j + 1], positions[j + 2])
		s2["heading"] = Vector3(headings[j], headings[j + 1], headings[j + 2])
		s2["velocity"] = Vector3(velocities[j], velocities[j + 1], velocities[j + 2])
	return status


static func _integrate_travel_gdscript(
	ships: Array, destinations: Array, arrive_radii: PackedFloat32Array, dt: float
) -> PackedInt32Array:
	var n := ships.size()
	var positions := PackedFloat32Array()
	var headings := PackedFloat32Array()
	var velocities := PackedFloat32Array()
	var dests := PackedFloat32Array()
	var speeds := PackedFloat32Array()
	positions.resize(n * 3)
	headings.resize(n * 3)
	velocities.resize(n * 3)
	dests.resize(n * 3)
	speeds.resize(n)
	for i in n:
		var s: Dictionary = ships[i]
		var p: Vector3 = s["position"]
		var h: Vector3 = s.get("heading", Vector3(0, 0, -1))
		var v: Vector3 = s.get("velocity", Vector3.ZERO)
		var d: Vector3 = destinations[i]
		var i3 := i * 3
		positions[i3] = p.x
		positions[i3 + 1] = p.y
		positions[i3 + 2] = p.z
		headings[i3] = h.x
		headings[i3 + 1] = h.y
		headings[i3 + 2] = h.z
		velocities[i3] = v.x
		velocities[i3 + 1] = v.y
		velocities[i3 + 2] = v.z
		dests[i3] = d.x
		dests[i3 + 1] = d.y
		dests[i3 + 2] = d.z
		speeds[i] = float(s["speed"])
	var fb := _integrate_travel_core(positions, headings, velocities, dests, speeds, arrive_radii, dt)
	positions = fb["positions"]
	headings = fb["headings"]
	velocities = fb["velocities"]
	var status: PackedInt32Array = fb["status"]
	for i in n:
		var s2: Dictionary = ships[i]
		var j := i * 3
		s2["position"] = Vector3(positions[j], positions[j + 1], positions[j + 2])
		s2["heading"] = Vector3(headings[j], headings[j + 1], headings[j + 2])
		s2["velocity"] = Vector3(velocities[j], velocities[j + 1], velocities[j + 2])
	return status


static func _integrate_travel_core(
	positions: PackedFloat32Array,
	headings: PackedFloat32Array,
	velocities: PackedFloat32Array,
	destinations: PackedFloat32Array,
	speeds: PackedFloat32Array,
	arrive: PackedFloat32Array,
	dt: float,
) -> Dictionary:
	var n := speeds.size()
	var status := PackedInt32Array()
	status.resize(n)
	for i in n:
		var i3 := i * 3
		var px := positions[i3]
		var py := positions[i3 + 1]
		var pz := positions[i3 + 2]
		var dx := destinations[i3] - px
		var dy := destinations[i3 + 1] - py
		var dz := destinations[i3 + 2] - pz
		var dist_sq := dx * dx + dy * dy + dz * dz
		if not is_finite(dist_sq):
			status[i] = STATUS_INVALID
			continue
		var dist := sqrt(dist_sq)
		var arr := arrive[i]
		if dist <= arr:
			status[i] = STATUS_ARRIVED
			velocities[i3] = 0.0
			velocities[i3 + 1] = 0.0
			velocities[i3 + 2] = 0.0
			continue
		var inv := 1.0 / dist
		var dir_x := dx * inv
		var dir_y := dy * inv
		var dir_z := dz * inv
		headings[i3] = dir_x
		headings[i3 + 1] = dir_y
		headings[i3 + 2] = dir_z
		var speed := speeds[i]
		var max_step := maxf(dist - arr * 0.5, 0.0)
		var step := minf(speed * dt, max_step)
		positions[i3] = px + dir_x * step
		positions[i3 + 1] = py + dir_y * step
		positions[i3 + 2] = pz + dir_z * step
		velocities[i3] = dir_x * speed
		velocities[i3 + 1] = dir_y * speed
		velocities[i3 + 2] = dir_z * speed
		status[i] = STATUS_TRAVELING
	return {
		"positions": positions,
		"headings": headings,
		"velocities": velocities,
		"status": status,
	}


## Apply far-field MultiMesh transforms via native kernel when available.
static func apply_ship_transforms(
	mm: MultiMesh,
	local_indices: PackedInt32Array,
	positions: PackedFloat32Array,
	headings: PackedFloat32Array,
	scales: PackedFloat32Array,
	hidden: PackedInt32Array,
) -> int:
	var n := scales.size()
	if available() and _kernels.has_method("apply_ship_transforms"):
		return int(_kernels.call(
			"apply_ship_transforms", mm, local_indices, positions, headings, scales, hidden
		))
	# GDScript fallback
	for i in n:
		var i3 := i * 3
		var pos := Vector3(positions[i3], positions[i3 + 1], positions[i3 + 2])
		if hidden[i] != 0:
			mm.set_instance_transform(local_indices[i], Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), pos))
			continue
		var heading := Vector3(headings[i3], headings[i3 + 1], headings[i3 + 2])
		if heading.length_squared() < 0.001:
			heading = Vector3(0, 0, -1)
		var basis := Basis.looking_at(heading.normalized(), Vector3.UP)
		var s := scales[i]
		mm.set_instance_transform(local_indices[i], Transform3D(basis.scaled(Vector3.ONE * s), pos))
	return n


static func bench_travel_ms(n: int, iters: int) -> float:
	_ensure()
	if available() and _kernels.has_method("bench_travel"):
		return float(_kernels.call("bench_travel", n, iters))
	# Approximate GDScript cost for comparison
	var positions := PackedFloat32Array()
	var headings := PackedFloat32Array()
	var velocities := PackedFloat32Array()
	var dests := PackedFloat32Array()
	var speeds := PackedFloat32Array()
	var arrive := PackedFloat32Array()
	positions.resize(n * 3)
	headings.resize(n * 3)
	velocities.resize(n * 3)
	dests.resize(n * 3)
	speeds.resize(n)
	arrive.resize(n)
	for i in n:
		positions[i * 3] = float(i) * 0.1
		dests[i * 3] = positions[i * 3] + 500.0
		dests[i * 3 + 1] = 10.0
		dests[i * 3 + 2] = 20.0
		speeds[i] = 80.0
		arrive[i] = 35.0
	var t0 := Time.get_ticks_usec()
	for _k in iters:
		_integrate_travel_core(positions, headings, velocities, dests, speeds, arrive, 0.05)
	return float(Time.get_ticks_usec() - t0) / 1000.0

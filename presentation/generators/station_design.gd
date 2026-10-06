## Semantic station layout — role modules become a graph, then geometry.
class_name StationDesign
extends RefCounted

## Relative offsets from core for known module types (architectural language).
const MODULE_LAYOUT := {
	"core": Vector3.ZERO,
	"docking": Vector3(0, -1.1, 2.0),
	"cargo": Vector3(2.0, 0.1, 0),
	"factories": Vector3(-2.0, 0.2, 0),
	"processing": Vector3(0, -0.3, 2.2),
	"power": Vector3(0, 1.6, 0),
	"habitation": Vector3(0, 0.5, -2.0),
	"communications": Vector3(0, 2.2, 0),
	"weapons": Vector3(1.6, 0.4, 1.2),
	"sensors": Vector3(-1.6, 0.4, 1.2),
	"armour": Vector3(0, 0, 0),
	"command": Vector3(0, 2.4, 0),
	"market": Vector3(1.8, 0.1, -1.4),
	"storage": Vector3(-1.8, 0.1, -1.4),
	"refinery": Vector3(0, -0.2, 2.4),
	"manufacturing": Vector3(-2.1, 0.25, 0.4),
}


static func build(station_or_design: Dictionary) -> Dictionary:
	var seed: int = int(station_or_design.get("seed", 1))
	var role: String = str(station_or_design.get("role", "trade"))
	var style: String = str(station_or_design.get("style", "industrial"))
	var profile := StyleProfile.of(style)
	var module_names: Array = station_or_design.get("modules", [])
	if module_names.is_empty():
		module_names = ["core", "docking", "cargo", "power"]

	var layout_seed := SeedHash.derive(seed, "layout")
	var detail_seed := SeedHash.derive(seed, "detail")
	var rng := SeededRNG.new(layout_seed)

	var nodes: Array = []
	var edges: Array = []
	# Always ensure core
	if not module_names.has("core"):
		module_names = ["core"] + module_names

	for i in module_names.size():
		var mname: String = str(module_names[i])
		var base: Vector3 = MODULE_LAYOUT.get(mname, Vector3(rng.randf_range(-2, 2), rng.randf_range(-0.5, 1.5), rng.randf_range(-2, 2)))
		# Slight deterministic jitter so identical roles still vary
		var jitter := Vector3(
			rng.randf_range(-0.15, 0.15),
			rng.randf_range(-0.1, 0.1),
			rng.randf_range(-0.15, 0.15)
		)
		if mname == "core":
			jitter = Vector3.ZERO
		var size := _module_size(mname, rng, profile)
		nodes.append({
			"id": i,
			"type": mname,
			"pos": base + jitter,
			"size": size,
			"seed": SeedHash.derive_i(seed, "module", i),
		})
		if mname != "core":
			edges.append({"from": 0, "to": i})

	# Role-specific rings / spines
	var extras: Array = []
	if role == "trade" or role == "habitat":
		extras.append({"type": "ring", "radius": 2.1, "tube": 0.28, "y": 0.0})
	if role == "mining" or role == "industrial":
		extras.append({"type": "ring", "radius": 1.7, "tube": 0.14, "y": 0.6})
	if role == "military":
		extras.append({"type": "spine", "height": 2.4})

	return {
		"seed": seed,
		"layout_seed": layout_seed,
		"detail_seed": detail_seed,
		"role": role,
		"style": style,
		"profile": profile,
		"nodes": nodes,
		"edges": edges,
		"extras": extras,
		"color": station_or_design.get("color", Color(0.55, 0.6, 0.65)),
	}


static func _module_size(mname: String, rng: SeededRNG, profile: Dictionary) -> Vector3:
	var d := float(profile.get("detail_density", 0.5))
	match mname:
		"core":
			return Vector3(1.2, 1.1, 1.2)
		"docking":
			return Vector3(0.9, 0.45, 1.1)
		"cargo", "storage":
			return Vector3(rng.randf_range(0.9, 1.3), rng.randf_range(0.5, 0.9), rng.randf_range(0.9, 1.3))
		"factories", "manufacturing", "processing", "refinery":
			return Vector3(rng.randf_range(1.2, 1.7), rng.randf_range(1.0, 1.5), rng.randf_range(1.0, 1.4))
		"power":
			return Vector3(0.55, rng.randf_range(1.0, 1.6), 0.55)
		"habitation":
			return Vector3(1.1, 0.9, 1.1)
		"weapons", "armour":
			return Vector3(0.55, 0.4, 0.55)
		"command", "communications":
			return Vector3(0.5, 0.7 + d * 0.3, 0.5)
		_:
			return Vector3(0.8, 0.6, 0.8)

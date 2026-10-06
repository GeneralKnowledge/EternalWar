## Faction / organisation visual style profiles.
## Style drives proportions, symmetry, materials — not just a colour tint.
class_name StyleProfile
extends RefCounted

const PROFILES := {
	"military": {
		"symmetry": 0.95,
		"taper": 0.4,
		"detail_density": 0.7,
		"engine_scale": 1.15,
		"ornament": 0.15,
		"material": "metal_dark",
		"accent_material": "painted",
		"roughness": 0.35,
		"metallic": 0.65,
	},
	"mining": {
		"symmetry": 0.55,
		"taper": 0.7,
		"detail_density": 0.85,
		"engine_scale": 0.95,
		"ornament": 0.05,
		"material": "industrial",
		"accent_material": "metal_dark",
		"roughness": 0.7,
		"metallic": 0.35,
	},
	"civilian": {
		"symmetry": 0.8,
		"taper": 0.55,
		"detail_density": 0.45,
		"engine_scale": 1.0,
		"ornament": 0.35,
		"material": "metal_light",
		"accent_material": "painted",
		"roughness": 0.45,
		"metallic": 0.4,
	},
	"pirate": {
		"symmetry": 0.25,
		"taper": 0.5,
		"detail_density": 0.9,
		"engine_scale": 1.2,
		"ornament": 0.2,
		"material": "industrial",
		"accent_material": "metal_dark",
		"roughness": 0.75,
		"metallic": 0.3,
	},
	"luxury": {
		"symmetry": 0.9,
		"taper": 0.45,
		"detail_density": 0.55,
		"engine_scale": 0.9,
		"ornament": 0.75,
		"material": "ceramic",
		"accent_material": "glass",
		"roughness": 0.25,
		"metallic": 0.55,
	},
	"industrial": {
		"symmetry": 0.6,
		"taper": 0.75,
		"detail_density": 0.8,
		"engine_scale": 1.0,
		"ornament": 0.1,
		"material": "industrial",
		"accent_material": "metal_dark",
		"roughness": 0.8,
		"metallic": 0.4,
	},
	"high_tech": {
		"symmetry": 0.85,
		"taper": 0.35,
		"detail_density": 0.6,
		"engine_scale": 1.1,
		"ornament": 0.4,
		"material": "ceramic",
		"accent_material": "energy",
		"roughness": 0.3,
		"metallic": 0.5,
	},
	"utilitarian": {
		"symmetry": 0.7,
		"taper": 0.65,
		"detail_density": 0.5,
		"engine_scale": 1.0,
		"ornament": 0.05,
		"material": "metal_light",
		"accent_material": "industrial",
		"roughness": 0.6,
		"metallic": 0.45,
	},
}


static func of(style: String) -> Dictionary:
	if PROFILES.has(style):
		return PROFILES[style].duplicate()
	return PROFILES["civilian"].duplicate()


static func merge_with_faction(style: String, faction: Dictionary = {}) -> Dictionary:
	var p := of(style)
	if faction.has("style") and str(faction["style"]) != style:
		var fp := of(str(faction["style"]))
		p["symmetry"] = lerpf(float(p["symmetry"]), float(fp["symmetry"]), 0.35)
		p["ornament"] = lerpf(float(p["ornament"]), float(fp["ornament"]), 0.35)
	return p

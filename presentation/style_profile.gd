## Faction / organisation visual style profiles.
## Style drives proportions, symmetry, hull language, exhaust — not just a colour tint.
## Values tuned from LT screenshot/source forensics (docs/limit-theory-ship-forensics.md).
class_name StyleProfile
extends RefCounted

const PROFILES := {
	"military": {
		"symmetry": 0.95,
		"taper": 0.38,
		"detail_density": 0.65,
		"engine_scale": 1.15,
		"ornament": 0.12,
		"material": "metal_dark",
		"accent_material": "painted",
		"roughness": 0.45,
		"metallic": 0.55,
		"hull_language": "wedge",
		"negative_space": 0.35,
		"exhaust_family": "cyan",
		"panel_bias": 0.7,
		"strut_bias": 0.25,
		"hull_sides": 6,
	},
	"mining": {
		"symmetry": 0.45,
		"taper": 0.68,
		"detail_density": 0.85,
		"engine_scale": 0.95,
		"ornament": 0.05,
		"material": "industrial",
		"accent_material": "metal_dark",
		"roughness": 0.78,
		"metallic": 0.3,
		"hull_language": "block",
		"negative_space": 0.55,
		"exhaust_family": "amber",
		"panel_bias": 0.5,
		"strut_bias": 0.75,
		"hull_sides": 4,
	},
	"civilian": {
		"symmetry": 0.8,
		"taper": 0.52,
		"detail_density": 0.4,
		"engine_scale": 1.0,
		"ornament": 0.3,
		"material": "metal_light",
		"accent_material": "painted",
		"roughness": 0.5,
		"metallic": 0.35,
		"hull_language": "round",
		"negative_space": 0.4,
		"exhaust_family": "white",
		"panel_bias": 0.4,
		"strut_bias": 0.35,
		"hull_sides": 8,
	},
	"pirate": {
		"symmetry": 0.2,
		"taper": 0.5,
		"detail_density": 0.9,
		"engine_scale": 1.25,
		"ornament": 0.15,
		"material": "industrial",
		"accent_material": "metal_dark",
		"roughness": 0.8,
		"metallic": 0.28,
		"hull_language": "block",
		"negative_space": 0.65,
		"exhaust_family": "amber",
		"panel_bias": 0.55,
		"strut_bias": 0.7,
		"hull_sides": 5,
	},
	"luxury": {
		"symmetry": 0.92,
		"taper": 0.42,
		"detail_density": 0.5,
		"engine_scale": 0.88,
		"ornament": 0.7,
		"material": "ceramic",
		"accent_material": "glass",
		"roughness": 0.28,
		"metallic": 0.45,
		"hull_language": "round",
		"negative_space": 0.25,
		"exhaust_family": "white",
		"panel_bias": 0.35,
		"strut_bias": 0.15,
		"hull_sides": 10,
	},
	"industrial": {
		"symmetry": 0.55,
		"taper": 0.72,
		"detail_density": 0.8,
		"engine_scale": 1.0,
		"ornament": 0.08,
		"material": "industrial",
		"accent_material": "metal_dark",
		"roughness": 0.82,
		"metallic": 0.35,
		"hull_language": "spine",
		"negative_space": 0.6,
		"exhaust_family": "amber",
		"panel_bias": 0.6,
		"strut_bias": 0.8,
		"hull_sides": 4,
	},
	"high_tech": {
		"symmetry": 0.85,
		"taper": 0.32,
		"detail_density": 0.55,
		"engine_scale": 1.1,
		"ornament": 0.35,
		"material": "ceramic",
		"accent_material": "energy",
		"roughness": 0.32,
		"metallic": 0.48,
		"hull_language": "wedge",
		"negative_space": 0.45,
		"exhaust_family": "cyan",
		"panel_bias": 0.55,
		"strut_bias": 0.3,
		"hull_sides": 8,
	},
	"utilitarian": {
		"symmetry": 0.7,
		"taper": 0.62,
		"detail_density": 0.45,
		"engine_scale": 1.0,
		"ornament": 0.05,
		"material": "metal_light",
		"accent_material": "industrial",
		"roughness": 0.65,
		"metallic": 0.4,
		"hull_language": "block",
		"negative_space": 0.4,
		"exhaust_family": "white",
		"panel_bias": 0.35,
		"strut_bias": 0.45,
		"hull_sides": 6,
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
		p["negative_space"] = lerpf(float(p["negative_space"]), float(fp["negative_space"]), 0.3)
	return p


## Exhaust emissive colour from style family (+ small seed jitter via rng optional).
static func exhaust_color(profile: Dictionary, rng: SeededRNG = null) -> Color:
	var family := str(profile.get("exhaust_family", "cyan"))
	var c: Color
	match family:
		"amber":
			c = Color(1.0, 0.55, 0.18)
		"white":
			c = Color(0.85, 0.9, 1.0)
		_:
			c = Color(0.35, 0.75, 1.0)
	if rng != null:
		c = c.lerp(Color(rng.randf(), rng.randf() * 0.5 + 0.4, rng.randf() * 0.4 + 0.3), 0.08)
	return c

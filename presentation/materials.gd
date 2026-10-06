## Shared procedural material vocabulary — parameters, not unique textures per object.
class_name VisualMaterials
extends RefCounted

const PRESETS := {
	# LT hulls read as dark matte silhouettes — keep metal softer/rougher than chrome.
	"metal_dark": {"albedo": Color(0.18, 0.19, 0.21), "roughness": 0.55, "metallic": 0.55, "emission": Color.BLACK, "emission_energy": 0.0},
	"metal_light": {"albedo": Color(0.58, 0.58, 0.6), "roughness": 0.48, "metallic": 0.4, "emission": Color.BLACK, "emission_energy": 0.0},
	"industrial": {"albedo": Color(0.38, 0.34, 0.28), "roughness": 0.82, "metallic": 0.28, "emission": Color.BLACK, "emission_energy": 0.0},
	"painted": {"albedo": Color(0.48, 0.42, 0.38), "roughness": 0.58, "metallic": 0.18, "emission": Color.BLACK, "emission_energy": 0.0},
	"ceramic": {"albedo": Color(0.72, 0.72, 0.74), "roughness": 0.35, "metallic": 0.12, "emission": Color.BLACK, "emission_energy": 0.0},
	"glass": {"albedo": Color(0.45, 0.55, 0.65, 0.55), "roughness": 0.12, "metallic": 0.05, "emission": Color(0.25, 0.4, 0.55), "emission_energy": 0.12},
	"energy": {"albedo": Color(0.9, 0.55, 0.25), "roughness": 0.25, "metallic": 0.08, "emission": Color(1.0, 0.55, 0.2), "emission_energy": 2.0},
	"energy_cyan": {"albedo": Color(0.35, 0.7, 1.0), "roughness": 0.2, "metallic": 0.1, "emission": Color(0.3, 0.65, 1.0), "emission_energy": 2.2},
	"warm_industrial": {"albedo": Color(0.42, 0.32, 0.22), "roughness": 0.8, "metallic": 0.25, "emission": Color.BLACK, "emission_energy": 0.0},
	"charcoal": {"albedo": Color(0.14, 0.14, 0.15), "roughness": 0.7, "metallic": 0.35, "emission": Color.BLACK, "emission_energy": 0.0},
	"copper": {"albedo": Color(0.55, 0.32, 0.18), "roughness": 0.55, "metallic": 0.65, "emission": Color.BLACK, "emission_energy": 0.0},
	"rock": {"albedo": Color(0.45, 0.4, 0.35), "roughness": 0.92, "metallic": 0.05, "emission": Color.BLACK, "emission_energy": 0.0},
	"ice": {"albedo": Color(0.7, 0.82, 0.92), "roughness": 0.3, "metallic": 0.12, "emission": Color(0.4, 0.55, 0.7), "emission_energy": 0.25},
	"gas": {"albedo": Color(0.75, 0.6, 0.4), "roughness": 0.85, "metallic": 0.0, "emission": Color(0.5, 0.4, 0.3), "emission_energy": 0.08},
	"atmosphere": {"albedo": Color(0.4, 0.55, 0.9, 0.2), "roughness": 1.0, "metallic": 0.0, "emission": Color(0.35, 0.5, 0.9), "emission_energy": 0.4},
}


static func make(name: String, tint: Color = Color.WHITE, tint_amount: float = 0.35) -> StandardMaterial3D:
	var p: Dictionary = PRESETS.get(name, PRESETS["metal_light"])
	var mat := StandardMaterial3D.new()
	var base: Color = p["albedo"]
	mat.albedo_color = base.lerp(tint, tint_amount)
	mat.roughness = float(p["roughness"])
	mat.metallic = float(p["metallic"])
	var em: Color = p["emission"]
	var ee := float(p["emission_energy"])
	if ee > 0.01:
		mat.emission_enabled = true
		mat.emission = em
		mat.emission_energy_multiplier = ee
	if base.a < 0.99:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	return mat


static func apply_to(mi: GeometryInstance3D, name: String, tint: Color = Color.WHITE) -> void:
	mi.material_override = make(name, tint)

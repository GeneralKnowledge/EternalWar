## Physically inspired stellar colour from temperature (Kelvin).
class_name StellarColour
extends RefCounted


## Approximate blackbody colour for stellar temperatures.
static func from_temperature(kelvin: float) -> Color:
	var t := clampf(kelvin, 2000.0, 40000.0)
	# Piecewise: red → orange → yellow → white → blue
	if t < 3500.0:
		var u := (t - 2000.0) / 1500.0
		return Color(1.0, lerpf(0.35, 0.55, u), lerpf(0.1, 0.25, u))
	if t < 5000.0:
		var u := (t - 3500.0) / 1500.0
		return Color(1.0, lerpf(0.55, 0.82, u), lerpf(0.25, 0.45, u))
	if t < 6500.0:
		var u := (t - 5000.0) / 1500.0
		return Color(1.0, lerpf(0.82, 0.95, u), lerpf(0.45, 0.8, u))
	if t < 10000.0:
		var u := (t - 6500.0) / 3500.0
		return Color(lerpf(1.0, 0.85, u), lerpf(0.95, 0.9, u), 1.0)
	var u2 := clampf((t - 10000.0) / 20000.0, 0.0, 1.0)
	return Color(lerpf(0.85, 0.55, u2), lerpf(0.9, 0.7, u2), 1.0)


static func luminosity_energy(luminosity: float) -> float:
	return 1.4 + clampf(luminosity, 0.3, 3.0) * 1.1

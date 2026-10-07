## Bake LT gen/planet.glsl height/color/clouds → equirect RGB map (TexCube stand-in).
## R=height, G=color field, B=clouds — sampled by planet.gdshader when use_bake=1.
class_name PlanetBake
extends RefCounted

static var _cache: Dictionary = {}


static func bake_equirect(
	seed_offset: float,
	freq: float = 4.0,
	power: float = 1.35,
	coef: Vector4 = Vector4(1, 1, 1, 1),
	width: int = 384,
	height: int = 192
) -> ImageTexture:
	var key := "planet_bake:%.4f:%d:%d" % [seed_offset, width, height]
	if _cache.has(key):
		return _cache[key]

	var img := Image.create(width, height, false, Image.FORMAT_RGBF)
	for y in height:
		var v := (float(y) + 0.5) / float(height)
		var theta := v * PI
		var sin_t := sin(theta)
		var cos_t := cos(theta)
		for x in width:
			var u := (float(x) + 0.5) / float(width)
			var phi := u * TAU - PI
			var dir := Vector3(sin_t * cos(phi), cos_t, sin_t * sin(phi)).normalized()
			var h := _gen_height(dir, seed_offset, freq, power, coef)
			var c := _gen_color(dir, seed_offset, coef)
			var cl := _gen_clouds(dir, seed_offset)
			img.set_pixel(x, y, Color(h, c, cl))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func _frac(x: float) -> float:
	return x - floorf(x)


static func _hash31(p: Vector3, seed_offset: float) -> float:
	var q := Vector3(_frac(p.x * 0.1031 + seed_offset), _frac(p.y * 0.1031), _frac(p.z * 0.1031))
	var d := q.dot(Vector3(q.y, q.z, q.x) + Vector3(33.33, 33.33, 33.33))
	return _frac((q.x + q.y) * q.z + d)


static func _noise1(x: float, seed_offset: float) -> float:
	return _hash31(Vector3(x, x * 1.7, seed_offset), seed_offset)


static func _noise4(x: float, seed_offset: float) -> float:
	return _hash31(Vector3(x * 0.13, x * 0.37 + 2.1, seed_offset + 5.8), seed_offset)


static func _cell_n(p: Vector3, s: float, seed_offset: float) -> float:
	var i := Vector3(floorf(p.x), floorf(p.y), floorf(p.z))
	var f := p - i
	var dmin := 8.0
	for xo in range(-1, 2):
		for yo in range(-1, 2):
			for zo in range(-1, 2):
				var g := i + Vector3(xo, yo, zo)
				var h := Vector3(
					_hash31(g + Vector3(s, 0, 0), seed_offset),
					_hash31(g + Vector3(s + 1.7, 0, 0), seed_offset),
					_hash31(g + Vector3(s + 3.1, 0, 0), seed_offset)
				)
				var r := Vector3(xo, yo, zo) + h - f
				dmin = minf(dmin, r.length_squared())
	return clampf(1.0 - sqrt(dmin), 0.0, 1.0)


static func _gain(x: float, k: float) -> float:
	var t := x if x < 0.5 else 1.0 - x
	var a := 0.5 * pow(2.0 * t, k)
	return a if x < 0.5 else 1.0 - a


static func _gen_height(p: Vector3, seed_offset: float, freq: float, power: float, coef: Vector4) -> float:
	var z := Vector4(p.x / 4.0 + 0.75, p.y / 4.0 + 0.75, p.z / 4.0 + 0.75, 0.3)
	var a := 0.0
	var l := 0.0
	var w := 1.0
	for i in 24:
		var m := z.dot(z)
		z = Vector4(absf(z.x), absf(z.y), absf(z.z), absf(z.w)) / maxf(m, 1e-4) - Vector4(0.4, 0.5, 0.6, 0.3)
		var n4 := log(1.0e-10 + _noise4(float(i) + seed_offset, seed_offset))
		z += Vector4(0.1 * n4, 0.1 * n4, 0.1 * n4, 0.1 * n4)
		z *= 1.0 + 0.25 * _noise1(float(i) + seed_offset * 2.0 + 32.0, seed_offset)
		z = Vector4(z.y, z.z, z.w, z.x)
		m = coef.x * z.x * z.x + coef.y * z.y * z.y + coef.z * z.z * z.z + coef.w * z.w * z.w
		if i > 0:
			a += w * exp(-absf(m - l))
			w *= 0.8 + 0.2 * (2.0 * _noise1(seed_offset + 3.3 * float(i), seed_offset) - 1.0)
		l = m
	return _gain(pow(0.5 + 0.5 * sin(freq * a), power), 4.0)


static func _gen_color(p: Vector3, seed_offset: float, coef: Vector4) -> float:
	var z := Vector4(p.x / 4.0 + 0.75, p.y / 4.0 + 0.75, p.z / 4.0 + 0.75, 0.3)
	var a := 0.0
	var w := 1.0
	for i in 20:
		var m := z.dot(z)
		z = Vector4(absf(z.x), absf(z.y), absf(z.z), absf(z.w)) / maxf(m, 1e-4) - Vector4(0.4, 0.5, 0.6, 0.4)
		var n4 := log(1.0e-10 + _noise4(float(i) + seed_offset + 58.329, seed_offset))
		z += Vector4(0.1 * n4, 0.1 * n4, 0.1 * n4, 0.1 * n4)
		z *= 1.0 + 0.25 * _noise1(float(i) + seed_offset * 5.0 + 12.0, seed_offset)
		z = Vector4(z.y, z.z, z.w, z.x)
		m = coef.x * z.x * z.x + coef.y * z.y * z.y + coef.z * z.z * z.z + coef.w * z.w * z.w
		a += w * exp(-m)
		w *= 0.85
	return 0.5 + 0.5 * sin(4.0 * a)


static func _gen_clouds(p: Vector3, seed_offset: float) -> float:
	var q := p + 0.5 * Vector3(
		_cell_n(p * 2.2, seed_offset + 1.0, seed_offset),
		_cell_n(p * 2.2, seed_offset + 5.0, seed_offset),
		_cell_n(p * 2.2, seed_offset + 8.0, seed_offset)
	)
	return 0.5 + 0.5 * sin(8.0 * _cell_n(q * 1.4, seed_offset + 6.0, seed_offset))

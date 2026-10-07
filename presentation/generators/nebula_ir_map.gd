## Approximate LT envMap:genIRMap — luminance IR from nebula panorama bake.
## Used to tint/suppress stars by direction (starbg sit-in-gas).
class_name NebulaIRMap
extends RefCounted

var width: int = 0
var height: int = 0
var lum: PackedFloat32Array = PackedFloat32Array()
var tint_r: PackedFloat32Array = PackedFloat32Array()
var tint_g: PackedFloat32Array = PackedFloat32Array()
var tint_b: PackedFloat32Array = PackedFloat32Array()


static func from_bake(bake: Dictionary, ir_size: int = 256) -> NebulaIRMap:
	var m := NebulaIRMap.new()
	if not bool(bake.get("ok", false)):
		return m
	var src_w := int(bake["width"])
	var src_h := int(bake["height"])
	var rgba: PackedFloat32Array = bake["rgba"]
	if rgba.size() != src_w * src_h * 4:
		return m
	m.width = ir_size
	m.height = ir_size / 2
	var n := m.width * m.height
	m.lum.resize(n)
	m.tint_r.resize(n)
	m.tint_g.resize(n)
	m.tint_b.resize(n)
	for y in m.height:
		for x in m.width:
			var u := float(x) / float(m.width)
			var v := float(y) / float(m.height)
			var sx := clampi(int(u * float(src_w)), 0, src_w - 1)
			var sy := clampi(int(v * float(src_h)), 0, src_h - 1)
			var i := (sy * src_w + sx) * 4
			var r := float(rgba[i])
			var g := float(rgba[i + 1])
			var b := float(rgba[i + 2])
			var L := 0.299 * r + 0.587 * g + 0.114 * b
			var di := y * m.width + x
			m.lum[di] = L
			m.tint_r[di] = r
			m.tint_g[di] = g
			m.tint_b[di] = b
	return m


func sample_dir(dir: Vector3) -> Dictionary:
	if width <= 0 or height <= 0 or lum.is_empty():
		return {"lum": 0.0, "tint": Color(1, 1, 1)}
	var d := dir.normalized()
	var u := 0.5 + atan2(d.z, d.x) / TAU
	var v := acos(clampf(d.y, -1.0, 1.0)) / PI
	var x := clampi(int(u * float(width)) % width, 0, width - 1)
	var y := clampi(int(v * float(height)), 0, height - 1)
	var i := y * width + x
	return {
		"lum": float(lum[i]),
		"tint": Color(float(tint_r[i]), float(tint_g[i]), float(tint_b[i])),
	}


## Apply IR suppress+tint to a star colour (LT starbg spirit).
func modulate_star(dir: Vector3, col: Color, suppress: float = 0.55, tint_amt: float = 0.35) -> Color:
	var s := sample_dir(dir)
	var L := float(s["lum"])
	var tint: Color = s["tint"]
	var dim := 1.0 - suppress * clampf(L * 1.8, 0.0, 1.0)
	# Bright gems punch through gas more
	var punch := clampf(maxf(col.r, maxf(col.g, col.b)) / 1.5, 0.0, 1.0)
	dim = lerpf(dim, 1.0, punch * 0.55)
	var out := Color(col.r * dim, col.g * dim, col.b * dim, col.a)
	var tcol := Color(
		lerpf(1.0, maxf(tint.r * 2.2, 0.2), tint_amt),
		lerpf(1.0, maxf(tint.g * 2.2, 0.2), tint_amt),
		lerpf(1.0, maxf(tint.b * 2.2, 0.2), tint_amt)
	)
	return Color(out.r * tcol.r, out.g * tcol.g, out.b * tcol.b, out.a)

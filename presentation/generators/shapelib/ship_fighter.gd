## Limit Theory ShipFighter.Standard — ShapeLib port (no Settings UI).
## Source: JoshParnell/ltheory script/Gen/ShipFighter.lua
class_name ShapeLibShipFighter
extends RefCounted


static func standard(seed: int) -> ShapeLibShape:
	var rng := SeededRNG.new(seed)
	var shape := hull_standard(rng)
	var body_aabb: Dictionary = shape.get_aabb()
	# 75% classic wings, 25% TIE (LT Distribution)
	if rng.randf() < 0.75:
		shape.add_shape(wings_standard(rng, body_aabb))
	else:
		shape.add_shape(wings_tie(rng))
	shape.add_shape(wing_mounts(rng, body_aabb, int(rng.choose([3, 4, 6, 8, 10, 20]))))
	shape = shape.bevel(rng.randf_range(0.1, 0.8))
	var r := shape.get_radius()
	if r > 1e-4:
		var s := 3.0 / r
		shape.scale_xyz(s, s, s)
	return shape


static func standard_mesh(seed: int, hull_color: Color = Color(0.42, 0.42, 0.45)) -> ArrayMesh:
	return standard(seed).finalize_mesh(hull_color)


static func hull_standard(rng: SeededRNG) -> ShapeLibShape:
	var length := rng.randf_range(0.5, 3.0)
	var cxy := Vector2(rng.randf_range(0.1, 0.5), rng.randf_range(0.1, 0.5))
	var res: int = int(rng.choose([3, 4, 5, 6, 8, 10, 20, 24, 28, 30]))
	var r := 1.0
	# 85% prism, 15% would be sphere — keep prism as LT default weight for now
	var shape := ShapeLibBasic.prism(2, res)
	# LT: rotate(0, pi/2, 0) = yaw,pitch,roll → pitch 90°
	shape.rotate_ypr(0.0, PI * 0.5, 0.0)
	if res % 2 != 0:
		shape.rotate_ypr(0.0, 0.0, PI * 0.5)
	var pi := shape.get_poly_with_normal(Vector3(0, 0, 1))
	var t := PI
	var fwd := Vector3(0.0, sin(t), -cos(t))
	if pi >= 0:
		shape.extrude_poly(pi, length, Vector3(cxy.x, cxy.y, 1.0), fwd)
	var back := shape.get_poly_with_normal(Vector3(0, 0, -1))
	if back >= 0:
		shape.extrude_poly(back, 0.3, Vector3(0.5, 0.5, 0.5), Vector3(0.0, sin(t), cos(t)))
	shape.scale_xyz(r, r, 1.0)
	return shape


static func wings_standard(rng: SeededRNG, body_aabb: Dictionary) -> ShapeLibShape:
	var shape := ShapeLibShape.new()
	var n := rng.randi_range(1, 3)
	var upper: Vector3 = body_aabb["upper"]
	for _i in n:
		var wing1 := ShapeLibBasic.box(0)
		var l := rng.randf_range(0.5, 3.0)
		var w := rng.randf_range(0.5, 3.0)
		var point := rng.randf_range(0.05, 1.0)
		wing1.scale_xyz(0.1, 0.2, w)
		var pi1 := wing1.get_poly_with_normal(Vector3(1, 0, 0))
		if pi1 >= 0:
			wing1.extrude_poly(pi1, l, Vector3(1.0, rng.randf_range(0.05, 0.5), point))
		pi1 = wing1.get_poly_with_normal(Vector3(1, 0, 0))
		if pi1 >= 0:
			wing1.extrude_poly(pi1, 0.2, Vector3(1, 0.1, 1))
		if rng.randf() < 0.5:
			var winglet := wing1.clone().scale_xyz(0.5, 0.5, 0.5)
			var wabb: Dictionary = wing1.get_aabb()
			winglet.rotate_ypr(0.0, 0.0, rng.randf_range(0.0, PI))
			var wu: Vector3 = wabb["upper"]
			winglet.center_at(wu.x, 0.0, 0.0)
			wing1.add_shape(winglet)
		var x_pos := upper.x
		var roll := rng.randf_range(-PI * 0.5, PI * 0.5)
		var yaw := rng.randf_range(0.0, PI * 0.5)
		wing1.rotate_ypr(yaw, 0.0, roll)
		wing1.translate_xyz(x_pos, 0.0, 0.0)
		wing1.tessellate(rng.randi_range(0, 2))
		if wing1.polys.size() > 0:
			wing1.extrude_poly(rng.randi_range(0, wing1.polys.size() - 1), rng.randf_range(0.2, 1.0))
		var wing2 := wing1.clone()
		wing2.mirror_axes(true, false, false)
		shape.add_shape(wing1)
		shape.add_shape(wing2)
	return shape


static func wings_tie(rng: SeededRNG) -> ShapeLibShape:
	var shape := ShapeLibShape.new()
	var type: int = int(rng.choose([2, 3, 4, 5]))
	var wing: ShapeLibShape
	if type == 2:
		wing = ShapeLibBasic.prism(2, int(rng.choose([4, 5, 6, 8])))
	elif type == 3:
		wing = ShapeLibBasic.prism(2, 30)
	else:
		wing = ShapeLibBasic.prism(2, 6)
	var r := rng.randf_range(0.5, 3.0)
	var dist := 1.5 + rng.randf() * 0.8
	wing.scale_xyz(r, 0.1, r)
	wing.rotate_ypr(PI * 0.5, 0.0, PI * 0.5)
	wing.translate_xyz(dist, 0.0, 0.0)
	var connector := ShapeLibBasic.prism(2, 6)
	connector.rotate_ypr(0.0, 0.0, PI * 0.5)
	connector.scale_xyz(0.1, 1.0, 1.0)
	var cpi := connector.get_poly_with_normal(Vector3(1, 0, 0))
	if cpi >= 0:
		connector.extrude_poly(cpi, dist, Vector3(1, 0.5, 0.5))
	wing.add_shape(connector)
	var wing2 := wing.clone()
	wing2.mirror_axes(true, false, false)
	shape.add_shape(wing)
	shape.add_shape(wing2)
	return shape


static func wing_mounts(rng: SeededRNG, body_aabb: Dictionary, res: int) -> ShapeLibShape:
	var mount := ShapeLibBasic.prism(2, maxi(res, 3))
	mount.rotate_ypr(0.0, PI * 0.5, 0.0) # LT rotate(0, pi/2, 0)
	var r := clampf(rng.randf() * 0.2 + 0.5, 0.2, 1.0)
	var lower: Vector3 = body_aabb["lower"]
	var upper: Vector3 = body_aabb["upper"]
	var l := rng.randf_range(0.2, maxf(0.25, absf(upper.z - lower.z)))
	mount.scale_xyz(r, r, l)
	mount.translate_xyz(lower.x, 0.0, 0.0)
	# Default surface = bevel
	mount = mount.bevel(rng.randf_range(0.1, 1.0))
	var mount2 := mount.clone()
	mount2.mirror_axes(true, false, false)
	mount.add_shape(mount2)
	return mount

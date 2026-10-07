## Limit Theory ShapeLib.Joint — attach pose from a face (pos/dir/up/scale).
class_name ShapeLibJoint
extends RefCounted

var pos: Vector3 = Vector3.ZERO
var dir: Vector3 = Vector3.UP
var up: Vector3 = Vector3.FORWARD
var scale: Vector3 = Vector3.ONE


static func from_poly(shape: ShapeLibShape, poly: Array) -> ShapeLibJoint:
	var j := ShapeLibJoint.new()
	if not j.generate_from_poly(shape, poly):
		return null
	return j


func generate_from_poly(shape: ShapeLibShape, poly: Array) -> bool:
	var normal: Variant = shape.get_face_normal(poly)
	if normal == null:
		return false
	var n: Vector3 = normal
	if n.length_squared() < 1e-12:
		return false
	pos = shape.get_face_center(poly)
	dir = n
	if poly.is_empty():
		return false
	var edge: Vector3 = shape.get_vertex(int(poly[0])) - pos
	if edge.length_squared() < 1e-12:
		up = Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	else:
		up = edge.normalized()
	scale = Vector3.ONE
	return valid()


func valid() -> bool:
	return dir.length_squared() > 1e-12 and up.length_squared() > 1e-12


## Orient + place `part` onto this joint (LT attachJoint spirit).
func attach_shape(part: ShapeLibShape) -> void:
	part.center_at()
	# Build basis: dir = outward normal (Y), up ≈ poly edge (Z), right = cross
	var y_axis := dir.normalized()
	var z_axis := up.normalized()
	var x_axis := y_axis.cross(z_axis)
	if x_axis.length_squared() < 1e-12:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	z_axis = x_axis.cross(y_axis).normalized()
	var basis := Basis(x_axis, y_axis, z_axis)
	for i in part.verts.size():
		var v: Vector3 = part.verts[i]
		v = Vector3(v.x * scale.x, v.y * scale.y, v.z * scale.z)
		part.verts[i] = basis * v + pos

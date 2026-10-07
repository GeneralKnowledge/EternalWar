## Limit Theory ShapeLib.BasicShapes — Box / Prism (JoshParnell/ltheory).
class_name ShapeLibBasic
extends RefCounted


static func box(res: int = 1) -> ShapeLibShape:
	if res < 0:
		res = 0
	var shape := ShapeLibShape.new()
	shape.add_vertex(-1, 1, -1) # 0
	shape.add_vertex(1, 1, -1) # 1
	shape.add_vertex(-1, 1, 1) # 2
	shape.add_vertex(1, 1, 1) # 3
	shape.add_vertex(-1, -1, -1) # 4
	shape.add_vertex(1, -1, -1) # 5
	shape.add_vertex(-1, -1, 1) # 6
	shape.add_vertex(1, -1, 1) # 7
	shape.add_quad(0, 2, 3, 1) # top
	shape.add_quad(4, 5, 7, 6) # bottom
	shape.add_quad(3, 7, 5, 1)
	shape.add_quad(0, 4, 6, 2)
	shape.add_quad(2, 6, 7, 3)
	shape.add_quad(0, 1, 5, 4)
	return shape.tessellate(res)


static func prism(stacks: int = 2, slices: int = 3) -> ShapeLibShape:
	if stacks < 2:
		stacks = 2
	if slices < 3:
		slices = 3
	var shape := ShapeLibShape.new()
	for i in stacks:
		var y := float(i) / float(stacks - 1) - 0.5
		for j in slices:
			var t := TAU * float(j) / float(slices)
			shape.add_vertex(cos(t) * 0.5, y, sin(t) * 0.5)
	# Top cap
	var top: Array = []
	for i in slices:
		top.append(i)
	shape.add_poly(top)
	# Bottom cap (opposite winding)
	var bottom: Array = []
	var offset := (stacks - 1) * slices
	for i in range(slices - 1, -1, -1):
		bottom.append(offset + i)
	shape.add_poly(bottom)
	# Side quads
	for stack in range(stacks - 1):
		for slice in slices:
			shape.add_quad(
				stack * slices + slice,
				(stack + 1) * slices + slice,
				(stack + 1) * slices + (slice + 1) % slices,
				stack * slices + (slice + 1) % slices
			)
	return shape

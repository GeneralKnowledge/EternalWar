## Limit Theory Station.GenerateStation — active path (greebled box).
## Source: JoshParnell/ltheory script/Gen/Station.lua (`if true` branch).
class_name ShapeLibStation
extends RefCounted


static func generate(seed: int) -> ShapeLibShape:
	var rng := SeededRNG.new(seed)
	var shape := ShapeLibBasic.box(1)
	shape.greeble(rng, 2, 0.01, 0.05, 1.0, 1.0)
	return shape


static func generate_mesh(seed: int, color: Color = Color(0.5, 0.48, 0.45)) -> ArrayMesh:
	return generate(seed).finalize_mesh(color)

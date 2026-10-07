## Limit Theory ShapeLib.Style — favored warps by aesthetic style.
## Simplified: no Parametric/Torus; maps EW style strings → warp lottery.
class_name ShapeLibStyle
extends RefCounted

var rng: SeededRNG
var style_name: String = "civilian"
var favored_warps: Array = [] # Array of String warp ids


static func from_style(style: String, seed: int) -> ShapeLibStyle:
	var s := ShapeLibStyle.new()
	s.rng = SeededRNG.new(SeedHash.derive(seed, "shapelib_style"))
	s.style_name = style
	s._seed_favored()
	return s


func _seed_favored() -> void:
	favored_warps.clear()
	match style_name:
		"military", "pirate":
			favored_warps = ["stellate", "extrude", "bevel"]
		"mining", "industrial":
			favored_warps = ["greeble", "extrude", "bevel"]
		"luxury":
			favored_warps = ["bevel", "bevel", "extrude"]
		_:
			favored_warps = ["bevel", "extrude", "stellate"]


## Apply a favored (90%) or random warp — LT Style:getWarp spirit.
func apply_warp(shape: ShapeLibShape) -> ShapeLibShape:
	var id: String
	if rng.randf() < 0.9 and not favored_warps.is_empty():
		id = str(rng.choose(favored_warps))
	else:
		id = str(rng.choose(["bevel", "extrude", "stellate", "greeble"]))
	match id:
		"stellate":
			shape.stellate(rng.randf() * 0.5)
			return shape
		"extrude":
			shape.extrude_all(rng.randf() * 0.5)
			return shape
		"greeble":
			shape.greeble(rng, 1, 0.01, 0.05)
			return shape
		_:
			return shape.bevel(rng.randf_range(0.1, 0.8))

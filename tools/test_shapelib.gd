extends MainLoop

var _frames := 0

func _initialize() -> void:
	print("SHAPE_TEST_BEGIN")

func _process(_dt: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	var f := ShapeLibShipFighter.standard(42)
	print("fighter verts=", f.get_vertex_count(), " polys=", f.polys.size(), " r=", f.get_radius())
	var fm := f.finalize_mesh(Color(0.4, 0.4, 0.45))
	print("fighter mesh surfaces=", fm.get_surface_count())
	if fm.get_surface_count() > 0:
		var arr = fm.surface_get_arrays(0)
		print("fighter tris=", arr[Mesh.ARRAY_VERTEX].size() / 3)
	var s := ShapeLibStation.generate(7)
	print("station verts=", s.get_vertex_count(), " polys=", s.polys.size())
	var am := ShapeLibAsteroid.generate_mesh(99, 1)
	print("asteroid surfaces=", am.get_surface_count())
	var design := {
		"seed": 42,
		"ship_class": SimEntities.ShipClass.PATROL,
		"style": "military",
		"color": Color(0.4, 0.4, 0.45),
	}
	var sm := ShipMeshGen.build(design, VisualLOD.LOD_FULL)
	print("ShipMeshGen patrol surfaces=", sm.get_surface_count())
	var cap := ShapeLibShipCapital.sausage(11)
	print("capital verts=", cap.get_vertex_count(), " polys=", cap.polys.size(), " r=", cap.get_radius())
	var hauler := {
		"seed": 11,
		"ship_class": SimEntities.ShipClass.HAULER,
		"style": "industrial",
		"color": Color(0.38, 0.36, 0.34),
	}
	var hm := ShipMeshGen.build(hauler, VisualLOD.LOD_FULL)
	print("ShipMeshGen hauler surfaces=", hm.get_surface_count())
	print("SHAPE_TEST_DONE")
	return true

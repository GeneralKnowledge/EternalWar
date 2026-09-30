class_name Starfield
extends Node3D

## Efficient starfield using MultiMeshInstance3D — not thousands of Node3Ds.

@export var star_count: int = 1200
@export var radius: float = 8000.0


func _ready() -> void:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = star_count

	var mesh := SphereMesh.new()
	mesh.radius = 2.5
	mesh.height = 5.0
	mesh.radial_segments = 4
	mesh.rings = 2
	mm.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.85, 0.9, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.85, 1.0)
	mat.emission_energy_multiplier = 1.2
	mmi.material_override = mat
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

	for i in range(star_count):
		var dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		var dist := randf_range(radius * 0.35, radius)
		var pos := dir * dist
		var s := randf_range(0.6, 3.5)
		var xf := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), pos)
		mm.set_instance_transform(i, xf)

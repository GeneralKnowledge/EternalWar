class_name Starfield
extends Node3D

## Efficient starfield using MultiMeshInstance3D — not thousands of Node3Ds.

@export var star_count: int = 1800
@export var radius: float = 12000.0


func _ready() -> void:
	_build_layer(star_count, radius, 1.5, 5.0, 1.4)
	# Nearer brighter layer for motion parallax
	_build_layer(int(star_count * 0.25), radius * 0.45, 2.0, 7.0, 2.0)


func _build_layer(count: int, rad: float, scale_min: float, scale_max: float, energy: float) -> void:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = count

	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 4
	mesh.rings = 2
	mm.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.9, 0.93, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.85, 0.9, 1.0)
	mat.emission_energy_multiplier = energy
	mat.disable_receive_shadows = true
	mmi.material_override = mat
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

	for i in range(count):
		var dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
		if dir.length_squared() < 0.001:
			dir = Vector3.FORWARD
		dir = dir.normalized()
		var dist := randf_range(rad * 0.25, rad)
		var pos := dir * dist
		var s := randf_range(scale_min, scale_max)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), pos))

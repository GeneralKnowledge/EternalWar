class_name ExplosionEffect
extends Node3D

## Lightweight stylised explosion from particles + flash + expanding sphere.

var team_color: Color = Color(1, 0.6, 0.2)
var duration: float = 1.2
var _age: float = 0.0
var _sphere: MeshInstance3D
var _light: OmniLight3D
var _particles: GPUParticles3D


func _ready() -> void:
	_sphere = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	_sphere.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(team_color.r, team_color.g, team_color.b, 0.85)
	mat.emission_enabled = true
	mat.emission = team_color
	mat.emission_energy_multiplier = 8.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_sphere.material_override = mat
	add_child(_sphere)

	_light = OmniLight3D.new()
	_light.light_color = team_color
	_light.light_energy = 8.0
	_light.omni_range = 40.0
	add_child(_light)

	_particles = GPUParticles3D.new()
	_particles.emitting = true
	_particles.one_shot = true
	_particles.explosiveness = 0.95
	_particles.amount = 28
	_particles.lifetime = 0.7
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 20.0
	pm.initial_velocity_max = 60.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.2
	pm.scale_max = 0.8
	pm.color = team_color
	_particles.process_material = pm
	var draw := BoxMesh.new()
	draw.size = Vector3(0.4, 0.4, 0.4)
	_particles.draw_pass_1 = draw
	add_child(_particles)


func _process(delta: float) -> void:
	_age += delta
	var t := _age / duration
	var scale_val := lerpf(1.0, 18.0, ease(t, 0.4))
	_sphere.scale = Vector3.ONE * scale_val
	if _sphere.material_override is StandardMaterial3D:
		var mat := _sphere.material_override as StandardMaterial3D
		mat.albedo_color.a = lerpf(0.85, 0.0, t)
		mat.emission_energy_multiplier = lerpf(8.0, 0.0, t)
	_light.light_energy = lerpf(8.0, 0.0, t)
	if _age >= duration:
		queue_free()

## Main entry: owns simulation, presentation, player, and debug HUD.
extends Node3D

@export var world_seed: int = 42
@export var ship_count: int = 400
@export var time_scale: float = 1.0

var sim: StarSystemSim
var presenter: SystemPresenter
var player: PlayerController
var overlay: DebugOverlay
var camera: Camera3D


func _ready() -> void:
	camera = Camera3D.new()
	camera.far = 50000.0
	camera.near = 0.5
	camera.fov = 70.0
	add_child(camera)
	camera.current = true

	sim = StarSystemSim.new()
	sim.generate(world_seed, ship_count)

	presenter = SystemPresenter.new()
	add_child(presenter)
	presenter.setup(sim, camera)

	player = PlayerController.new()
	add_child(player)
	player.setup(sim, camera)

	overlay = DebugOverlay.new()
	add_child(overlay)
	overlay.setup(sim, player, presenter)

	var star: Dictionary = sim.world["star"]
	print("Generated system '%s' seed=%d star=%s planets=%d stations=%d ships=%d" % [
		sim.world["name"], world_seed, star.get("star_type", "?"),
		sim.world["planets"].size(), sim.world["stations"].size(), sim.world["ships"].size()
	])


func _physics_process(dt: float) -> void:
	if sim == null:
		return
	sim.tick(dt * time_scale)

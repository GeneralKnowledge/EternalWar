## Main entry: owns simulation, presentation, player, and debug HUD.
## Visual debug: F3 pause, [ / ] seed, R regenerate, F5 showcase mode note.
extends Node3D

@export var world_seed: int = 42
@export var ship_count: int = 400
@export var time_scale: float = 1.0

var sim: StarSystemSim
var presenter: SystemPresenter
var player: PlayerController
var overlay: DebugOverlay
var camera: Camera3D
var paused: bool = false


func _ready() -> void:
	camera = Camera3D.new()
	camera.far = 50000.0
	camera.near = 0.5
	camera.fov = 70.0
	add_child(camera)
	camera.current = true
	_boot_world()


func _boot_world() -> void:
	if presenter != null:
		presenter.queue_free()
		presenter = null
	if player != null:
		player.queue_free()
		player = null
	if overlay != null:
		overlay.queue_free()
		overlay = null

	sim = StarSystemSim.new()
	sim.generate(world_seed, ship_count)

	presenter = SystemPresenter.new()
	add_child(presenter)
	presenter.setup(sim, camera)

	player = PlayerController.new()
	add_child(player)
	player.setup(sim, camera, presenter)

	overlay = DebugOverlay.new()
	add_child(overlay)
	overlay.setup(sim, player, presenter)
	if overlay.has_method("set_paused"):
		overlay.set_paused(paused)

	var star: Dictionary = sim.world["star"]
	var sky: Dictionary = sim.world.get("sky_composition", {})
	print("Generated system '%s' seed=%d star=%s mood=%s planets=%d stations=%d ships=%d" % [
		sim.world["name"], world_seed, star.get("star_type", "?"),
		str(sky.get("mood", "?")),
		sim.world["planets"].size(), sim.world["stations"].size(), sim.world["ships"].size()
	])


func _physics_process(dt: float) -> void:
	if sim == null:
		return
	if overlay != null and overlay.paused:
		return
	sim.tick(dt * time_scale)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_BRACKETLEFT:
				world_seed = maxi(1, world_seed - 1)
				_boot_world()
			KEY_BRACKETRIGHT:
				world_seed += 1
				_boot_world()
			KEY_R:
				_boot_world()
			KEY_F5:
				get_tree().change_scene_to_file("res://scenes/visual_showcase.tscn")

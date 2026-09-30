extends Node

## Placeholder audio system — easily replaceable with real assets later.

var _enabled: bool = true
var _players: Array[AudioStreamPlayer3D] = []
var _bus_index: int = 0


func _ready() -> void:
	# Generate tiny procedural beep streams so the game has feedback without assets.
	pass


func play_laser(at: Vector3) -> void:
	if not _enabled:
		return
	_play_tone(at, 880.0, 0.04, -12.0)


func play_explosion(at: Vector3) -> void:
	if not _enabled:
		return
	_play_tone(at, 90.0, 0.25, -6.0)


func play_boost() -> void:
	pass


func play_warning() -> void:
	_play_tone(Vector3.ZERO, 440.0, 0.1, -8.0, false)


func _play_tone(at: Vector3, freq: float, duration: float, volume_db: float, spatial: bool = true) -> void:
	# Procedural audio via AudioStreamGenerator would be heavier; keep silent-safe stubs.
	# If AudioStreamWAV generation is desired later, hook it here.
	# For MVP we intentionally no-op unless a stream exists — avoids dependency on assets.
	# Using a light click via system is optional; prefer silence over broken audio.
	var _f := freq
	var _d := duration
	var _v := volume_db
	var _a := at
	var _s := spatial
	# Intentionally empty placeholder.
	pass

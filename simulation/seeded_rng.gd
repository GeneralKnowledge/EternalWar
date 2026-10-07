## Deterministic seeded RNG for procedural generation and reproducible sim tests.
## IMPORTANT: Never call bare randf()/randi() inside this class — those resolve to
## GlobalScope's non-seeded RNG in GDScript. Always use _rng.* or self.*.
class_name SeededRNG
extends RefCounted

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var seed_value: int = 0


func _init(p_seed: int = 0) -> void:
	reseed(p_seed)


func reseed(p_seed: int) -> void:
	seed_value = p_seed
	_rng.seed = p_seed as int


func randf() -> float:
	return _rng.randf()


func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)


func randi() -> int:
	return _rng.randi()


func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


func randfn(mean: float = 0.0, deviation: float = 1.0) -> float:
	return _rng.randfn(mean, deviation)


## Unit-mean exponential draw (LT `RNG:getExp()`): −ln(U), U∈(0,1].
func exp_rand() -> float:
	var u := clampf(_rng.randf(), 1e-7, 1.0)
	return -log(u)


## Unit vector in XZ plane (y = 0).
func dir2() -> Vector3:
	var a: float = _rng.randf() * TAU
	return Vector3(cos(a), 0.0, sin(a))


## Unit vector on sphere.
func dir3() -> Vector3:
	var z: float = _rng.randf_range(-1.0, 1.0)
	var a: float = _rng.randf() * TAU
	var r: float = sqrt(maxf(0.0, 1.0 - z * z))
	return Vector3(r * cos(a), z, r * sin(a))


func choose(options: Array) -> Variant:
	if options.is_empty():
		return null
	return options[_rng.randi_range(0, options.size() - 1)]


## Derive a child seed from this RNG (consumes one randi).
func next_seed() -> int:
	return _rng.randi()


static func combine_seeds(a: int, b: int) -> int:
	# Simple deterministic mix; stable across platforms for int32-ish values.
	var x := (a ^ (b * 0x9E3779B9)) & 0x7FFFFFFF
	if x == 0:
		x = 1
	return x

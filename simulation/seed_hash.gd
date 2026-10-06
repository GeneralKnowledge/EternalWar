## Hierarchical deterministic seed derivation.
## Child seeds are independent of generation order.
class_name SeedHash
extends RefCounted


## Derive a stable child seed from a parent seed and a string tag.
static func derive(parent_seed: int, tag: String) -> int:
	var h: int = int(hash("%d|%s" % [parent_seed, tag]))
	h = h & 0x7FFFFFFF
	if h == 0:
		h = 1
	return h


static func derive_i(parent_seed: int, tag: String, index: int) -> int:
	return derive(parent_seed, "%s:%d" % [tag, index])


static func make_rng(parent_seed: int, tag: String) -> SeededRNG:
	return SeededRNG.new(derive(parent_seed, tag))


static func make_rng_i(parent_seed: int, tag: String, index: int) -> SeededRNG:
	return SeededRNG.new(derive_i(parent_seed, tag, index))

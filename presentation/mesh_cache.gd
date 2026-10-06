## Shared ArrayMesh cache keyed by design seed / role strings.
class_name MeshCache
extends RefCounted

static var _meshes: Dictionary = {}
static var _hits: int = 0
static var _misses: int = 0


static func get_mesh(key: String) -> Mesh:
	if _meshes.has(key):
		_hits += 1
		return _meshes[key]
	return null


static func store(key: String, mesh: Mesh) -> Mesh:
	_misses += 1
	_meshes[key] = mesh
	return mesh


static func clear() -> void:
	_meshes.clear()
	_hits = 0
	_misses = 0


static func stats() -> Dictionary:
	return {"entries": _meshes.size(), "hits": _hits, "misses": _misses}

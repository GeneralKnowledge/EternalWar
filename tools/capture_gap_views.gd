## Capture key visual views for gap before/after comparison.
## Usage: godot --rendering-driver opengl3 -s tools/capture_gap_views.gd -- --tag=before|after
extends SceneTree

const OUT := "/opt/cursor/artifacts/screenshots"
const VIEWS := [
	{"id": "nebula_planet", "focus": "planet", "dist": 380.0},
	{"id": "star_system", "focus": "star", "dist": 900.0},
	{"id": "ship_near", "focus": "ship", "dist": 55.0},
	{"id": "asteroid_field", "focus": "yield", "dist": 220.0},
]

var _tag := "after"
var _root: Node3D
var _cam: Camera3D
var _presenter: SystemPresenter
var _sim: StarSystemSim
var _vp: SubViewport
var _queue: Array = []
var _frames := 0
var _ready := false
var _current: Dictionary = {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			_tag = a.substr(6)
	print("GAP_CAPTURE_BEGIN tag=", _tag)
	DirAccess.make_dir_recursive_absolute(OUT)

	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.transparent_bg = false
	root.add_child(_vp)

	_root = Node3D.new()
	_vp.add_child(_root)

	_cam = Camera3D.new()
	_cam.current = true
	_cam.fov = 55.0
	_cam.far = 50000.0
	_cam.near = 0.2
	_root.add_child(_cam)

	_sim = StarSystemSim.new()
	_sim.generate(42, 120)
	_presenter = SystemPresenter.new()
	_root.add_child(_presenter)
	_presenter.setup(_sim, _cam)
	# Advance FX so pulse/explosion are mid-cycle in captures.
	_presenter._fx_age = 0.85
	_presenter.sync_ships()

	for v in VIEWS:
		_queue.append(v)
	_advance()
	_ready = true


func _focus_pos(kind: String) -> Vector3:
	match kind:
		"planet":
			return _presenter.get_planet_focus()
		"star":
			var star: Dictionary = _sim.world.get("star", {})
			return star.get("position", Vector3.ZERO)
		"ship":
			var ships: Array = _sim.world.get("ships", [])
			if ships.is_empty():
				return Vector3(80, 20, 60)
			return ships[0].get("position", Vector3(80, 20, 60))
		"yield":
			var ys: Array = _sim.world.get("yields", [])
			if ys.is_empty():
				return Vector3(400, 0, 400)
			return ys[0].get("position", Vector3(400, 0, 400))
		_:
			return Vector3.ZERO


func _advance() -> void:
	if _queue.is_empty():
		print("GAP_CAPTURE_DONE tag=", _tag)
		quit()
		return
	_current = _queue.pop_front()
	var focus := _focus_pos(str(_current["focus"]))
	var dist := float(_current["dist"])
	var offset := Vector3(dist * 0.55, dist * 0.22, dist * 0.75)
	if str(_current["focus"]) == "star":
		offset = Vector3(dist * 0.4, dist * 0.15, dist * 0.5)
		# Look past star into nebula
		_cam.look_at_from_position(focus + offset, focus + Vector3(2000, 400, -800), Vector3.UP)
	else:
		_cam.look_at_from_position(focus + offset, focus, Vector3.UP)
	_frames = 0
	print("CAPTURE ", _current["id"], " focus=", focus)


func _process(_dt: float) -> bool:
	if not _ready:
		return false
	_frames += 1
	if _frames < 14:
		return false
	if _current.is_empty():
		return false
	var path := "%s/gap_%s_%s.png" % [OUT, _tag, str(_current["id"])]
	var tex := _vp.get_texture()
	if tex != null:
		var img := tex.get_image()
		if img != null:
			img.save_png(path)
			print("WROTE ", path)
	_current = {}
	_advance()
	return false

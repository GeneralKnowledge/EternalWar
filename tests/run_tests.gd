extends SceneTree

## Headless test runner for non-visual MVP systems.
## Run: godot --headless --path . -s res://tests/run_tests.gd

var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	print("=== Eternal Battle MVP Tests ===")
	_test_shield_absorbs_damage()
	_test_damage_transfers_to_hull()
	_test_fighter_destruction()
	_test_friendly_fire_prevented_logic()
	_test_target_selection_helpers()
	_test_teams()
	_test_projectile_pool()
	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  PASS: ", msg)
	else:
		_failed += 1
		print("  FAIL: ", msg)


func _make_ship(team: int = Teams.Side.FRIENDLY) -> Ship:
	var s := Ship.new()
	s.team = team
	s.max_health = 100.0
	s.max_shield = 50.0
	s.health = 100.0
	s.shield = 50.0
	s.is_alive = true
	return s


func _test_shield_absorbs_damage() -> void:
	print("-- shields absorb damage --")
	var s := _make_ship()
	s.take_damage(30.0)
	_assert(is_equal_approx(s.shield, 20.0), "shield reduced by 30")
	_assert(is_equal_approx(s.health, 100.0), "hull untouched while shield remains")
	s.free()


func _test_damage_transfers_to_hull() -> void:
	print("-- damage transfers to hull --")
	var s := _make_ship()
	s.take_damage(70.0) # 50 shield + 20 hull
	_assert(is_equal_approx(s.shield, 0.0), "shield depleted")
	_assert(is_equal_approx(s.health, 80.0), "20 damage to hull")
	s.free()


func _test_fighter_destruction() -> void:
	print("-- fighter destroyed at zero health --")
	var s := _make_ship()
	var state := {"destroyed": false}
	s.destroyed.connect(func(_ship: Ship): state["destroyed"] = true)
	s.take_damage(200.0)
	_assert(not s.is_alive, "ship marked not alive")
	_assert(state["destroyed"] == true, "destroyed signal emitted")
	_assert(s.health <= 0.0, "health at or below zero")
	# Base Ship.queue_free via _play_destruction; ensure cleanup if still valid
	if is_instance_valid(s):
		s.free()


func _test_friendly_fire_prevented_logic() -> void:
	print("-- friendly fire team check --")
	_assert(not Teams.is_enemy(Teams.Side.FRIENDLY, Teams.Side.FRIENDLY), "same team not enemy")
	_assert(Teams.is_enemy(Teams.Side.FRIENDLY, Teams.Side.ENEMY), "opposite teams are enemies")


func _test_target_selection_helpers() -> void:
	print("-- target distance helper --")
	var a := Node3D.new()
	var b := Node3D.new()
	root.add_child(a)
	root.add_child(b)
	a.global_position = Vector3.ZERO
	b.global_position = Vector3(3000, 0, 0)
	var d := TargetSystem.distance_to(a, b)
	_assert(is_equal_approx(d, 3000.0), "distance between nodes is 3000")
	a.queue_free()
	b.queue_free()


func _test_teams() -> void:
	print("-- teams helpers --")
	_assert(Teams.opposite(Teams.Side.FRIENDLY) == Teams.Side.ENEMY, "opposite of friendly is enemy")
	_assert(Teams.side_name(Teams.Side.ENEMY) == "ENEMY", "side name")


func _test_projectile_pool() -> void:
	print("-- projectile pool --")
	Projectile.clear_pool()
	var p1 := Projectile.acquire()
	var p2 := Projectile.acquire()
	_assert(p1 != p2, "acquire returns distinct instances when pool empty")
	Projectile.release(p1)
	var p3 := Projectile.acquire()
	_assert(p3 == p1, "released projectile is reused")
	Projectile.release(p2)
	Projectile.release(p3)
	Projectile.clear_pool()

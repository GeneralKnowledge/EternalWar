class_name Teams
extends RefCounted

## Team identifiers for the two-sided eternal battle.
enum Side {
	FRIENDLY,
	ENEMY,
}


static func opposite(side: int) -> int:
	return Side.ENEMY if side == Side.FRIENDLY else Side.FRIENDLY


static func side_name(side: int) -> String:
	return "FRIENDLY" if side == Side.FRIENDLY else "ENEMY"


static func is_enemy(a: int, b: int) -> bool:
	return a != b

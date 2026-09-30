# Eternal Battle

A playable Godot 4.x MVP: you are one fighter pilot inside a continuous 3D space battle between two battleships.

## Requirements

- Godot **4.3+** (Forward Plus)
- No external 3D assets or Blender required — ships are built from primitives at runtime

## Run

1. Open this folder in Godot 4.3+
2. Press **F5** (main scene: `scenes/main.tscn`)

Or from CLI:

```bash
godot --path . 
```

## Controls

| Input | Action |
|-------|--------|
| Mouse | Aim |
| W/A/S/D | Manoeuvre (strafe / vertical) |
| Space | Thrust |
| Shift | Boost |
| Left Mouse | Fire |
| R | Target nearest enemy |
| Tab | Cycle targets |
| Esc | Pause |
| F3 | Debug overlay |

Debug (with F3 overlay on): F5/F6 spawn fighters, F7 destroy target, F8 respawn, F9 reset battle.

## Tests

```bash
godot --headless --path . -s res://tests/run_tests.gd
```

## Architecture

```
Ship
├── Fighter
│   ├── PlayerFighter
│   └── (AI via FighterAI component)
└── Battleship
```

`BattleManager` tracks fleet counts and player respawn. Battleships maintain ~12 fighters each by gradually launching replacements. The battle never “ends.”

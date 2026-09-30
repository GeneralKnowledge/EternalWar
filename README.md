# Eternal Battle

A playable Godot 4.x MVP: you are one fighter pilot inside a continuous 3D space battle between two battleships.

## Requirements

- Godot **4.3+**
- No external 3D assets or Blender required — ships are built from primitives at runtime

## Run

1. Open this folder in Godot 4.3+
2. Press **F5** (main scene: `scenes/main.tscn`)

Or from CLI:

```bash
godot --path . --rendering-driver opengl3
```

## Flight model

BSGO-inspired Newtonian flight:

- **Mouse** turns the nose (attitude). Turning does **not** change your velocity by itself.
- **Space** lights the main engines. Release Space to cut engines and **coast**.
- While coasting you can flip around and keep your momentum (classic Raider slide).
- **C** reverse thrust, **WASD** strafe/vertical thrusters, **Shift** boost, **Q/E** roll.

## Controls

| Input | Action |
|-------|--------|
| Mouse | Aim / turn nose |
| Space | Main thrusters (hold) |
| C | Reverse thrusters |
| W/A/S/D | Strafe / vertical thrusters |
| Q / E | Roll |
| Shift | Boost (with Space) |
| Left Mouse | Fire |
| R | Target nearest enemy |
| Tab | Cycle targets |
| Esc | Pause |
| F3 | Debug overlay |
| F4 | Spectate / leave AI dogfight camera |

Debug (with F3 overlay on): F5/F6 spawn fighters, F7 destroy target, F8 respawn, F9 reset battle.

## Tests

```bash
godot --headless --path . -s res://tests/run_tests.gd
godot --path . --rendering-driver opengl3 -s res://tests/integration_battle.gd
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

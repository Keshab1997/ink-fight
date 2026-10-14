# Visual Concepts

These selected concept images establish the intended landscape UI direction. They are references for layout, contrast, hierarchy, and mood—not final production assets.

- `ink_fight_home.png` — main menu with Bot Fight as the first action.
- `ink_fight_battle.png` — Player vs Bot arena HUD and touch controls.
- `ink_fight_result.png` — victory/result screen with rematch flow.
- `player_ink_fighter_reference.png` — first AI-generated player concept reference.
- `bot_ink_brawler_reference.png` — first AI-generated bot concept reference.
- `player_ink_fighter_reference_clean.png` — cleaned player reference for frame generation.
- `bot_ink_brawler_reference_clean.png` — cleaned bot reference for frame generation.

The two clean character references are the locked starting point for animation prompts. The `frames/` folder contains the first AI-generated sample frames: idle, light punch, and heavy-kick contact references for both characters. They are still source references, not final transparent runtime sprites; background cleanup, baseline alignment, and animation frame generation follow the asset pipeline.

Production UI text, buttons, health bars, and accessibility states should be implemented in Flutter/Flame rather than baked into an image.

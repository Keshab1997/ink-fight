# Runtime Character Assets

Cleaned RGBA PNG frames belong in the character-specific folders here after background removal, baseline alignment, pivot validation, and animation review.

The current batch contains idle, light-punch contact, and heavy-kick contact samples for the player and black/crimson rival. The remaining MVP frames will be added using the same folders and naming convention.

To re-run the deterministic border-background cleanup after adding source frames:

```bash
python3 tool/process_character_assets.py
```

The release build must load only approved runtime assets, never the `assets/characters/originals/` archive.

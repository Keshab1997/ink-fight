# Sound effects

Placeholder cues for the fight, one file per row of the table in
`docs/technical/GAME_FEEL.md` §4. They are **synthesised by
`tool/generate_sfx.py`**, so the repository carries no third-party audio and
nothing here needs a licence review — regenerate any time with:

```bash
python3 tool/generate_sfx.py
```

| File | Cue (§4) | Length |
|---|---|---|
| `hit_light.wav` | light hit — short tick | 80 ms |
| `hit_heavy.wav` | heavy hit — low thud + ink splat tail | 420 ms |
| `blocked.wav` | blocked — wooden clack | 105 ms |
| `whoosh_light.wav` | jab start — thin whoosh | 170 ms |
| `whoosh_heavy.wav` | kick start — longer whoosh | 340 ms |
| `step_tap.wav` | jump / land — soft tap | 70 ms |
| `ko_gong.wav` | KO — gong, then silence | 1000 ms |
| `countdown_blip.wav` | countdown — blip (played ×3) | 110 ms |
| `round_sting.wav` | result — short sting | 450 ms |

Format: mono, 22050 Hz, 16-bit PCM, all under the 60 KB per-file budget the
document sets. They are deliberately plain — good enough to make the fight
audible and testable, meant to be replaced by recorded or designed audio when
someone wants to. If a file is replaced, keep the name: the code refers to the
cue, not to how it was made.

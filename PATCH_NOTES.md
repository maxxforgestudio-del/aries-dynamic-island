# Updating patch notes

Aries shows patch notes in **Settings › Patch Notes**. They load from
[`docs/patch-notes.json`](docs/patch-notes.json), which GitHub Pages serves at
https://maxxforgestudio-del.github.io/aries-dynamic-island/patch-notes.json, so you can post new notes
without releasing a new version of the app.

Every 1–2 weeks:

1. Add a new entry at the **top** of `entries` (newest first):
   ```json
   { "version": "2.0.1", "date": "2026-11-30", "title": "Bug fixes",
     "items": [ { "type": "fixed", "text": "What was fixed, in plain words." } ] }
   ```
   `type` is one of `new`, `improved`, `fixed`, `security`.
2. Update `knownIssues` (remove what's fixed, add anything new).
3. Change `updated` to today's date (`yyyy-MM-dd`). For a second change on the same day, use `2026-11-30.2`.
   This is what makes Aries show a "New Patch Notes" alert and a blue dot.
4. Commit and push to `main`. Copies of Aries pick it up within about 4 hours, or right away with Refresh.

The download page shows the same notes.

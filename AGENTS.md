# Agent Notes

Read `CONTRIBUTING.md` for setup, checks, changelog, and project rules. Notes here cover what an agent can't derive from the repo.

- Client context: the current retail client is the **Midnight** expansion (12.x, successor to The War Within); max player level is 90. Training data is stale for this client — don't trust it for level caps, item ids, or API behavior.
- For uncertain live-client behavior (API return values, item links, atlas names), ask the user to run a short in-game `/dump` — one or two copy-pasteable lines — instead of extended research or guessing.
- When wiki/community docs lack an API that Blizzard's own UI visibly uses, read the implementing frame in https://github.com/Gethe/wow-ui-source (branch `live`, `Interface/AddOns/Blizzard_*`) to find the call, then confirm it with a `/dump`.
- The add-on is symlinked into the AddOns folder per CONTRIBUTING → Setup, so repo edits are live in-game after a `/reload`.

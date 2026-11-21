# Contributing

## Branches
`main` (stable, demo) ← `develop` (integration) ← `feat/public-intake`, `feat/backend-core`,
`feat/admin-ops`, `feat/maps-integration`.

```bash
git checkout -b develop && git push -u origin develop
git checkout -b feat/<your-area> develop
```
- Small PRs into `develop` at every checkpoint (H2, H12, H24, H30, H36, H42). Don't wait until hour 40.
- `main` only receives from `develop` after the H42 rehearsal.

## Rules
1. One owner per module; others contribute via PR to the owner's area.
2. **No manual schema edits in the Supabase dashboard.** `supabase migration new <name>` and commit.
3. Never commit secrets. Service-role key lives only in `.env` / Edge Function secrets.
4. API responses are always `{ "data": ..., "error": ... }`. Timestamps UTC.
5. Demo data is fictional only. No real citizenship/licence photos.
6. After H36: feature freeze, P0/P1 bug fixes only.

## Commit style
`feat(mobile): ...`, `fix(supabase): ...`, `docs: ...`, `chore: ...`

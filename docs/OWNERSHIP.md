# Ownership (from the 48-hour plan)

| Person | Area | Folder | Key deliverables |
|---|---|---|---|
| 1 | Flutter / public UX | `apps/mobile` | Forms, validation, district picker, volunteer work list, map screen |
| 2 | Supabase / backend | `supabase/` | Schema, RLS, Edge Functions/RPC, OTP, atomic claim, inventory, API contract |
| 3 | Admin panel / ops | `apps/admin` | Review queue, inventory kanban, assignment board, incidents, audit timeline |
| 4 | Integration / QA / maps / deck | `docs/`, `scripts/`, CI | Seed/reset, FCM proof, map layers wiring, test matrix, slides, demo script |

Person 2 owns the canonical contract and migrations. Person 4 owns integration readiness and demo stability.

## Checkpoint gates
- H2: everyone can run their app; schema + API contract agreed
- H12: public form writes to Supabase; admin sees it
- H24: one resource delivery approved, assigned, progressed
- H30: donation pickup + quantity confirmation end-to-end
- H36: feature freeze
- H42: rehearsal on clean seeded state + backup video

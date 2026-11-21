
# Ownership

| Person | Name                         | Area                           | Folder                                              | Key deliverables                                                                 |
| ------ | ---------------------------- | ------------------------------ | --------------------------------------------------- | -------------------------------------------------------------------------------- |
| 1      | Saurav Maske                 | Flutter / public UX            | `apps/mobile`                                     | Forms, validation, district picker, volunteer work list, map screen              |
| 2      | Rujan Dhamala, Aakash Thakur | Supabase / backend             | `supabase/`                                       | Schema, RLS, Edge Functions and RPCs, OTP, atomic claim, inventory, API contract |
| 3      | Utsav Subedi                 | Admin panel / ops              | `apps/admin`                                      | Review queue, inventory kanban, assignment board, incidents, audit timeline      |
| 4      | Rujan Dhamala, Aakash Thakur | Integration / QA / maps / deck | `docs/`, `scripts/`, `.github/`, `postman/` | Seed and reset, FCM proof, map layers wiring, test matrix, slides, demo script   |

Person 2 owns the canonical contract and migrations. Person 4 owns integration readiness and demo stability.
Rujan Dhamala and Aakash Thakur cover both Person 2 and Person 4, so there is no hand-off between those roles. Decide between you who reviews whose PRs.

## Who to ask

| Question about                                  | Ask                                   |
| ----------------------------------------------- | ------------------------------------- |
| A table, RLS policy, Edge Function or RPC shape | Rujan Dhamala or Aakash Thakur        |
| Fields the Flutter form must send               | Saurav Maske, then the backend owners |
| What the admin panel needs to read or call      | Utsav Subedi                          |
| Seeding, reset, CI, test matrix, demo stability | Rujan Dhamala or Aakash Thakur        |

## Checkpoint gates

- H2: everyone can run their app; schema and API contract agreed
- H12: public form writes to Supabase; admin sees it
- H24: one resource delivery approved, assigned, progressed
- H30: donation pickup and quantity confirmation end-to-end
- H36: feature freeze
- H42: rehearsal on clean seeded state and backup video

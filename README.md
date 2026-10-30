# Simple Memo 2.0

HTML/CSS/ES modules + Supabase. GitHub Pages: https://hwan2277.github.io/simple-memo/

## Usage
- Without login: browser-local demo, isolated from real accounts.
- Account connection: existing passwordless email link login, unchanged callback URL.
- After login: memos, folders, tags, tasks are stored under the authenticated user in Supabase.
- Title/body, autosave (1 second), pin/favorite/color, search, folder/tag management, archive/trash/restore, linked and standalone tasks with deadlines.
- Plain text rendering. No user HTML is executed. A note requires nonempty body; title optional. Body max 20,000 characters. Up to 20 tags, 50 characters each.
- Notes from trash can be permanently deleted with explicit confirmation; attached tasks and tag links cascade. No scheduled deletion.
- No API secret/service-role key in browser. Publishable key is public by design.

## Development
Serve the repository with a static HTTP server (for example `python3 -m http.server 8080`). Production requires HTTPS.
Run `node tests/model.test.mjs`. There are no build dependencies.

## Database
`database/simple_memo_v2.sql` is the additive migration applied on 2026-10-30. It must run transactionally and once, not at each page load. `database/memo_tags_owner_index.sql` adds the relation index.
Original users and memo id/user_id/content/created_at preserved. RLS enabled for all 5 tables. Composite foreign keys prohibit cross-owner relationships. `save_memo_v2` runs as invoker, atomically changes note/tags, and checks version for concurrent changes.
Existing 1.0 frontend can still insert/read notes. Rollback frontend to commit e4bacb4f189eb9a1454403736b4e940f08c856b9 if necessary; do not drop new columns/tables because that would lose 2.0 data.

## Encryption decision
HTTPS protects transport; Supabase documents encryption at rest and in transit. RLS limits which user's rows the client can access. This is NOT end-to-end encryption: database administrators can read plaintext fields.
No custom browser encryption has been enabled. An optional locked-note feature would need authenticated encryption (AES-GCM), key derivation, key recovery policy, multi-device unlocking, and explicit handling of search/AI limits. Never store decryption keys beside ciphertext or describe base64 as encryption.
Source: https://supabase.com/docs/guides/deployment/shared-responsibility-model

## Limits
- Search currently fetches the user's data in 500-row pages and filters locally. Large collections need server-side search and visible pagination.
- Offline edits remain in the current editor; no persistent plaintext draft cache for signed-in users. Save failure and unload warnings are shown. A closed tab with unsaved edits can still lose data.
- Concurrent note writes are protected by optimistic version checks; after conflict, copy unsaved content and reload. Tasks use last-write-wins.
- Auth flow remains passwordless; SMTP/email deliverability is governed by existing project configuration. Login email delivery requires a real inbox check.
- Mobile CSS is included, but actual phone testing remains recommended.

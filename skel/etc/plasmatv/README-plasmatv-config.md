# /etc/plasmatv/

- `users-public.json` (world-readable, root:root 644) — id, display name,
  type (`adult`/`child`), avatar, daily time limit (child only), whether a
  PIN is set. No secrets in here — safe for the unprivileged selector-user
  to read directly.
- `users-secrets.json` (root:root 600) — PIN hashes (SHA-256, salted).
  Only ever read by root-run helper scripts (`plasmatv-verify-pin`,
  `plasmatv-set-pin`), never by the selector app itself.
- Slots `child-user-0` .. `child-user-15` are reserved usernames; only the
  ones present in `users-public.json` actually exist as Linux accounts.

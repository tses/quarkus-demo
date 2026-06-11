# Copilot Instructions

- Always review and align with the main project context in `README.md` before making changes.
- Each demo script is accompanied by a matching guide in `demo/` (for example: `scripts/07-probes.sh` <-> `demo/07-probes.md`).

## Demo script conventions (`scripts/`)

The scripts are meant to be run live in front of an audience, so they follow a
"explain before you run" presentation flow. Preserve these conventions:

- Source `demo-config.sh` at the top of every script and reuse its shared
  helpers and config (`source "$(dirname "$0")/demo-config.sh"`). Do not
  hard-code values that already live in `demo-config.sh`.
- Use the presentation helpers from `demo-config.sh`:
  - `header "..."` / `step "..."` / `ok "..."` / `warn "..."` for structured,
    colorized output.
  - `pause` to stop for pacing/explanation (waits for ENTER).
  - `show_cmd "..."` to display a command or YAML block in a box and wait for
    ENTER *before executing it*, so the presenter can explain what will run.
    After `show_cmd`, actually run the same command that was shown.
- Keep scripts **idempotent** (when doable): re-running a script should
  re-apply/re-check resources without erroring. Use patterns already in the
  repo, e.g. `oc apply`, `oc ... --ignore-not-found`, create-or-reuse guards
  (`oc project X || oc new-project X`), and `oc set ...` over imperative create.
- Start scripts with `set -euo pipefail`.
- Use `check_login` and `use_project` (or the relevant namespace) before acting
  on the cluster.

# Project notes for Claude

## Always give Brian a one-command install, never a link

Brian is a self-described novice juggling many projects at once. Whenever a session
reports a finished or updated build of FaderLab to him, **lead the reply with the
ready-to-paste one-liner below** — never just a GitHub Releases page link or "go
download it" instruction. He wants to go straight from the message to a running app
with zero browser interaction (no clicking a link, no manual unzip).

The exact command (copy verbatim — don't retype it, to avoid drift):

```bash
curl -fsSL https://raw.githubusercontent.com/brianbruzzi/iPhone-App/claude/faders-launchpad-midi-automation-u4z9u7/install.sh | bash
```

This already does everything: downloads the newest build, quits any running copy,
unzips it, installs to `~/Applications/FaderLab.app`, strips the quarantine attribute,
drops a double-clickable `Update FaderLab.command` next to it, and launches the app.
Running the exact same line again later updates it in place — this is also the update
command, not just the install command.

This infrastructure (`install.sh`, the CI-published stable `latest-build` release tag,
and `README.md`'s install section) already exists and works — there's no need to build
any of it. The only failure mode to avoid is forgetting to lead with the command itself
in chat.

**Known caveat, no action needed unless it comes up:** the URL above is hardcoded to
the feature branch `claude/faders-launchpad-midi-automation-u4z9u7`, because `master`
is currently just an empty initial commit with no app code. If this branch ever merges
into `master` (or gets renamed), `install.sh`'s self-updater, `README.md`, and this
note all reference that branch name and need updating together.

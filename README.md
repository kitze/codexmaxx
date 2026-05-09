# CodexMaxx

Minimal macOS menu bar app for tracking and switching Codex accounts.

<img src="docs/codexmaxx-menu.jpg" alt="CodexMaxx menu bar account usage popup" width="520">

CodexMaxx reads local Codex OAuth credentials from your machine, fetches Codex usage windows, and lets you switch between stored Codex profiles from the menu bar.

## Features

- Combined or active-account menu bar usage.
- Session and weekly Codex quota display.
- Account switching without a CLI.
- Profile deletion from the account context menu.
- Optional email hiding for privacy.
- Text, stacked-bar, and circular menu bar display modes.
- Local profile storage under `~/.codexmaxx`.

## Add Multiple Accounts

CodexMaxx saves whatever account is currently active in the Codex CLI. To add multiple accounts, use `codex login` for each account and then save it from the CodexMaxx menu.

1. Log in to the first account with the Codex CLI:

   ```bash
   codex login
   ```

2. Open CodexMaxx and choose `Add Current Account...`. Give the profile a clear name, such as `work` or `personal`.

3. Log in to the next account with the Codex CLI:

   ```bash
   codex login
   ```

4. Choose `Add Current Account...` again and save this account under a different profile name.

Repeat the same flow for every account you want to manage. You do not need to run a logout command first; use `codex login` to replace the currently active CLI credentials, then save that active account in CodexMaxx.

After the accounts are saved, switch between them from the CodexMaxx menu. Switching copies the selected saved profile into `~/.codex`, so the Codex CLI and CodexMaxx use the same active account.

## Build

```bash
swift build -c release --product CodexMaxx
```

## Install Locally

```bash
./Scripts/package_app.sh
open CodexMaxx.app
```

## Privacy

CodexMaxx stores copied Codex profile files in `~/.codexmaxx/profiles/codex` and backs up switched files under `~/.codexmaxx/backups`. Deleting a profile removes its saved CodexMaxx copy and metadata, but does not delete your live `~/.codex` files.

Do not commit `~/.codex`, `~/.codexmaxx`, `auth.json`, or local release credentials.

## Credits

CodexMaxx was inspired by [CodexBar](https://github.com/steipete/codexbar) by [@steipete](https://github.com/steipete) and account-switching ideas from [aisw](https://github.com/burakdede/aisw) by [Burak Dede](https://burakdede.com/).

## License

MIT

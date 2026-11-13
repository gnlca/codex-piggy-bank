<img src="docs/codex-piggy-bank-icon.png" width="128" alt="Tokens Piggy Bank app icon">

# Tokens Piggy Bank

A native macOS menu bar app for tracking Codex and Claude subscriptions, usage limits, and banked reset expiration times.

Previously Codex Piggy Bank. Existing preferences, notifications, and Calendar event references are preserved.

## Features

- Track multiple Codex and Claude accounts, each with its own configuration and cached usage.
- Add, edit, color, enable, pause, and remove accounts in **Settings → Providers**, independently of T3 Code.
- Keep a global average of weekly balances in the menu bar and below the tabs in **All**, with equal weight for each account.
- Open **All** for compact account cards with 5h / 7d rings on the right and a combined reset list. Turn off **Settings → Appearance → Compact cards** for a two-column grid with larger rings, five-hour first and weekly second.
- Reset countdowns use compact relative times such as `5d 3h`; hover for the exact date. A dashed mark on each usage ring shows the balance expected with evenly spread usage until reset, using [T3 Code's even-pace calculation](https://github.com/pingdotgg/t3code/blob/d033768ec73d728a1d10a75c53cf2ab195d1c867/packages/shared/src/usageLimits.ts#L533-L548). It appears only when the window duration and reset time are known.
- Select an account's animated line tab to filter its limits and resets. Individual accounts use the same linear usage bars as the global summary, including model-specific limits such as Fable. A single active account goes straight to this view without tabs or a duplicate summary.
- Optionally import configured provider instances from T3 Code, including names, badge colors, account folders, and enabled states.
- See subscription usage windows, including Claude's model-specific weekly limits when returned by its CLI.
- Track banked resets in expiration order and in your Mac's current time zone.
- Get optional notifications 1 hour, 10 minutes, and 5 minutes before expiration.
- Add or remove Calendar events with the same three alerts.
- Refresh enabled accounts independently every 15 minutes, or refresh manually.

## Connect accounts

1. Install and authenticate the CLI for each provider you use: Codex CLI or Claude Code.
2. Open Tokens Piggy Bank and use the sliders button at the bottom right to open **Settings → Providers**. T3 Code is not required. Existing app accounts are preserved; **Import → Import from T3 Code…** is an optional manual import from `~/.t3/userdata/settings.json`.
3. Choose **Add provider → Codex / Claude**. Give the account a name, such as “Claude Personal”, and choose its badge color with the native color picker. You can also change the color directly in the provider list.
4. Keep the proposed separate account folder for a new login, or choose an existing account folder. Leave the field empty to use the CLI's default configuration. Two profiles for the same provider cannot use the same folder.
5. Save and refresh. Existing CLI logins are reused. For a new account, choose **Sign in…**; for an existing account, **… → Sign in again…** reconnects or changes the login in Terminal.

The CLI executable is detected automatically. Set **CLI executable** in the editor if it is installed elsewhere. Codex accounts use `CODEX_HOME`; Claude accounts use `CLAUDE_CONFIG_DIR`, preserving `HOME` and macOS Keychain access. The login command uses the same account configuration as the usage reader.

Double-click an account's name in **Providers** to rename it inline. Return or leaving the field saves the name; Escape cancels. Renaming preserves the active connection, cached usage, and reminder identifiers.

Each account has separate cached usage and reset reminder identifiers. Pausing or removing an account cancels its pending notifications; it keeps the CLI login and previously created Calendar events. Editing an account folder starts a separate usage cache.

Claude requires a version of Claude Code that supports the experimental `get_usage` control request; tested with 2.1.308. API-key-only logins and unavailable subscription limits are shown as unavailable, never as unused quota. Claude reset grants are read from `get_usage` when its `cedar_ember` block reports eligible, usable credits and a confirmed next grant. Unreported credits are not inferred. Each grant is labeled by what it refills, following [T3 Code's grouping](https://github.com/pingdotgg/t3code/blob/9e1f81c78894270c7e281c78402a69a1a97c4474/apps/server/src/provider/claudeResetCredits.ts#L102-L125): **Fable reset** when it gives back weekly usage, otherwise its declared type or the limits it clears (**5-hour**, **Weekly**, or **Full reset**). Hover a reset's name for what it refills.

## Global weekly average

The global percentage is the rounded arithmetic mean of the available weekly remaining percentages: `sum(weekly remaining) / account count`. This follows [T3 Code's usage-pool calculation](https://github.com/pingdotgg/t3code/blob/d033768ec73d728a1d10a75c53cf2ab195d1c867/packages/shared/src/usageLimits.ts#L454-L509). T3 groups its pools by provider; Piggy Bank applies that same equal-account mean to the main weekly limits across Codex and Claude.

Confirmed duplicate subscriptions count once, using the latest report. Paused accounts, failed refreshes, missing weekly data, and model-specific limits do not contribute. Unknown plans are included when their weekly usage is available. A partial-coverage label appears when some active accounts have no usable weekly data.

Plan names and 5× / 20× tiers are descriptive labels only. They never affect the average, and no plan-weight configuration is needed. Claude tier metadata is checked against the CLI's signed-in email before displaying it.

## Data access

Codex usage is read through `account/read` and `account/rateLimits/read`. Claude uses a short-lived CLI control connection with `initialize` and `get_usage`, skipping transcript analysis. Usage checks send no prompts, disable Claude hooks and tools, and do not consume reset credits. The app does not store credentials or update either CLI. Login starts only when you choose **Sign in…** or **Sign in again…** and is handled by the provider's CLI in Terminal.

## Build and test

Requires macOS 14 or later and Xcode with the macOS 26 SDK or later for the existing gated Liquid Glass controls.

```sh
./script/build_and_run.sh
swift test
```

The app is built as **Tokens Piggy Bank.app**. The Xcode project/scheme (`CodexPiggyBank`) and bundle identifier remain stable for upgrades. `script/package_release.sh` produces a universal signed DMG when your signing identity and notary profile are configured. Published versions are available in [GitHub Releases](https://github.com/gnlca/codex-piggy-bank/releases).

## Reference

Provider instances and account isolation follow the approach documented in [T3 Code's Codex setup](https://github.com/pingdotgg/t3code/blob/main/docs/user/providers-codex.md) and [Claude setup](https://github.com/pingdotgg/t3code/blob/main/docs/user/providers-claude.md). The Claude reader uses the same control requests as [T3 Code's capabilities probe](https://github.com/pingdotgg/t3code/blob/d033768ec73d728a1d10a75c53cf2ab195d1c867/apps/server/src/provider/ClaudeProvider.ts), implemented natively in Swift.

The Claude SVG and adapted provider conventions retain the [T3 Code MIT notice](CodexPiggyBank/Resources/ThirdPartyNotices.txt), also bundled with the app.

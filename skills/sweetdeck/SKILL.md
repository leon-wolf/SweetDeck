---
name: sweetdeck
description: Use SweetDeck as the primary CLI for Apple build/run/test/simulator/device workflows in this repository.
---

# Skill: sweetdeck

Use `sweetdeck` first for Xcode-oriented development tasks in this project.

## When to use

- Build, run, clean, and test app targets.
- Inspect project context (project, scheme, destination, derived data).
- Set up simulators and app lifecycle tasks (install, launch, logs, stop).
- Manage physical devices via `sweetdeck device`.
- Edit project schemes/configs/packages via `sweetdeck project`.

## Fast start

1) Initialize config in the project root:

```sh
sweetdeck init --scheme <YourScheme>
```

2) Make simulator setup deterministic:

```sh
sweetdeck simulator setup
```

3) Verify and use:

```sh
sweetdeck context
sweetdeck build
sweetdeck run
sweetdeck test
```

## Non-interactive behavior

- SweetDeck is non-interactive.
- Do not rely on interactive prompts.
- Prefer explicit `--scheme`, `--destination`, `--device`, and `--bundle-id` when needed.
- Avoid `--pick-scheme` (deprecated).

## Recommended command patterns

```sh
# Context + refresh discovered data
sweetdeck context --refresh

# Build with extra xcodebuild args
sweetdeck build --xcarg -quiet

# Build and run on simulator from config destination
sweetdeck run

# Run on a specific simulator or physical device
sweetdeck run --device "iPhone 16"
sweetdeck run --device "<device-udid>"

# Stream logs for configured bundle
sweetdeck logs

# Stop app (simulator or device)
sweetdeck stop
sweetdeck stop --device "<device-udid>" --pid <pid>
```

## Simulator operations

```sh
# list
sweetdeck simulator list

# one-command setup (pick, boot, open, write destination)
sweetdeck simulator setup

# explicit lifecycle
sweetdeck simulator boot <udid-or-name>
sweetdeck simulator shutdown <udid-or-name>
sweetdeck simulator delete <udid-or-name>
sweetdeck simulator prune
```

## JSON-first automation

Use `--output json` on top-level commands for machine-readable responses:

```sh
sweetdeck --output json context --refresh
sweetdeck --output json build
sweetdeck --output json test
```

## Troubleshooting

- `No config found`: run `sweetdeck init` in project root.
- `Missing bundle identifier`: pass `--bundle-id` or set `appLaunch.bundleIdentifier` in config.
- `Simulator not found`: run `sweetdeck simulator list` and use `sweetdeck simulator setup --simulator ...`.
- If destination drifts, run `sweetdeck simulator setup` again to re-pin destination.

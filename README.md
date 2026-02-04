# SweetDeck

`sweetdeck` is a FlowDeck-like CLI for driving Xcode builds, simulators, and related workflows.

## Features

- Xcode build/test/clean/run workflows
- Simulator management and app install/launch
- Device management via `devicectl`
- Project editing (schemes/configs/packages)
- Config-driven automation with `.sweetdeck/config.json`

## Install

### Homebrew (recommended)

```sh
brew install sweetdeck
```

### From source

```sh
git clone https://github.com/leon-wolf/SweetDeck.git
cd SweetDeck
swift build -c release
install -m 755 .build/release/sweetdeck ~/.local/bin/sweetdeck
```

## Build

```sh
swift build -c release
```

## Run (from this repo)

```sh
swift run sweetdeck --help
```

## Initialize a project

From an Xcode workspace/project directory:

```sh
sweetdeck init
```

This creates `.sweetdeck/config.json` and `.sweetdeck/DerivedData` (default).

### Init options

```sh
# pick default scheme + simulator interactively
sweetdeck init

# set schemes and default scheme explicitly
sweetdeck init --schemes App --schemes App-Staging --scheme App
```

## Usage

```sh
sweetdeck context
sweetdeck build
sweetdeck test
sweetdeck run
sweetdeck logs
```

### Common flags

- `--scheme <name>`: override scheme for this invocation
- `--pick-scheme`: prompt to pick a scheme
- `--output json`: machine-readable output
- `--verbose`: show tool output (xcodebuild, simctl, devicectl)

## Contributing

1. Fork the repo and create your branch from `main`.
2. Make your changes with clear commits.
3. Run tests: `swift test` (and `swift build -c release` if relevant).
4. Open a PR with a clear summary and screenshots/logs if applicable.

### Development tips

- Prefer small, focused PRs.
- Keep CLI UX consistent across commands.
- Avoid adding heavy dependencies unless needed.

## License

MIT (see `LICENSE`).

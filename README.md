# SweetDeck

`sweetdeck` is a FlowDeck-like CLI for driving Xcode builds, simulators, and related workflows.

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


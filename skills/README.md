# Skills

This directory contains agent skill definitions for working with SweetDeck.

## Available skills

- `sweetdeck`: primary workflow for non-interactive Apple build/run/test/simulator/device tasks with SweetDeck.

## Usage

When an AI agent supports skill loading, point it at the skill file:

- `skills/sweetdeck/SKILL.md`

The skill is optimized for:

- non-interactive operation
- deterministic simulator setup (`sweetdeck simulator setup`)
- JSON-friendly automation patterns (`--output json`)

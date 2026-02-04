---
title: "Homebrew Tap Setup & Maintenance"
---

# Homebrew Tap Setup & Maintenance

This guide explains how to create and maintain a Homebrew tap for SweetDeck and keep the formula in sync with tagged releases.

## 1) Create the tap repository

Homebrew taps use a separate GitHub repo named `homebrew-<tap>`.

Example (recommended):

```
leon-wolf/homebrew-sweetdeck
```

Initialize:

```sh
mkdir homebrew-sweetdeck
cd homebrew-sweetdeck
git init
```

Add the formula:

```sh
mkdir Formula
cp /path/to/SweetDeck/Formula/sweetdeck.rb Formula/sweetdeck.rb
git add Formula/sweetdeck.rb
git commit -m "Add sweetdeck formula"
git remote add origin https://github.com/leon-wolf/homebrew-sweetdeck.git
git push -u origin main
```

## 2) Install from your tap

```sh
brew tap leon-wolf/sweetdeck
brew install sweetdeck
```

## 3) Release workflow integration (recommended)

The GitHub Action in the main repo is already set up to:

- build the release binary from tag
- zip it as `sweetdeck-<tag>-macos.zip`
- compute SHA256
- update `Formula/sweetdeck.rb`
- commit and push the formula change

By default, that update happens **in the same repo**. For a separate tap repo, choose one of the options below.

### Option A — Keep formula in this repo (simplest)

If you don’t want a separate tap repo, keep using `Formula/sweetdeck.rb` in this repo and create a Homebrew tap from it:

```sh
brew tap leon-wolf/sweetdeck https://github.com/leon-wolf/SweetDeck
```

Homebrew will look for `Formula/sweetdeck.rb` in the main repo.

### Option B — Push formula to a dedicated tap repo

Update the workflow to push `Formula/sweetdeck.rb` to a separate tap repository:

```sh
git clone https://github.com/leon-wolf/homebrew-sweetdeck.git
cp Formula/sweetdeck.rb homebrew-sweetdeck/Formula/sweetdeck.rb
cd homebrew-sweetdeck
git add Formula/sweetdeck.rb
git commit -m "Update sweetdeck formula for <tag>"
git push
```

Automate this by adding a workflow step that clones the tap repo and pushes updates after tagging.

#### GitHub Actions snippet (push to tap repo)

Add the following step **after** the formula is updated and committed in the main repo:

```yaml
      - name: Push formula to tap repo
        env:
          TAP_REPO: leon-wolf/homebrew-sweetdeck
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          git clone https://github.com/${TAP_REPO}.git /tmp/tap
          mkdir -p /tmp/tap/Formula
          cp Formula/sweetdeck.rb /tmp/tap/Formula/sweetdeck.rb
          cd /tmp/tap
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add Formula/sweetdeck.rb
          git commit -m "Update sweetdeck formula for ${{ github.ref_name }}" || true
          git push
```

If you prefer a PAT for a separate tap repo, set `GH_TOKEN` to a secret that has access to `leon-wolf/homebrew-sweetdeck`.

## 4) Maintain the tap over time

For each release:

1. Tag and push: `git tag vX.Y.Z && git push origin vX.Y.Z`
2. The workflow builds the zip, computes SHA, and updates the formula
3. Users can upgrade with: `brew upgrade sweetdeck`

## 5) Troubleshooting

**Formula not updating**
- Confirm the action ran on a tag (only triggers for `v*`)
- Check `Formula/sweetdeck.rb` was updated and pushed

**SHA mismatch**
- Ensure the SHA in the formula matches the published zip
- Re-run the release action or re-upload the zip

**Install fails**
- Check that the zip contains the `sweetdeck` binary at the top level

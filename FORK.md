# Fork: remusa/opencode-bar

This is a community fork of [opgginc/opencode-bar](https://github.com/opgginc/opencode-bar) with added **DeepSeek** provider support.

## Divergence from Upstream

### Added Features
- **DeepSeek Provider**: Credit balance tracking for the DeepSeek API platform
  - Reads `deepseek` entry from OpenCode's `auth.json`
  - Fetches balance from `GET https://api.deepseek.com/user/balance`
  - Displays remaining credit balance in the pay-as-you-go section
  - Shows balance breakdown (granted vs topped-up) in the submenu

## Sync Strategy

### Periodic Manual Merges
1. Track upstream `main` branch via `upstream` remote
2. Periodically merge upstream changes into local `dev` branch
3. Review conflicts and resolve before merging to `master`
4. Never auto-sync — always review before merging

### Commands
```bash
# Fetch upstream changes
git fetch upstream

# Merge upstream into dev
git checkout dev
git merge upstream/main

# Resolve conflicts if any
# Then merge to master
git checkout master
git merge dev
```

## Installation

### Homebrew (Fork)
```bash
brew install --cask remusa/tap/opencode-bar
```

### Build from Source
```bash
git clone https://github.com/remusa/opencode-bar.git
cd opencode-bar
xcodebuild -project CopilotMonitor/CopilotMonitor.xcodeproj \
  -scheme CopilotMonitor -configuration Debug build
```

## Contributing

Contributions welcome! Please submit a Pull Request to the `dev` branch.

## License

MIT License - Same as upstream.

---
name: skill-crawler
description: >
  Tracks external OpenClaw skills and inspiration repos for upstream updates.
  Two tiers: installed skills (flags new commits to pull) and watch repos (flags new ideas).
  Runs weekly via cron. Notifies via Telegram when updates are found.
  Use when: you want to stay current with upstream skill updates without manually checking GitHub.
  Setup: copy skill-crawler.config.json, fill in your repos and chat ID, add to cron.
allowed-tools: "Bash(node:*)"
compatibility: "Requires bash, curl, python3, git. No npm deps."
metadata:
  author: wiziswiz
  version: 1.0.0
  category: maintenance
  tags: [skills, updates, github, maintenance, cron]
---

## Overview
Skill Crawler monitors your installed OpenClaw skills and any inspiration repos you're watching for upstream commits. When new commits land, you get a Telegram digest so nothing slips by.

## Setup (3 steps)

### 1. Copy config
```bash
cp ~/.openclaw/skills/skill-crawler/skill-crawler.config.json.example \
   ~/.openclaw/skills/skill-crawler/skill-crawler.config.json
```

### 2. Edit config
Fill in your `telegram_chat_id`, and list your installed skills + watch repos.

Your Telegram chat ID: send any message to your bot and check `https://api.telegram.org/bot<TOKEN>/getUpdates`.

### 3. Add cron (Monday 10 AM)
In OpenClaw, add a cron job:
- Schedule: `0 10 * * 1` (America/Los_Angeles or your tz)
- Payload: `Run ~/.openclaw/skills/skill-crawler/scripts/skill-crawler.sh using exec tool. Reply NO_REPLY regardless of output.`
- sessionTarget: isolated

## Config Reference
- `telegram_chat_id` — your Telegram user ID (not the bot token)
- `installed_skills` — skills you maintain locally; gets git-fetched if .git exists, otherwise checked via GitHub API
- `watch_repos` — repos you pulled ideas from; checked via GitHub API for new commits
- `context` field — reminder of what you took from the repo (shown in digest)

## How It Works
1. Reads config from `skill-crawler.config.json`
2. Reads Telegram bot token from `~/.openclaw/openclaw.json` automatically
3. For installed skills: `git fetch` if `.git` exists, else GitHub API
4. For watch repos: GitHub API commit check
5. Compares against last-known SHA in `/tmp/skill-crawler/`
6. Sends a single Telegram digest if anything is new; stays silent otherwise
7. First run seeds state files — notifications start from the second run

## Manual Run
```bash
~/.openclaw/skills/skill-crawler/scripts/skill-crawler.sh
```

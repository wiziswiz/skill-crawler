# 🕷️ Skill Crawler

**Stay current with upstream updates for your OpenClaw skills — without manually checking GitHub.**

Skill Crawler is an [OpenClaw](https://github.com/openclaw) skill that monitors external repos and notifies you via Telegram when new commits land.

## What It Does

**Two-tier monitoring:**

- **Installed Skills** — Skills you've cloned locally. Skill Crawler runs `git fetch` (or falls back to GitHub API) and tells you exactly how far behind you are, with a ready-to-run `git pull` command.
- **Watch Repos** — Repos you're keeping an eye on for ideas. Checked via GitHub API. Includes your custom context note so you remember *why* you're watching.

**Zero noise** — If nothing changed, it stays completely silent.

## Sample Telegram Output

```
🕷️ Skill Crawler — Updates Found

📦 Installed Skills
• repo-analyzer (3 commits behind)
  ab12cd3 feat: add batch mode — AuthorName
  → cd ~/.openclaw/skills/repo-analyzer && git pull

👀 Watch List
• cool-framework (user/cool-framework)
  ef45gh6 refactor: new plugin system — AuthorName
  Context: Borrowed the retry logic pattern

Run: 2026-03-10 10:00 PDT
```

## Install

```bash
# Clone to your skills directory
git clone https://github.com/wiziswiz/skill-crawler.git ~/.openclaw/skills/skill-crawler

# Copy and edit config
cd ~/.openclaw/skills/skill-crawler
cp skill-crawler.config.json.example skill-crawler.config.json
# Edit skill-crawler.config.json with your repos and Telegram chat ID
```

## Config

Edit `skill-crawler.config.json`:

```json
{
  "telegram_chat_id": "YOUR_CHAT_ID",
  "installed_skills": [
    {
      "name": "my-skill",
      "local_path": "~/.openclaw/skills/my-skill",
      "github_repo": "owner/my-skill"
    }
  ],
  "watch_repos": [
    {
      "name": "interesting-project",
      "github_repo": "someone/interesting-project",
      "context": "Great error handling patterns"
    }
  ]
}
```

**Finding your Telegram chat ID:** Send any message to your bot, then visit:
```
https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates
```

The bot token is read automatically from `~/.openclaw/openclaw.json`.

## Cron Setup (OpenClaw)

Add a weekly cron job in your OpenClaw config:

- **Schedule:** `0 10 * * 1` (Monday 10 AM)
- **Payload:** `Run ~/.openclaw/skills/skill-crawler/scripts/skill-crawler.sh using exec tool. Reply NO_REPLY regardless of output.`
- **sessionTarget:** `isolated`

## Requirements

- `bash`, `curl`, `python3`, `git`
- No npm/pip dependencies
- OpenClaw with Telegram channel configured

## How It Works

1. Reads your config for repos to check
2. Pulls Telegram bot token from OpenClaw config automatically
3. Installed skills: `git fetch` if `.git` exists, otherwise GitHub API
4. Watch repos: GitHub API latest commit check
5. Deduplicates via state files in `/tmp/skill-crawler/`
6. Sends one clean Telegram digest (or stays silent if nothing new)
7. First run seeds state — notifications start from run #2

## License

MIT

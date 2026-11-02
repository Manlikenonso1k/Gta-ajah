# Video editor skills

This repo uses the skill pack from
[mrpaidsocial-video-editor-agent](https://github.com/mrpaidsocial/mrpaidsocial-video-editor-agent)
for editing short-form videos (for example gameplay clips and trailers).

The skills in `.claude/skills/` are relative symlinks into a clone of that pack
at `../mrpaidsocial/mrpaidsocial-video-editor-agent`. They are not copies: change
the skills in the pack repo, not here.

## Setup

```bash
bash tools/setup-video-editor.sh          # clone the pack if missing, link the skills
bash tools/setup-video-editor.sh --demo   # also install QA dependencies and run the offline demo
```

Set `VIDEO_EDITOR_PACK_DIR` to use a clone somewhere else. Start a new Claude Code
session after linking so the skills load.

Requirements: Python 3.10+, ffmpeg/ffprobe, Node.js 20+ and npm.
API keys (ElevenLabs, Gemini, OpenAI) are optional and go in the pack's `.env`.
Brand details, defaults and the projects directory go in the pack's
`MASTER_CONTEXT.md`. Both files are gitignored.

## Use

Put footage somewhere outside the tracked repo files and ask for an edit, for
example "edit this video". The `video-edit-pipeline` skill routes the request.
Keep media out of commits.

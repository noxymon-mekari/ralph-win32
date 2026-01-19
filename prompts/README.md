# Sample prompts

This folder contains example prompt files to use with `--prompt`.

## Usage

Looped runner:

Runs multiple iterations (good for actually making progress on a PRD).

**Linux/macOS:**
```bash
./ralph.sh --prompt prompts/default.txt --allow-profile dev 10
```

**Windows:**
```cmd
ralph.cmd --prompt prompts\default.txt --allow-profile dev 10
```

Single run:

Runs exactly one iteration (good for testing your tool permissions and prompt wording).

**Linux/macOS:**
```bash
./ralph-once.sh --prompt prompts/default.txt --allow-profile dev
```

**Windows:**
```cmd
ralph-once.cmd --prompt prompts\default.txt --allow-profile dev
```

## Examples (per prompt)

Default prompt + PRD:
Runs the standard workflow: attach your PRD and let Ralph iterate safely (write + limited shell).

Credit: [Ship working code while you sleep (video)](https://www.youtube.com/watch?v=_IK18goX4X8)

**Linux/macOS:**
```bash
./ralph.sh --prompt prompts/default.txt --prd plans/prd.json --allow-profile safe 10
```

**Windows:**
```cmd
ralph.cmd --prompt prompts\default.txt --prd plans\prd.json --allow-profile safe 10
```

Write-only prompt:
Use this when you want Copilot to only edit files (no shell access).

**Linux/macOS:**
```bash
./ralph.sh --prompt prompts/safe-write-only.txt --allow-profile locked 10
```

**Windows:**
```cmd
ralph.cmd --prompt prompts\safe-write-only.txt --allow-profile locked 10
```

WordPress plugin agent:
Targets WordPress development workflows; attaches a PRD but keeps tool access constrained by the harness/profile.

**Linux/macOS:**
```bash
./ralph.sh --prompt prompts/wordpress-plugin-agent.txt --prd plans/prd.json --allow-profile safe 10
```

**Windows:**
```cmd
ralph.cmd --prompt prompts\wordpress-plugin-agent.txt --prd plans\prd.json --allow-profile safe 10
```

Pest coverage:
Iterates on adding ONE meaningful test per iteration; typically you don't need a PRD for this style of task.

Credits: https://gist.github.com/mpociot/914c1871e6faeb350d2fda09ecb2a18f 

**Linux/macOS:**
```bash
./ralph.sh --prompt prompts/pest-coverage.txt --allow-profile safe 10
```

**Windows:**
```cmd
ralph.cmd --prompt prompts\pest-coverage.txt --allow-profile safe 10
```

## Tool permissions

Tool permissions are controlled by the scripts via flags (not by prompt file content).

Examples:

Single-run, write-only:
Useful when you want to validate the prompt behavior without letting the agent run any shell commands.

**Linux/macOS:**
```bash
./ralph-once.sh --prompt prompts/safe-write-only.txt \
  --allow-profile locked
```

**Windows:**
```cmd
ralph-once.cmd --prompt prompts\safe-write-only.txt --allow-profile locked
```

Looped run with explicit deny:
Allows everything in the `dev` profile, but still blocks a dangerous command.

**Linux/macOS:**
```bash
./ralph.sh --prompt prompts/default.txt --allow-profile dev \
  --deny-tools 'shell(git push)' \
  10
```

**Windows:**
```cmd
ralph.cmd --prompt prompts\default.txt --allow-profile dev --deny-tools "shell(git push)" 10
```

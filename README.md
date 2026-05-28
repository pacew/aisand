-*- mode: visual-line -*-

# aisand: Claude Code Sandbox

A Docker sandbox for running Claude Code CLI safely within your development projects. Designed to mitigate the risk of prompt injection attacks while preserving a natural development workflow.

## Threat Model

**Attack scenario:**
An attacker learns what kind of project you're working on, finds a community forum or documentation site you'll likely visit, and injects a malicious prompt that causes Claude Code to generate harmful code or execute dangerous commands.

**What we protect against:**
- Code generation turned malicious by prompt injection
- Exfiltration of files from outside the sandbox
- Permanent damage to your host system

**What we accept:**
- Arbitrary command execution inside the container (you control what Claude suggests)
- Container being fully compromised (code execution, data deletion within the project)
- Resource exhaustion from fork bombs or runaway processes
- Everything written to the container filesystem by Claude Code is considered potentially tainted

**Defense strategy:**
1. **Containment:** Docker isolates the container filesystem from the host. Only your project directory (git repo) is visible to Claude Code.
2. **Audit:** You review all code changes with `meld` (or similar) outside the container before running anything with broader access.
3. **Network isolation:** Outbound network is allowed (package downloads, external APIs) but the container cannot reach your host services or inbound connections.
4. **Credentials:** Only the Anthropic API key is exposed to Claude Code. All other credentials stay outside.

## Architecture

```
┌──────────────────────────────────────────────────┐
│ Your Host Machine                                │
├──────────────────────────────────────────────────┤
│  /home/user/projects/my-project/ (git repo)     │
│         ↓ (mounted as /home/user/projects/...) │
│  ┌────────────────────────────────────────────┐ │
│  │ Docker Container (ephemeral per run)       │ │
│  │  /home/user/projects/my-project/ (rw)     │ │
│  │  ~/.claude/ (persistent volume)            │ │
│  │  /tmp (rw) ← build artifacts               │ │
│  │  Claude Code CLI                           │ │
│  │  Python, C tools                           │ │
│  │  Network: outbound only                    │ │
│  └────────────────────────────────────────────┘ │
│  Docker Volume: aisand-my-project-memory        │
│         (Claude's memory, persists)             │
│                                                  │
│  Review changes outside container               │
│  (meld, git diff, etc.)                         │
│  Push code from host (git push)                 │
└──────────────────────────────────────────────────┘
```

- **Container:** Fresh ephemeral container on each `aisand` run. Destroyed on exit.
- **Project volume:** Your git repo mounted at its actual path (e.g., `/home/user/projects/my-project/`).
- **Memory volume:** Claude's memory persists across runs in a named Docker volume (`aisand-{repo-name}-memory`).
- **Credentials:** Only `ANTHROPIC_API_KEY` is visible inside.
- **Network:** Outbound unrestricted; no inbound; no access to `localhost:*` on host.

## Installation

1. Clone or download the `aisand` repository:
   ```bash
   git clone https://github.com/pacew/aisand.git ~/aisand
   ```

2. Add it to your PATH or create a symlink:
   ```bash
   ln -s ~/aisand/aisand ~/bin/aisand
   # or add ~/aisand to your PATH in ~/.bashrc or ~/.zshrc
   ```

3. Ensure your `ANTHROPIC_API_KEY` is set in your shell environment:
   ```bash
   export ANTHROPIC_API_KEY="sk-ant-..."
   ```

## Usage

Navigate to the root of any git repository and run:

```bash
cd ~/projects/my-project
aisand
```

The script will:
1. Verify you're in a git repository root
2. Check that `ANTHROPIC_API_KEY` is set
3. Build a Docker image (cached, so subsequent runs are fast)
4. Create or reuse a Docker volume for Claude's memory
5. Launch an interactive shell inside the container with your project at its original path

Inside the container, interact with Claude Code normally:

```bash
# Inside the container
cd ~/projects/my-project
claude --help
# ... collaborate with Claude Code on your project
```

When you exit the container (Ctrl+D or `exit`), it's destroyed. Your project files and Claude's memory persist on the host.

### Multi-window workflow

A common pattern: run Claude in one terminal, and use other terminals in the same container for running tests or commands:

```bash
# Terminal 1: launch aisand with Claude
cd ~/projects/my-project
aisand
# Inside: interact with Claude Code

# Terminal 2 (on host): launch a second container session
cd ~/projects/my-project
aisand
# Inside: run pytest, build commands, etc.
```

Both containers share the same memory volume and git repo, so you can iterate with Claude in one while testing in another.

## Workflow

1. **Inside the container:** Collaborate with Claude Code on editing, exploration, and design.
2. **Outside the container:** Review code changes with `meld` or `git diff`.
3. **Outside the container:** Run git push and deploy from your host.

Example:

```bash
# In project directory on host
aisand
# Inside container: interact with Claude Code
exit

# Back on host: review changes
meld .
git diff
git push
```

## Security Constraints

The Docker container runs with:

- **Dropped capabilities:** `--cap-drop=all` — removes elevated privileges needed to modify host or escalate inside container
- **No privilege escalation:** `--security-opt=no-new-privileges` — prevents setuid binaries from gaining extra privs
- **Resource limits:** Memory capped at 4GB, CPU at 4 cores — protects against fork bombs
- **Network:** Outbound allowed, inbound blocked, localhost unreachable
- **Filesystem:** Your project directory and `/tmp` are writable; everything else is the container root

## Assumptions & Limitations

1. **You will code review.** The Docker boundary contains damage; code review prevents it. Don't skip this step.
2. **No credentials in the project tree.** Never store AWS keys, GitHub tokens, database passwords in your git repo (not even in `.env`). The container can read them.
3. **One thread per project.** Separate container for separate projects. Clean isolation, but more startup overhead.
4. **No IDE inside container.** Uses Claude Code CLI (terminal-based) with your editor of choice on the host. Emacs, Vim, etc. work great; you edit locally and Claude Code modifies files in your project directory.

## Rebuilds and Cleanup

Docker images and memory volumes are cached by project name for speed.

**Force a rebuild of the Docker image:**

```bash
aisand rebuild
```

**Clean up all aisand images and volumes:**

```bash
aisand prune
```

This removes all `aisand-*` images and volumes. Use with care — you'll lose Claude's memory for all projects.

**Delete memory for a specific project:**

```bash
docker volume rm aisand-my-project-memory
```

Next run will create a fresh memory volume.

## Troubleshooting

**"Not in a git repository root"**
- Make sure you're running `aisand` from the root directory of a git repo (where `.git/` exists)

**"ANTHROPIC_API_KEY not set"**
- Set your API key in your shell: `export ANTHROPIC_API_KEY="sk-ant-..."`
- Or add it to your `~/.bashrc` or `~/.zshrc`

**"Docker permission denied"**
- Add your user to the docker group: `sudo usermod -aG docker $USER`
- Log out and back in, or run `newgrp docker`

**Container exits immediately**
- Check the error message. Run with `set -x` in the script for debug output.

**Slow on first run**
- Docker is building the image. Subsequent runs use the cached image (fast).

## Implementation Notes

- **Dockerfile:** Debian base, Python 3, GCC/embedded C toolchain, Node.js, Claude Code CLI
- **Launch script:** Bash; finds `.git`, validates environment, builds image, manages memory volume, runs container
- **Image tag:** Based on project name (`aisand-{repo-name}`)
- **Project mount:** Git repo mounted at its actual path (e.g., `/home/user/projects/my-project/`)
- **Memory volume:** Named volume `aisand-{repo-name}-memory` mounted at `/home/claude/.claude`
- **Subcommands:** `aisand rebuild` and `aisand prune` for image/volume management

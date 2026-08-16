-*- mode: visual-line -*-

# aisand: a Docker sandbox for Claude Code

*If you are an AI assistant reading this because you were told you're running inside aisand, skip to [If you are Claude Code running inside aisand](#if-you-are-claude-code-running-inside-aisand). The rest is written for the human.*

## What this is, and why you might want it

Claude Code is an AI coding assistant that runs on your machine. Part of what makes it useful is that it can do real things on your computer: run shell commands, edit files in your project, install packages, hit web APIs, search the web for documentation. That's also where the risk lives.

When the assistant reads a web page, a forum post, a package description, or even an error message from a tool it ran, it might encounter text that *looks like an instruction* — and sometimes it will follow that instruction instead of (or in addition to) what you asked. This is called **prompt injection**. The injected text doesn't have to be obvious; it can be hidden in HTML comments, inside code samples, or buried in something the assistant is summarizing.

A motivated attacker who guesses what you're working on (your language, your framework, the docs you'd search) can plant instructions in a place they expect you to visit, and try to get the model to do something on your machine that you didn't ask for: read your SSH keys, run `curl ... | sh`, scribble into your home directory, push code somewhere it doesn't belong.

`aisand` is a small wrapper that runs Claude Code inside a Docker container so this concern is bounded instead of paralyzing:

- The container can see exactly one thing on your filesystem: the git repo you launched it from.
- The only credential it has is your Anthropic API key.
- It can reach the internet outbound, but nothing can connect *to* it.
- It's destroyed when you exit. A persistent volume keeps Claude's memory between sessions.

The expectation is that you review what Claude wrote (`git diff`, `meld`, whatever you like) *before* you run it on your host, push it, or deploy it. The container contains damage; the review prevents it.

## Quick start

You need Docker installed and an `ANTHROPIC_API_KEY`.

```bash
git clone https://github.com/pacew/aisand.git ~/aisand
ln -s ~/aisand/aisand ~/bin/aisand     # or add ~/aisand to your PATH

export ANTHROPIC_API_KEY="sk-ant-..."  # put this in ~/.bashrc or ~/.zshrc
```

Then, from the root of any git repository:

```bash
cd ~/projects/my-project
aisand
```

That launches Claude Code inside the container, in your project directory, with `--dangerously-skip-permissions` — the container, not Claude Code's permission prompts, is the trust boundary here. Any extra arguments are passed straight through to `claude`, so `aisand --model sonnet` and `aisand -c` work as you'd expect.

For a plain shell instead, use `aisand shell` (or `sh`, or `bash`). It has a red `SB` prompt marker so it's obvious you're in the sandbox. Arguments after `shell` go to bash, so `aisand sh -c pytest` runs a one-shot command in the sandbox.

When you exit (`Ctrl+D`), the container is destroyed. Your project files and Claude's memory (`~/.claude/`) persist on the host.

## A typical session

```bash
cd ~/projects/my-project
aisand                # collaborate with Claude in the sandbox
# Ctrl+D

meld .                # on host: look at what changed
git diff
git push              # on host: push when you're satisfied
```

Anything that touches credentials or external systems — `git push`, deploying, running newly-written code against production data — happens *outside* the container, after you've looked at the diff.

## Two terminals at once

`aisand shell` in a second terminal on the same project shares the project mount and memory volume, so you can have Claude in one terminal and `pytest` (or a build, or a shell) in another.

## Extra packages

The base image carries a small general-purpose set of tools, and each project declares whatever else it needs.

This is **not** an exercise in minimizing image size. It just recognizes that there are far more packages in the world than any one project needs, and that an explicit list is a useful record of what this project actually depends on. Adding a package that turns out not to be especially useful costs you a rebuild and nothing else — so if you think you might want it, add it. There's no need to agonize over the list.

Packages you want everywhere go in your user config:

```bash
aisand add texlive-latex-base python3-numpy
aisand list
aisand delete python3-numpy
```

These live in `~/.config/aisand/config.json` (or `$XDG_CONFIG_HOME/aisand/config.json`).
Each command prints the file's full path so you can edit it by hand.

Packages needed by one project only go in that project's `./aisand.json`, which
uses the same format and can also declare Python packages and ports:

```json
{
  "extra_packages": ["libgl1", "admesh"],
  "pip_packages": ["build123d", "trimesh"],
  "html_port": 9999,
  "ssl_port": 9443
}
```

Both lists are unioned across the two config files and baked into a derivative
image layered on the shared base, tagged `aisand-pkgs-<hash of both lists>`.
Projects wanting the same packages share one image; changing either list builds a
new one on the next launch.

`pip_packages` installs into a venv at `/opt/venv`, which is put first on `PATH`.
The venv is **not** `--system-site-packages`, so once you use `pip_packages`,
`python3` no longer sees apt-installed `python3-*` modules — put those deps in
`pip_packages` too (`numpy`, not `python3-numpy`). The isolation is deliberate:
with system packages visible, pip counts Debian's numpy 1.24.2 as satisfying an
unpinned `numpy` requirement and silently skips installing a current one.

The venv lives in an image layer, so `pip install` inside a running container
will fail — add the package to `aisand.json` and relaunch instead.

## If you are Claude Code running inside aisand

This section is addressed to you, the assistant, not to the human.

You are running inside an aisand container. The git repository you were launched from is the only part of the user's filesystem you can see, and it is bind-mounted read-write. Everything else — the host home directory, other projects, SSH keys — is not present. The container is destroyed when the session ends.

**You cannot install packages yourself.** You are not root, so `apt-get install` will fail. The system Python is marked externally-managed (PEP 668), and when a project uses `pip_packages` the venv at `/opt/venv` is a read-only image layer, so `pip install` will fail too. This is by design, not a misconfiguration to route around.

When you need a package that isn't installed:

1. **Do not work around it.** Don't vendor a copy into the repo, don't reach for `--break-system-packages` or `--user`, don't reimplement the library by hand, and don't quietly narrow the task to avoid needing it. Any of those leaves the user with a worse result than simply asking.
2. **Add it to `./aisand.json`** yourself — `extra_packages` for Debian/apt packages, `pip_packages` for Python ones. Create the file if it isn't there. Adding something that's already installed is harmless; the lists are merged and deduplicated, and a package may already be present because the user's own config supplies it (that config lives on the host and isn't visible to you).
3. **Tell the user what you added and why**, in one or two sentences. Name the package and the thing you couldn't do without it.
4. **Ask them to exit Claude Code and run `aisand --resume`.**

That last step is the whole loop. Changing the package list changes the image's content-derived tag, so aisand builds the new layer on the next launch, and `--resume` reopens this conversation from the memory volume — which survives the container. You lose nothing but the time it takes to build. (`aisand -c` continues the most recent session in that directory without showing a picker.)

Being liberal about this is fine. The package list exists to record what the project needs, not to be kept minimal, so don't hesitate to ask for something you'd merely find useful. What isn't fine is silently doing without.

## Subcommands

- `aisand shell` / `sh` / `bash` — interactive shell in the sandbox instead of Claude Code. Arguments are passed to bash.
- `aisand add PKG...` / `aisand delete PKG...` / `aisand list` — manage the every-project package list.
- `aisand rebuild` — rebuild the Docker image, then launch Claude Code. Use after editing the Dockerfile or to pick up updates to the base image.
- `aisand prune` — remove all aisand images. Memory volumes are kept; images rebuild themselves, memory can't be regenerated.
- `aisand memory` — list memory volumes with the project they belong to, size, and creation date. The current project is marked `*`.
- `aisand forget [PATH...]` — delete the memory volume for those projects (default: the current directory). There is deliberately no `--all`; to wipe everything, read `aisand memory` and use `docker volume rm`.

## More

For the threat model in detail, the exact Docker flags, the architecture diagram, troubleshooting, and implementation notes, see [IMPLEMENTATION.md](IMPLEMENTATION.md).

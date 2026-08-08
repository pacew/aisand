-*- mode: visual-line -*-

# aisand: a Docker sandbox for Claude Code

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

The base image is deliberately small. Packages you want everywhere go in your
user config:

```bash
aisand add texlive-latex-base python3-numpy
aisand list
aisand delete python3-numpy
```

These live in `~/.config/aisand/config.json` (or `$XDG_CONFIG_HOME/aisand/config.json`).
Each command prints the file's full path so you can edit it by hand.

Packages needed by one project only go in that project's `./aisand.json`, which
uses the same format and can also declare ports:

```json
{
  "extra_packages": ["ghostscript"],
  "html_port": 9999,
  "ssl_port": 9443
}
```

Both `extra_packages` lists are unioned and installed into a derivative image
layered on the shared base, tagged `aisand-pkgs-<hash of the package list>`.
Projects wanting the same packages share one image; changing either list builds a
new one on the next launch. Everything is `apt` only — see the note in
[TODO](TODO) about pip.

## Subcommands

- `aisand shell` / `sh` / `bash` — interactive shell in the sandbox instead of Claude Code. Arguments are passed to bash.
- `aisand add PKG...` / `aisand delete PKG...` / `aisand list` — manage the every-project package list.
- `aisand rebuild` — rebuild the Docker image, then launch Claude Code. Use after editing the Dockerfile or to pick up updates to the base image.
- `aisand prune` — remove all aisand images and memory volumes. Destructive; you lose Claude's memory for every project.

## More

For the threat model in detail, the exact Docker flags, the architecture diagram, troubleshooting, and implementation notes, see [IMPLEMENTATION.md](IMPLEMENTATION.md).

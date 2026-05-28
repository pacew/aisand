FROM debian:bookworm-slim

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    g++ \
    make \
    git \
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    curl \
    wget \
    less \
    ca-certificates \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI globally
RUN npm install -g @anthropic-ai/claude-code

# Add red "SB" prompt marker so sandbox shells are obvious.
# Appended to /etc/bash.bashrc so it wins over Debian's default PS1.
RUN echo 'PS1='\''\[\e[31m\]SB \[\e[0m\]\$ '\''' >> /etc/bash.bashrc

# The container is launched as the host user via `docker run --user`,
# with /etc/passwd, $HOME, and the working directory provided at runtime.
# No user is created in the image.
CMD ["/bin/bash"]

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
    curl \
    wget \
    ca-certificates \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI globally
RUN npm install -g @anthropic-ai/claude-code

# Create non-root user
RUN useradd -m -s /bin/bash claude

# Set working directory to user home
WORKDIR /home/claude

# Switch to non-root user
USER claude

# Set up shell environment
ENV PATH="/home/claude/.npm-global/bin:${PATH}"

# Default shell
CMD ["/bin/bash"]

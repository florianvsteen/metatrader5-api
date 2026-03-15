FROM --platform=linux/amd64 ghcr.io/linuxserver/baseimage-kasmvnc:ubuntujammy AS base

ENV TITLE=MetaTrader
ENV WINEARCH=win64
ENV WINEPREFIX="/config/.wine"
ENV DISPLAY=:0
ENV DEBIAN_FRONTEND=noninteractive

# Basic dependencies only - no winetricks/cabextract/wine32 needed
RUN apt-get update && apt-get install -y \
    dos2unix \
    python3-pip \
    wget \
    python3-xdg \
    netcat-openbsd \
    ca-certificates \
    && update-ca-certificates \
    && pip3 install --upgrade pip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Add WineHQ repository
RUN wget -q -O /tmp/winehq.key https://dl.winehq.org/wine-builds/winehq.key \
    && apt-key add /tmp/winehq.key \
    && add-apt-repository 'deb https://dl.winehq.org/wine-builds/ubuntu/ jammy main' \
    && rm /tmp/winehq.key

# Install Wine stable (64-bit only - MT5 files are pre-copied, no installer needed)
RUN apt-get update && \
    apt-get install --install-recommends -y winehq-stable \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Stage 2: Final image
FROM base

# Copy scripts and app
COPY app /app
COPY scripts /scripts
RUN dos2unix /scripts/*.sh && \
    chmod +x /scripts/*.sh

COPY /root /

# Wine prefix directory with correct ownership
RUN mkdir -p /config/.wine && \
    chown -R abc:abc /config && \
    chmod -R 755 /config

EXPOSE 3000 5000 5001 8001 18812
VOLUME /config

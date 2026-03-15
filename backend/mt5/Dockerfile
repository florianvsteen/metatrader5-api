FROM --platform=linux/amd64 ghcr.io/linuxserver/baseimage-kasmvnc:ubuntujammy AS base

ENV TITLE=MetaTrader
ENV WINEARCH=win64
ENV WINEPREFIX="/config/.wine"
ENV DISPLAY=:0
ENV DEBIAN_FRONTEND=noninteractive

# Basic dependencies
RUN apt-get update && apt-get install -y \
    dos2unix \
    python3-pip \
    wget \
    python3-xdg \
    netcat-openbsd \
    ca-certificates \
    software-properties-common \
    gnupg2 \
    && update-ca-certificates \
    && pip3 install --upgrade pip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Add WineHQ repository for Ubuntu Jammy
RUN mkdir -pm755 /etc/apt/keyrings \
    && wget -q https://dl.winehq.org/wine-builds/winehq.key -O /etc/apt/keyrings/winehq-archive.key \
    && echo "deb [signed-by=/etc/apt/keyrings/winehq-archive.key] https://dl.winehq.org/wine-builds/ubuntu/ jammy main" \
       > /etc/apt/sources.list.d/winehq-jammy.list

# Install Wine stable
RUN dpkg --add-architecture i386 && \
    apt-get update && \
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

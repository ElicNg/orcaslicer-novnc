# Stage 1: Build Easy noVNC
FROM golang:bookworm AS easy-novnc-build
WORKDIR /src
RUN go mod init build && go install github.com/geek1011/easy-novnc@v1.1.0

# Stage 2: Main Image
FROM debian:trixie-slim

ARG PUID=99
ARG PGID=100

# Set locale environment variables
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    openbox tigervnc-standalone-server supervisor gosu \
    lxterminal nano wget openssh-client rsync ca-certificates xdg-utils htop \
    tar xzip gzip bzip2 zip unzip \
    lxde gtk2-engines-murrine gnome-themes-extra gtk2-engines-pixbuf gtk2-engines-murrine arc-theme \
    libwebkit2gtk-4.1-0 freeglut3-dev libgtk2.0-dev libwxgtk3.2-dev libwx-perl libxmu-dev \
    libgl1-mesa-dev libgl1-mesa-dri xdg-utils locales pcmanfm libgtk-3-dev \
    libglew-dev libudev-dev libdbus-1-dev zlib1g-dev locales-all \
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libgstreamer-plugins-bad1.0-dev \
    gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly gstreamer1.0-libav gstreamer1.0-tools squashfuse fuse libfuse2 \
    libglu1-mesa libglx-mesa0 \
    gstreamer1.0-x gstreamer1.0-alsa gstreamer1.0-gl gstreamer1.0-gtk3 \
    gstreamer1.0-qt5 gstreamer1.0-pulseaudio jq curl git firefox-esr && \
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && locale-gen && \
    update-locale LANG=${LANG} LANGUAGE=${LANGUAGE} LC_ALL=${LC_ALL} && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Create proper directories and set ownership
RUN mkdir -p /etc/orcaslicer /var/lib/orcaslicer /opt/orcaslicer && \
    chown -R ${PUID}:${PGID} /etc/orcaslicer /var/lib/orcaslicer /opt/orcaslicer

# Set up OrcaSlicer
WORKDIR /opt/orcaslicer
COPY get_release_info.sh /opt/orcaslicer/
RUN chmod +x /opt/orcaslicer/get_release_info.sh && mkdir -p /opt/orcaslicer/orcaslicer-dist

# Download and extract OrcaSlicer
RUN latestOrcaslicer=$(/opt/orcaslicer/get_release_info.sh url) && \
    curl -sSL ${latestOrcaslicer} -o /opt/orcaslicer/orcaslicer-dist/orcaslicer.AppImage && \
    chmod +x /opt/orcaslicer/orcaslicer-dist/orcaslicer.AppImage && \
    /opt/orcaslicer/orcaslicer-dist/orcaslicer.AppImage --appimage-extract || \
    (mkdir squashfs-root && squashfuse /opt/orcaslicer/orcaslicer-dist/orcaslicer.AppImage squashfs-root)

# Create user and directories with proper permissions
RUN groupadd -o -g ${PGID} orcaslicer 2>/dev/null || true && \
    useradd -o -u ${PUID} -g orcaslicer -m -d /home/orcaslicer orcaslicer 2>/dev/null || true && \
    chown -R ${PUID}:${PGID} /home/orcaslicer

# Set up configuration directories
RUN if [ -d /home/orcaslicer/.config ] && [ ! -L /home/orcaslicer/.config ]; then \
        mv /home/orcaslicer/.config /home/orcaslicer/.config_backup; \
    fi && \
    ln -sfn /etc/orcaslicer/ /home/orcaslicer/.config && \
    echo "XDG_DOWNLOAD_DIR=\"/var/lib/orcaslicer/\"" >> /home/orcaslicer/.config/user-dirs.dirs && \
    echo "file:///var/lib/orcaslicer/ prints" >> /home/orcaslicer/.gtk-bookmarks

# Set up supervisord logging
RUN mkdir -p /var/log/supervisord && chmod 777 /var/log/supervisord

# Copy noVNC and UI configuration files
COPY --from=easy-novnc-build /go/bin/easy-novnc /usr/local/bin/
COPY menu.xml /etc/xdg/openbox/
COPY supervisord.conf /etc/

# Expose ports and define volumes
EXPOSE 8080
VOLUME /etc/orcaslicer /var/lib/orcaslicer

# Run supervisord
ENTRYPOINT ["supervisord", "-c", "/etc/supervisord.conf"]

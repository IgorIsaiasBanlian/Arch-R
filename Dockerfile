FROM archlinux:latest

SHELL ["/usr/bin/bash", "-c"]

# Update system and install base packages
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
    base-devel bc jdk-openjdk file gawk git go gperf \
    perl-json perl-xml-parser ncurses lzop make patchutils \
    python python-setuptools parted unzip wget curl \
    xorg-mkfontscale libxslt zip vim zstd rdfind automake \
    xmlstarlet rsync which sudo rpcsvc-proto perl-parse-yapp xorg-bdftopcf

# Downgrade GCC to 14.x to avoid gnulib _Generic conflicts with GCC 15+
RUN cd /tmp && \
    curl -LO 'https://archive.archlinux.org/packages/g/gcc/gcc-14.2.1%2Br134%2Bgab884fffe3fc-1-x86_64.pkg.tar.zst' && \
    curl -LO 'https://archive.archlinux.org/packages/g/gcc-libs/gcc-libs-14.2.1%2Br134%2Bgab884fffe3fc-1-x86_64.pkg.tar.zst' && \
    pacman -U --noconfirm --overwrite='*' /tmp/gcc-*.pkg.tar.zst && \
    rm -f /tmp/gcc-*.pkg.tar.zst

# Create build user
RUN useradd -m -s /bin/bash docker && \
    echo 'docker ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Set locale
RUN echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \
    locale-gen
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# Ensure Perl tools (pod2man, yapp, etc.) are in standard PATH
RUN for f in /usr/bin/core_perl/*; do [ -f "$f" ] && ln -sf "$f" /usr/bin/ 2>/dev/null; done; \
    for f in /usr/bin/vendor_perl/*; do [ -f "$f" ] && ln -sf "$f" /usr/bin/ 2>/dev/null; done; \
    true

### Cross compiling on ARM
RUN if [ "$(uname -m)" = "aarch64" ]; then pacman -S --noconfirm qemu-user-static; fi
RUN if [ ! -d /lib64 ]; then ln -sf /usr/x86_64-archr-linux-gnu/lib64 /lib64 2>/dev/null || true; fi
RUN if [ ! -d /lib/x86_64-archr-linux-gnu ]; then ln -sf /usr/x86_64-archr-linux-gnu/lib /lib/x86_64-archr-linux-gnu 2>/dev/null || true; fi

RUN mkdir -p /work && chown docker /work

WORKDIR /work
USER docker

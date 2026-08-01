FROM ubuntu:26.04 AS build
ENV DEBIAN_FRONTEND=noninteractive

# Dependencies for optimized static user-mode compilation
RUN apt-get update && apt-get install -y --no-install-recommends \
  build-essential \
  git \
  wget \
  python3 \
  python3-venv \
  python3-tomli \
  ninja-build \
  pkg-config \
  libglib2.0-dev \
  libfdt-dev \
  libpixman-1-dev \
  zlib1g-dev \
  libseccomp-dev \
  liburing-dev \
  ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /build
ARG QEMU_VERSION=11.0.3

# Download source code
RUN wget -O qemu.tar.gz https://github.com/qemu/qemu/archive/refs/tags/v${QEMU_VERSION}.tar.gz && \
    tar -xzf qemu.tar.gz && rm qemu.tar.gz

WORKDIR /build/qemu-${QEMU_VERSION}

# Compilation flags (adjust -O2/-Os/-O3 according to preference)
ENV CFLAGS="-O2 -g0" LDFLAGS="-s"

# Configuration and build
# If any --disable-* option causes an error, remove it.
RUN ./configure \
    --python=/usr/bin/python3 \
    --target-list=x86_64-linux-user \
    --static \
    --disable-debug-info \
    --disable-debug-tcg \
    --disable-werror && \
    make -j"$(nproc)" && \
    make install DESTDIR=/qemu-dist

# Dynamic version, depends on host libraries, for full emulation, as VM
#RUN ./configure --target-list=x86_64-softmmu && \
#    make -j$(nproc) && \
#    make install DESTDIR=/qemu-dist

# Final strip (ignore errors if something is already clean)
RUN find /qemu-dist -type f -executable -exec strip --strip-unneeded {} + || true

# Minimal final stage
FROM scratch
COPY --from=build /qemu-dist/ /qemu-dist

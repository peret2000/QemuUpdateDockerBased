FROM ubuntu:22.04 AS build
ENV DEBIAN_FRONTEND=noninteractive

# Dependencias para compilación user-mode estática optimizada
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
ARG QEMU_VERSION=10.1.0

# Descarga del código fuente
RUN wget -O qemu.tar.gz https://github.com/qemu/qemu/archive/refs/tags/v${QEMU_VERSION}.tar.gz && \
    tar -xzf qemu.tar.gz && rm qemu.tar.gz

WORKDIR /build/qemu-${QEMU_VERSION}

# Flags de compilación (ajusta -O2/-Os/-O3 según preferencia)
ENV CFLAGS="-O2 -g0" LDFLAGS="-s"

# Configuración y build
# Si alguna opción --disable-* diera error, elimínala.
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

# Strip final (ignora errores si algo ya está limpio)
RUN find /qemu-dist -type f -executable -exec strip --strip-unneeded {} + || true

# Etapa final mínima
FROM scratch
COPY --from=build /qemu-dist/ /qemu-dist
CMD ["/qemu-dist/usr/local/bin/qemu-x86_64", "--version"]

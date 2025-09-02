FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Installs dependencies to compile QEMU
RUN apt-get update && apt-get install -y \
  build-essential \
  git \
  wget \
  libglib2.0-dev \
  libfdt-dev \
  libpixman-1-dev \
  zlib1g-dev \
  python3 \
  python3-venv \
  python3-tomli \
  ninja-build \
  pkg-config \
  libcapstone-dev \
  libseccomp-dev \
  liburing-dev \
  libbpf-dev \
  ca-certificates

WORKDIR /build

# Download QEMU v10.1.0
RUN wget https://github.com/qemu/qemu/archive/refs/tags/v10.1.0.tar.gz && \
    tar -xzf v10.1.0.tar.gz && \
    rm v10.1.0.tar.gz

WORKDIR /build/qemu-10.1.0

# User version, staticlly linked, to run docker or a program
RUN ./configure --target-list=x86_64-linux-user --static && \
    make -j$(nproc) && \
    make install DESTDIR=/qemu-dist

# Dynamic version, depends on host libraries, for full emulation, as VM
#RUN ./configure --target-list=x86_64-softmmu && \
#    make -j$(nproc) && \
#    make install DESTDIR=/qemu-dist

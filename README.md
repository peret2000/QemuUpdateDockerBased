# QEMU Update (Podman/Docker-based Builder)

This repository provides a container-based workflow to build and install a newer QEMU on your Linux host, then re-register binfmt entries so Podman or Docker can use the updated QEMU for cross-architecture containers.

## Motivation

Older QEMU versions can cause subtle and hard-to-debug problems when running or building containers for foreign architectures (for example, building amd64 images on an arm64 host or vice versa). These issues commonly surface due to:
- Kernel and libc (glibc) ABI drift: older QEMU may not fully emulate newer syscalls or kernel behaviors expected by modern distros inside containers.
- Differences in how QEMU parses/handles certain instructions, signals, or vdso interactions that newer userlands rely on.
- Runtime behavior mismatches that manifest as segmentation faults, illegal instruction errors, EINVAL returns on syscalls (e.g., futex, io_uring), or random build failures under emulation.

In short, a newer QEMU often resolves these problems by bringing syscall coverage, instruction decoding, and runtime behavior closer to what modern containers expect.

This project packages a reproducible, containerized build of QEMU and a set of steps to install it on the host and natively reconfigure binfmt via `systemd`.

## What this provides

- A Dockerfile that builds QEMU (e.g., version 10.1.0) and exports the build artifacts to `/qemu-dist`.
- Guidance for installing those artifacts into `/usr/local` (dynamic build) or placing the static user-mode binary at the conventional `qemu-<arch>-static` location.
- Steps to configure binfmt natively natively via `systemd-binfmt` so your container engine natively uses the updated QEMU (crucial for rootless execution).
- A short list of runtime libraries you may need if you install dynamic binaries.

The workflow is distro-agnostic for the build step (because it compiles in a container). Installation and dependency instructions assume a Debian/Ubuntu-like host; adapt package names if your distro differs.

## Prerequisites

- Podman or Docker installed and working on the host.
- Sudo privileges on the host to copy binaries to `/usr/local` or `/usr/bin` and to reconfigure binfmt.
- Optional (dynamic builds only): ability to install runtime libraries through your package manager.

## Build and Install


```bash
# Build the QEMU builder image (example tag uses version 10.1.0)
podman build -t qemu-build:10.1.0 .

# Create a container from the image to access the compiled artifacts
podman create --name qemu-builder qemu-build:10.1.0

# The build output lives inside the container at /qemu-dist
# Copy it out to the host
podman cp qemu-builder:/qemu-dist ./qemu-dist

# Clean up the temporary container
podman rm qemu-builder

# Optionally remove the builder image (keeps your image cache clean)
podman rmi qemu-build:10.1.0

# Install the binaries on the host (dynamic build case):
sudo cp -r ./qemu-dist/usr/local/* /usr/local/

# Remove the exported build directory from the host
rm -rf ./qemu-dist

# Verify installation (system-mode example):
/usr/local/bin/qemu-system-x86_64 --version
```


### Static user-mode build case

If your Dockerfile produced a static user-mode QEMU (common for cross-arch builds under binfmt), the default binary name is typically `qemu-x86\_64`. You can create a link at the standard binfmt target name.  
Beforehand, if `qemu` is already installed in the system, it is advisable to tell the system package manager to not overwrite the locally built version every time it decides to update it: the system will create a *renamed* version of its product.  
So these are the steps:

```bash
# In case qemu is already installed by the system
sudo dpkg-divert --add --rename --divert /usr/bin/qemu-x86_64-static.distrib /usr/bin/qemu-x86_64-static

# Typical location expected by binfmt for static user-mode QEMU:
# (Adjust the architecture suffix if needed)
sudo ln -s /usr/local/bin/qemu-x86_64 /usr/bin/qemu-x86_64-static
```

- binfmt configurations commonly reference `qemu-<arch>-static`. Placing the new binary at this path ensures the binfmt handler uses it without additional configuration changes.

## Reinstall binfmt natively via systemd

Once the QEMU binaries are installed or moved, re-register binfmt natively so the container engine will pick up the new interpreter path. systemd-binfmt injects the F (fix-binary) flag, which is mandatory for rootless configurations:

```bash
# Create the persistent configuration file for systemd
echo ':qemu-x86_64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00:\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/local/bin/qemu-x86_64:OCF' | sudo tee /etc/binfmt.d/qemu-x86_64.conf

# Apply the changes natively on the host
sudo systemctl restart systemd-binfmt.service
```

## Apply the changes

To ensure all services and caches see the new binfmt entries and binaries, reboot the host:

```bash
sudo reboot
```

## Runtime dependencies (dynamic builds)

If you installed dynamic QEMU binaries, you may need these runtime libraries on Debian/Ubuntu:

```bash
sudo apt update
sudo apt install -y libcapstone4 libpixman-1-0 liburing2
```

* QEMU links against libraries such as capstone (disassembly), pixman (pixel manipulation), and io_uring (on newer builds/functions). If they are missing, QEMU may fail to start or lose functionality. Static builds typically embed dependencies and may not require these packages.

---

By refreshing QEMU and re-registering binfmt, you align your host’s emulation layer with what modern container images expect, reducing build-time errors and runtime surprises during cross-architecture development and CI.
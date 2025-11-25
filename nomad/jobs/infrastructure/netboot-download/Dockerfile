# Use a stable Ubuntu LTS release as the base image.
FROM ubuntu:22.04

# Install all necessary tools for the setup scripts.
# - curl: For downloading files.
# - gnupg & ca-certificates: For GPG key verification.
# - util-linux: Provides the 'mount' command.
# - dpkg-deb: To extract files from .deb packages (for the GRUB bootloader).
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    gnupg \
    ca-certificates \
    util-linux \
    dpkg-deb \
    && rm -rf /var/lib/apt/lists/*

# Copy the verification and setup scripts into the container's execution path.
COPY verify-ubuntu-image.sh /usr/local/bin/verify-ubuntu-image.sh
COPY setup-netboot-files.sh /usr/local/bin/setup-netboot-files.sh

# Make the scripts executable.
RUN chmod +x /usr/local/bin/verify-ubuntu-image.sh && \
    chmod +x /usr/local/bin/setup-netboot-files.sh

# The main command to run when the container starts.
# This can be overridden in the Nomad job file if needed.
ENTRYPOINT ["/usr/local/bin/setup-netboot-files.sh"]

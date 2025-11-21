#!/bin/bash
set -euxo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Requires sudo..."
  exec sudo "$0" "$@"
fi

# --- CONFIG ---
ANSIBLE_IMAGE="cowboy-bootstrap-ansible"
PLAYBOOK="/ansible/setup.yaml"
SSH_KEY="$HOME/.ssh/id_ed25519_ansible"

# Generate an SSH key if it doesn’t exist
if [ ! -f "$SSH_KEY" ]; then
  ssh-keygen -t ed25519 -f "$SSH_KEY" -N ""
  cat "${SSH_KEY}.pub" >> ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
fi

apt-get install -y docker.io docker-compose-v2 docker-buildx

# TODO remove after dev
docker build -t ${ANSIBLE_IMAGE} ansible/

docker run --rm -it \
    --privileged \
    --network host \
    -v /:/host \
    -v "$SSH_KEY":/root/.ssh/id_ed25519:ro \
    "$ANSIBLE_IMAGE" \
    -c community.general.chroot \
    -D "$PLAYBOOK"

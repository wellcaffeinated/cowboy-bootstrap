#!/bin/bash
set -euxo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Requires sudo..."
  exec sudo "$0" "$@"
fi

# --- CONFIG ---
ANSIBLE_IMAGE="cowboy-bootstrap-ansible"
PLAYBOOK="/ansible/setup.yaml"

apt-get install -y docker.io docker-compose-v2 docker-buildx

# TODO remove after dev
docker build -t ${ANSIBLE_IMAGE} ansible/

docker run --rm -it \
    --privileged \
    --network host \
    -v /:/host \
    "$ANSIBLE_IMAGE" \
    -c community.general.chroot \
    -e ansible_host=/host \
    -D "$PLAYBOOK" -vvv

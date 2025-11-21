#!/bin/bash
set -euxo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Requires sudo..."
  exec sudo "$0" "$@"
fi

# --- CONFIG ---
ANSIBLE_IMAGE="cowboy-bootstrap-ansible"
PLAYBOOK="/ansible/playbooks/setup.yml"

apt-get install -y docker.io docker-compose-v2

# TODO remove after dev
docker build -t ${ANSIBLE_IMAGE} ansible/

docker run --rm -it \
  --privileged \
  --network host \
  -v /:/host \
  "$ANSIBLE_IMAGE" \
  ansible-playbook \
    -c community.general.chroot \
    -e ansible_host=/host \
    "$PLAYBOOK"

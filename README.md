# Cowboy Bootstrap

Infrastructure bootstrap system for Ubuntu Server using Docker-based Ansible.

## Usage

### Bootstrap Server (First Server)

On a clean Ubuntu Server install with two network interfaces:

```bash
sudo ./begin.sh bootstrap-server
```

Installs Consul, Vault, and Nomad in **server mode** with dual-NIC network configuration.

### Worker Nodes (Additional Servers)

On additional Ubuntu Server installs:

```bash
sudo ./begin.sh aspen-generic
# or just:
sudo ./begin.sh  # aspen-generic is the default
```

Installs Consul and Nomad in **client mode**, connecting to the bootstrap server.

## Device Profiles

| Profile | Purpose | Components |
|---------|---------|------------|
| `bootstrap-server` | Control plane | Consul server, Vault server, Nomad server, dual-NIC NAT gateway |
| `aspen-generic` | Worker node (default) | Consul client, Nomad client |

**Naming convention:**
- `-server` suffix = control plane mode
- `-generic` suffix or no special suffix = worker/client mode
- `aspen-*` prefix = cluster-specific worker nodes

## After Bootstrap

### Verify Installation

```bash
export VAULT_ADDR='http://127.0.0.1:8200'
sudo -E ./tests/phase1-health-check.sh
```

### Initialize Vault (Bootstrap Server Only)

```bash
vault operator init  # Save the keys!
vault operator unseal  # Run 3 times
```

### Access Web UIs

- Consul: `http://<server>:8500`
- Vault: `http://<server>:8200`
- Nomad: `http://<server>:4646`

## Configuration

Node-specific settings in `ansible/inventories/<profile>/group_vars/all.yaml`

Example (bootstrap-server):
```yaml
internet_interface: "eno1"
bootstrap_lan_interface: "enx00e04c1b3a80"
```

## Adding New Node Types

1. Create inventory: `ansible/inventories/<name>/`
2. Create playbook: `ansible/playbooks/<name>.yaml`
3. Add to `begin.sh`

See [PLAN.md](PLAN.md) for detailed architecture and roadmap.

## Background

Based on work by M. Aldridge:
- https://www.michaelwashere.net/post/2025-03-21-nomad-matrix-1/
- https://github.com/the-maldridge/matrix

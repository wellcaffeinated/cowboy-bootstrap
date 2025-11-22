# Bootstrap Infrastructure Plan

## Overview

This project creates a self-bootstrapping infrastructure platform inspired by [M. Aldridge's Nomad/Matrix work](https://www.michaelwashere.net/post/2025-03-21-nomad-matrix-1/). The goal is to enable rapid provisioning of Ubuntu Server nodes for various specialized roles through automated network boot and configuration.

## Current State

The repository contains a Docker-based Ansible bootstrap system that:
- Configures a single Ubuntu Server installation
- Uses privileged Docker container with chroot to avoid requiring Ansible on host
- Installs base packages, hardens SSH, configures NTP, creates users
- Installs HashiCorp Nomad for orchestration

**Current Roles:**
- `base` - Python3 and essential packages
- `chrony` - NTP time synchronization
- `users` - Creates 'cowboy' user with sudo access
- `ssh` - Hardens SSH configuration
- `nomad` - Installs Nomad

## Target Architecture

### Bootstrap Server

A dual-NIC server that:
1. **Self-provisions** using the existing `begin.sh` script
2. **Runs core services:**
   - Nomad (orchestration)
   - Consul (service mesh and service discovery)
   - Vault (secrets management)
   - Terraform (optional, for infrastructure as code)
3. **Acts as provisioning hub** via Nomad jobs:
   - Pixiecore (PXE boot server)
   - HTTP server for cloud-init configs and scripts
   - NAT gateway/router for bootstrap LAN

**Network Interfaces:**
- `eth0` (or primary) - Internet connectivity
- `eth1` (or secondary) - Bootstrap LAN (isolated unmanaged switch)

### Provisioned Nodes

Nodes connect to bootstrap LAN and:
1. Network boot via PXE (Pixiecore)
2. Install Ubuntu Server
3. Fetch and execute `begin.sh` via cloud-init
4. Join Consul mesh for service discovery
5. Register with Nomad for workload scheduling
6. Get moved to production network after initial bootstrap

**Node Types:**
- Specialized roles with different provisioning profiles
- All nodes participate in Nomad/Consul cluster
- Service configuration managed through Nomad jobs

## Implementation Phases

### Phase 1: Bootstrap Server Self-Provisioning
**Goal:** Extend current bootstrap to prepare the bootstrap server

**Tasks:**
- [ ] Add `consul` role to install Consul
- [ ] Add `vault` role to install HashiCorp Vault
  - Install Vault from official HashiCorp repository
  - Configure Vault server mode
  - Set up Consul storage backend for Vault
  - Initialize and unseal Vault (store root token and unseal keys securely)
  - Enable AppRole and SSH auth methods
- [ ] Add `terraform` role (optional installation)
- [ ] Add `network` role to configure dual-NIC setup
  - Configure `eth0` for internet
  - Configure `eth1` for bootstrap LAN (static IP, e.g., 192.168.100.1/24)
  - Enable IP forwarding
  - Configure iptables NAT for bootstrap LAN → internet
- [ ] Add `docker` role (if not already present) for running containerized services
- [ ] Configure Nomad server mode on bootstrap server
- [ ] Configure Consul server mode on bootstrap server

**Deliverables:**
- Bootstrap server can provision itself with all required services
- Network routing operational between both NICs
- Nomad, Consul, and Vault running in server mode
- Vault initialized and integrated with Consul storage backend

### Phase 2: PXE Boot Infrastructure
**Goal:** Enable network boot provisioning via Nomad jobs

**Tasks:**
- [ ] Create Nomad job definition for Pixiecore service
  - Container image with Pixiecore
  - Network mode: host (to bind DHCP/TFTP ports)
  - Volume mounts for boot files and configs
  - Configure DHCP range for bootstrap LAN (e.g., 192.168.100.100-200)
  - Point to cloud-init configuration URL
- [ ] Create Nomad job for HTTP file server
  - Serves Ubuntu netboot images
  - Hosts cloud-init user-data and meta-data
  - Serves this repository's `begin.sh` script
  - Serves repository tarball or git clone endpoint
- [ ] Create cloud-init templates
  - Network configuration for bootstrap LAN
  - Script to download and execute `begin.sh`
  - Post-bootstrap tasks (report to Consul, etc.)
- [ ] Create Ansible role: `bootstrap-server`
  - Deploys Pixiecore Nomad job
  - Deploys HTTP server Nomad job
  - Generates cloud-init configs

**Deliverables:**
- Pixiecore running as Nomad job, serving PXE boot
- HTTP server hosting boot files and scripts
- Cloud-init configuration that bootstraps new nodes

### Phase 3: Node Provisioning Profiles
**Goal:** Support different node types with specialized configurations

**Tasks:**
- [ ] Design provisioning profile system
  - Define profile format (YAML/JSON)
  - Identify profile selection mechanism (MAC address mapping, interactive menu, etc.)
- [ ] Create base provisioning profile
  - Common roles for all nodes (base, chrony, users, ssh)
  - Consul client configuration
  - Nomad client configuration
- [ ] Create specialized provisioning profiles
  - Different Ansible role combinations per profile
  - Nomad client metadata/tags for workload placement (environment, role, tier)
  - Consul service registration
  - **Development profile** - Nodes for testing updates before production
    - Tagged as `env=development` in Nomad metadata
    - Receives updates first for testing
    - Lower priority for critical workloads
  - **Production profile** - Stable nodes for production workloads
    - Tagged as `env=production` in Nomad metadata
    - Receives updates only after validation on dev nodes
    - Higher resource allocation and priority
- [ ] Extend cloud-init to support profile selection
  - Pass profile identifier to `begin.sh`
  - Modify Ansible playbook to use profile-driven role inclusion
- [ ] Create profile management interface
  - Store profiles in Consul KV store
  - API or CLI for profile CRUD operations

**Deliverables:**
- Multiple provisioning profiles available
- Nodes can be provisioned with different roles
- Profile management system operational

### Phase 4: Consul Mesh Integration
**Goal:** Nodes automatically join Consul mesh after bootstrap

**Tasks:**
- [ ] Configure Consul gossip encryption
  - Generate encryption key on bootstrap server
  - Distribute key to nodes via cloud-init or secure fetch
- [ ] Configure Consul ACLs (optional but recommended)
  - Bootstrap ACL system on server
  - Generate client tokens for nodes
- [ ] Create Ansible role: `consul-client`
  - Install Consul
  - Configure as client mode
  - Auto-join bootstrap server
  - Register node services
- [ ] Add consul-client role to provisioning profiles
- [ ] Create health checks and monitoring
  - Consul health checks for node services
  - Dashboard for cluster status

**Deliverables:**
- Nodes automatically join Consul mesh
- Service discovery operational
- Cluster health visible via Consul UI

### Phase 5: Ongoing Management via Nomad
**Goal:** Manage nodes through Nomad-scheduled Ansible jobs

**Tasks:**
- [ ] Create base Ansible runner container image
  - Contains Ansible and required collections
  - Can target nodes via SSH or Consul service discovery
- [ ] Create Nomad job templates for common tasks
  - System updates: `nomad job run update-systems.nomad`
  - Configuration changes: `nomad job run reconfigure-service.nomad`
  - Package installation: `nomad job run install-package.nomad`
- [ ] Implement task orchestration patterns
  - Use Nomad job constraints to target specific nodes by environment/role
  - Use Consul service metadata for node selection
  - Batch vs rolling update strategies
- [ ] **Implement dev→prod update workflow**
  - **Stage 1: Development deployment**
    - Target nodes with `env=development` constraint
    - Apply updates to dev nodes first
    - Run automated tests and health checks
  - **Stage 2: Validation gate**
    - Monitor dev nodes for issues (configurable time window)
    - Check Consul health status for all dev services
    - Require manual approval or automated validation to proceed
  - **Stage 3: Production deployment**
    - Target nodes with `env=production` constraint
    - Rolling updates to minimize disruption
    - Automatic rollback on health check failures
- [ ] Create management CLI or UI
  - Submit Ansible tasks as Nomad jobs
  - Monitor task execution
  - View results and logs

**Deliverables:**
- Ansible tasks can be run across cluster via Nomad
- Common management tasks automated
- Centralized management interface

### Phase 6: Production Network Migration
**Goal:** Move nodes from bootstrap LAN to production network

**Tasks:**
- [ ] Define production network architecture
  - IP addressing scheme
  - VLAN configuration (if applicable)
  - Firewall rules
- [ ] Create migration procedure
  - Reconfigure network interface
  - Update Consul bind address
  - Update Nomad bind address
  - Verify connectivity to bootstrap server
- [ ] Automate migration process
  - Ansible playbook for network reconfiguration
  - Triggered manually or automatically post-bootstrap
  - Rollback procedure if migration fails
- [ ] Update provisioning flow
  - Cloud-init includes production network config (pending migration)
  - Or manual trigger after physical network reconnection

**Deliverables:**
- Documented migration procedure
- Automated migration playbook
- Nodes operational on production network

## Technical Components

### Pixiecore
- All-in-one PXE boot server
- Provides DHCP, TFTP, and HTTP services
- Configured with cloud-init to bootstrap nodes
- Runs as Nomad job in host network mode

### Cloud-Init
- Provides initial node configuration
- Fetches and executes `begin.sh`
- Configures networking
- Reports bootstrap status

### Consul
- Service discovery and mesh networking
- Stores provisioning profiles (KV store)
- Health checking and monitoring
- Service-to-service communication

### Nomad
- Orchestrates all containerized services
- Schedules workloads across cluster
- Runs Ansible jobs for ongoing management
- Handles service lifecycle
- Integrates with Vault for workload secrets

### Vault
- Centralized secrets management
- Dynamic secrets generation
- Encryption as a service
- Uses Consul as storage backend for HA
- AppRole authentication for Nomad workloads
- SSH secrets engine for node access
- PKI secrets engine for certificate management

### Ansible
- Initial node configuration via `begin.sh`
- Ongoing configuration management via Nomad jobs
- Role-based configuration for different node types
- Retrieves secrets from Vault for sensitive operations

## Network Architecture

### Bootstrap LAN (Phase 1-2)
```
Internet
   |
   | (eth0: DHCP or static)
   |
[Bootstrap Server]
   |
   | (eth1: 192.168.100.1/24)
   |
[Unmanaged Switch] (Bootstrap LAN)
   |
   +-- [Node 1] (192.168.100.100, PXE boot)
   +-- [Node 2] (192.168.100.101, PXE boot)
   +-- [Node N] (192.168.100.1xx, PXE boot)
```

**Bootstrap Server:**
- Runs Pixiecore (DHCP 192.168.100.100-200)
- NAT gateway (iptables MASQUERADE)
- Routes bootstrap LAN traffic to internet

**New Nodes:**
- PXE boot from Pixiecore
- Get DHCP address on bootstrap LAN
- Download Ubuntu installer and cloud-init config
- Install OS and run `begin.sh`
- Join Consul/Nomad cluster

### Production Network (Phase 6)
```
Internet
   |
[Production Network/Router]
   |
   +-- [Bootstrap Server] (production IP)
   |
   +-- [Node 1] (production IP, migrated)
   +-- [Node 2] (production IP, migrated)
   +-- [Node N] (production IP, migrated)

[Bootstrap LAN] (still available for new nodes)
   |
[Unmanaged Switch]
   |
   +-- [New Node] (PXE boot)
```

**Post-Migration:**
- Nodes communicate on production network
- Bootstrap LAN remains available for provisioning new nodes
- Bootstrap server accessible on both networks

## Provisioning Flow

### Step-by-Step: New Node Provisioning

1. **Physical Setup**
   - Connect node to bootstrap LAN switch
   - Power on node with PXE boot enabled

2. **PXE Boot**
   - Node broadcasts DHCP discover
   - Pixiecore responds with DHCP offer (IP + boot server)
   - Node downloads bootloader via TFTP
   - Bootloader fetches kernel and initrd via HTTP

3. **Ubuntu Installation**
   - Network installer boots
   - Cloud-init configuration applied
   - Ubuntu Server installed to disk
   - System reboots

4. **Bootstrap Execution**
   - Cloud-init runs on first boot
   - Fetches this repository (git clone or tarball)
   - Executes `begin.sh` with profile parameter
   - Ansible configures node based on profile

5. **Cluster Join**
   - Node authenticates to Vault using AppRole or SSH auth method
   - Retrieves necessary secrets from Vault (tokens, keys, certificates)
   - Consul client starts and joins mesh
   - Nomad client starts and registers with server
   - Nomad configured to use Vault integration for workload secrets
   - Node services registered in Consul
   - Node ready for workload scheduling

6. **Production Migration** (manual or automated)
   - Network configuration updated
   - Physical connection moved to production network
   - Services reconnect to cluster on new IP
   - Node operational in production

## Open Questions / Decisions

### 1. State Management (TBD)
**Decision needed:** How should Consul/Nomad persistent state be handled?

**Options:**
- Single server (bootstrap server only) - Simple but no HA
- Multi-server cluster (3-5 nodes) - HA but more complex
- External storage backend - Separate state from compute

**Recommendation:** Start with single server, document path to HA cluster

### 2. Profile Selection Mechanism
**Decision needed:** How do nodes know which provisioning profile to use?

**Options:**
- MAC address mapping (stored in Consul KV)
- Interactive menu during PXE boot (requires iPXE scripting)
- DNS-based (hostname determines profile)
- Default profile with manual override

**Recommendation:** Start with MAC address mapping, add interactive menu later

### 3. Security Model
**Decision needed:** What security measures should be implemented?

**Considerations:**
- Vault for secrets management (implemented in Phase 1)
- Consul gossip encryption (strongly recommended)
- Consul ACLs (recommended for production)
- Nomad ACLs (recommended for production)
- Vault-generated certificates for mTLS between services (leveraging PKI engine)
- Bootstrap LAN isolation (physical security)

**Recommendation:**
- Phase 1: Deploy Vault for secrets management
- Phase 4: Implement Consul/Nomad gossip encryption and ACLs, tokens managed in Vault
- Phase 4+: Enable mTLS using Vault PKI engine for service certificates

### 4. Secrets Management
**Decision:** HashiCorp Vault will be used for all secrets management.

**Architecture:**
- Vault server runs on bootstrap server (Phase 1)
- Consul backend provides HA storage for Vault data
- Initial secrets (root token, unseal keys) stored securely offline
- Nodes authenticate to Vault via AppRole (service accounts) or SSH
- Nomad jobs use Vault integration for dynamic secrets
- Ansible retrieves credentials from Vault for configuration tasks

**Secrets Use Cases:**
- SSH keys for node access (SSH secrets engine)
- Database credentials (dynamic generation)
- API tokens and service credentials
- TLS certificates (PKI secrets engine)
- Encryption keys
- Consul/Nomad ACL tokens

**Implementation Notes:**
- Vault must be initialized and unsealed on bootstrap server startup
- Consider auto-unseal options (cloud KMS, transit seal) for production
- Implement proper ACL policies to limit secret access by role
- Rotate secrets regularly using Vault's dynamic secrets features

### 5. Update Strategy
**Decision needed:** How are OS and package updates handled?

**Options:**
- Automated via unattended-upgrades (risky without testing)
- Scheduled via Nomad jobs running Ansible (more control)
- Manual trigger by operator (safest but slowest)
- Immutable infrastructure (re-provision nodes)

**Recommendation:** Use dev→prod promotion workflow (see Phase 5):
1. Deploy updates to development nodes first
2. Monitor and validate (automated tests + health checks)
3. Require manual/automated approval gate
4. Roll out to production nodes with automatic rollback capability

This approach balances safety with automation, ensuring updates are tested before reaching production workloads.

## Future Enhancements

### Short Term
- Monitoring and observability (Prometheus, Grafana)
- Log aggregation (Loki, Elasticsearch)
- Backup and disaster recovery procedures
- Documentation for common operations

### Medium Term
- Web UI for cluster management
- Automated testing of provisioning profiles
- Integration with external authentication (LDAP, OAuth)
- Support for bare-metal GPU nodes

### Long Term
- Multi-site/multi-datacenter support
- Automated capacity planning
- Cost tracking and resource optimization
- Self-healing infrastructure

## Success Criteria

The bootstrap infrastructure will be considered successful when:

1. ✅ Bootstrap server can provision itself from clean Ubuntu install
2. ✅ Vault operational with Consul backend, secrets management functional
3. ✅ New nodes can PXE boot and automatically install Ubuntu
4. ✅ Nodes automatically execute `begin.sh` and join cluster
5. ✅ Multiple provisioning profiles available for different roles (including dev/prod)
6. ✅ Consul mesh operational with service discovery
7. ✅ Nomad can schedule workloads across cluster with Vault integration
8. ✅ Ansible tasks can be run cluster-wide via Nomad jobs
9. ✅ Dev→prod update workflow operational (updates tested on dev nodes before production)
10. ✅ Nodes can be migrated to production network post-bootstrap
11. ✅ System documented and reproducible

## References

- [M. Aldridge - Nomad Matrix Blog Post](https://www.michaelwashere.net/post/2025-03-21-nomad-matrix-1/)
- [M. Aldridge - Nomad Matrix Video](https://www.youtube.com/watch?v=5_kW1HOPa-o)
- [M. Aldridge - Matrix Repository](https://github.com/the-maldridge/matrix)
- [Pixiecore Documentation](https://github.com/danderson/netboot/tree/master/pixiecore)
- [Cloud-Init Documentation](https://cloudinit.readthedocs.io/)
- [HashiCorp Nomad](https://www.nomadproject.io/)
- [HashiCorp Consul](https://www.consul.io/)
- [HashiCorp Vault](https://www.vaultproject.io/)
- [Vault-Nomad Integration](https://developer.hashicorp.com/nomad/docs/integrations/vault-integration)
- [Vault Consul Storage Backend](https://developer.hashicorp.com/vault/docs/configuration/storage/consul)

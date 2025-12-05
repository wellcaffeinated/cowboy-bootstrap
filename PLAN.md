# Bootstrap Infrastructure Plan

## Overview

This project creates a self-bootstrapping infrastructure platform inspired by [M. Aldridge's Nomad/Matrix work](https://www.michaelwashere.net/post/2025-03-21-nomad-matrix-1/). The goal is to enable rapid provisioning of Ubuntu Server nodes for various specialized roles through automated network boot and configuration.

## Current State

The repository contains a Docker-based Ansible bootstrap system that:
- Configures Ubuntu Server installations via chroot-based Ansible in Docker
- Uses privileged Docker container with chroot to avoid requiring Ansible on host
- Supports two bootstrap profiles: `bootstrap-server` and `aspen-generic`
- Installs and configures HashiCorp stack (Consul, Vault, Nomad) with Connect mesh

**Current Roles:**
- `base` - Python3 and essential packages
- `chrony` - NTP time synchronization
- `users` - Creates 'cowboy' user with sudo access
- `ssh` - Hardens SSH configuration
- `network` - Dual-NIC setup with UFW NAT routing
- `hashicorp` - HashiCorp GPG key and repository setup
- `consul-server` - Consul server with Connect service mesh enabled
- `vault-server` - Vault server with Consul storage backend
- `nomad-server` - Nomad server with Consul and Vault integration

**Bootstrap Profiles:**
- `bootstrap-server` - Full control plane with all server roles
- `aspen-generic` - Base system for worker nodes (client roles TODO)

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

### Phase 1: Bootstrap Server Self-Provisioning ✅ COMPLETE
**Goal:** Extend current bootstrap to prepare the bootstrap server

**Tasks:**
- [x] Add `hashicorp` role for shared GPG key and repository setup
- [x] Add `consul-server` role to install Consul server
  - Install Consul from official HashiCorp repository
  - Configure Consul server mode
  - **Enable Consul Connect for service mesh**
  - Configure built-in CA for mTLS certificates
  - Enable gRPC port (8502) for Connect
- [x] Add `vault-server` role to install HashiCorp Vault
  - Install Vault from official HashiCorp repository
  - Configure Vault server mode
  - Set up Consul storage backend for Vault
  - Vault self-registers with Consul via service_registration block
  - Service-to-service communication ready for mTLS via Connect
  - Initialize and unseal Vault (manual step, store root token and unseal keys securely)
  - Enable AppRole and SSH auth methods (TODO: manual configuration after init)
- [x] Add `terraform` role for infrastructure as code
  - Install Terraform from official HashiCorp repository
  - Used for building Docker images and deploying Nomad jobs
  - Manages infrastructure declaratively with state tracking
- [x] Add `network` role to configure dual-NIC setup
  - Configurable interface names via group_vars (eno1, enx00e04c1b3a80, etc.)
  - Configure bootstrap LAN (static IP: 192.168.100.1/24)
  - Enable IP forwarding via sysctl
  - Configure UFW (Uncomplicated Firewall) for NAT routing
  - Set up forwarding rules: bootstrap LAN → internet
- [x] Configure Nomad server mode on bootstrap server (`nomad-server` role)
- [x] Configure Consul server mode on bootstrap server (`consul-server` role)
- [x] Create bootstrap profile system
  - `bootstrap-server` inventory and playbook for control plane
  - `aspen-generic` inventory and playbook for worker nodes
  - `begin.sh` updated to accept profile argument (defaults to aspen-generic)

**Deliverables:**
- ✅ Bootstrap server can provision itself with all required services
- ✅ Network routing operational between both NICs
- ✅ Nomad, Consul, and Vault running in server mode
- ✅ **Consul Connect enabled with automatic mTLS for services**
- ✅ Vault initialized and integrated with Consul storage backend
- ✅ Bootstrap profiles implemented for server vs worker nodes
- ✅ Configurable network interfaces via Ansible variables

**Status:** Phase 1 is functionally complete. Tested and operational on bootstrap server hardware.

### Phase 2: PXE Boot Infrastructure
**Goal:** Enable network boot provisioning via Nomad jobs

**Architecture Decision:** Using **dnsmasq + Shoelaces + Traefik** for PXE boot orchestration. **ARM64/Raspberry Pi 4+ is the primary target**, with x86_64 support to be added later.

**Image Strategy:** Use pre-built Docker images and official Ubuntu ARM64 releases to avoid cross-compilation complexity.

**Storage Strategy:** Netboot files stored in Nomad host volume (e.g., `/opt/netboot`), not in git repository. Only checksums and download scripts tracked in git.

**Tasks:**
- [x] Create Nomad job for dnsmasq service - DHCP + DNS forwarding operational
  - DHCP server for bootstrap LAN (192.168.100.100-200)
  - DNS forwarding to upstream resolvers
  - UFW rules configured (UDP 67/68)
  - Network mode: host (to bind DHCP/DNS ports)
- [ ] Configure Nomad host volume for netboot files
  - Create `/opt/netboot` directory on bootstrap server
  - Configure as Nomad host volume
  - Shared across dnsmasq (TFTP) and Traefik (HTTP)
- [ ] Update dnsmasq configuration for TFTP support
  - Enable TFTP server in dnsmasq.conf
  - Mount netboot volume for serving boot files
  - ARM64-specific boot file paths for RPi4+
- [ ] Create netboot download/setup job
  - Downloads Ubuntu 24.04 LTS ARM64 netboot files
  - Verifies GPG signatures and checksums
  - Extracts to `/opt/netboot/ubuntu-24.04/arm64/`
  - Runs as one-time or periodic Nomad batch job
  - Checksums stored in git for verification
- [ ] Create Nomad job for Shoelaces service
  - Use pre-built Shoelaces image or official release binary
  - Manages PXE boot configurations and profiles
  - Serves boot profiles based on client architecture and MAC address
  - Provides API for dynamic boot configuration
  - Integrates with dnsmasq for boot file selection
- [ ] Create Nomad job for Traefik HTTP server
  - Use official pre-built Traefik image (traefik:3.x)
  - Consul Catalog integration for service discovery
  - Mounts netboot volume for serving files
  - Hosts cloud-init user-data and meta-data
  - Serves this repository's `begin.sh` script
  - Serves repository tarball or git clone endpoint
- [ ] Create cloud-init templates for RPi4+
  - Network configuration for bootstrap LAN
  - Script to download and execute `begin.sh`
  - RPi-specific settings if needed
  - Post-bootstrap tasks (report to Consul, etc.)

**Deliverables:**
- Nomad host volume configured for netboot files
- dnsmasq running as Nomad job, serving DHCP, DNS, and TFTP
- Netboot download job operational with checksum verification
- Shoelaces running as Nomad job, managing RPi4+ boot configs
- Traefik running as Nomad job, serving boot files with Consul integration
- Cloud-init configuration that bootstraps RPi4+ nodes

### Phase 3: ARA Integration & Management Tools
**Goal:** Add Ansible logging and remote management capabilities

**Architecture Pattern:** Inspired by M. Aldridge's Matrix setup, adapted to use our existing Vault infrastructure instead of Nomad Variables.

**Tasks:**
- [ ] Deploy ARA (Ansible Run Analysis) server
  - Create Nomad job for ARA API server (official Docker image)
  - Configure host volume for SQLite database persistence (`/nomad/ara`)
  - Expose on bootstrap network (192.168.100.1:8000)
  - Web UI for viewing all Ansible playbook runs with task details and timing
- [ ] Integrate ARA with Ansible Docker container
  - Add `ara==1.7.2` to ansible/requirements.txt
  - Configure environment variables in Dockerfile:
    - ARA_API_CLIENT=http
    - ARA_API_SERVER=http://192.168.100.1:8000
    - ANSIBLE_CALLBACK_PLUGINS (ARA callback plugin path)
  - No code changes required - passive integration via callback plugin
  - All future `begin.sh` runs automatically logged to ARA
- [ ] Set up GitHub Actions for Ansible container builds
  - Create `.github/workflows/build-ansible.yml` workflow
  - Build and push to GitHub Container Registry (GHCR) on push to master
  - Tag images with git commit SHA for versioning
  - Tag `latest` for default deployments
  - Free registry, no self-hosted infrastructure needed
- [ ] Create parameterized Nomad job for remote Ansible execution
  - Sysbatch job type (dispatch-based, runs on specific nodes)
  - Parameters: IMAGE_TAG (git commit or "latest"), ANSIBLE_PLAYBOOK (path)
  - Uses same chroot pattern as `begin.sh` (privileged, host network, /:/host volume)
  - Limits execution to specific node with `--limit ${node.unique.name}`
  - Pulls versioned images from GHCR
  - All runs automatically logged to ARA
- [ ] Document Vault integration patterns (for future secrets)
  - Vault already installed and configured (uses Consul backend)
  - Document initialization procedure (vault operator init/unseal)
  - Create example Nomad job using Vault integration
  - Vault policies for per-service secret access
  - Use Vault instead of Nomad Variables for production secrets

**Deliverables:**
- ARA server running, accessible at http://192.168.100.1:8000
- All Ansible runs logged with full task history and output
- GitHub Actions automatically builds Ansible images on git push
- Can dispatch Ansible playbooks to any node via Nomad CLI/UI
- Reproducible deployments using git commit-based image tags
- Vault integration documented and ready for secrets management

**Benefits:**
- **Visibility**: Every Ansible run logged with timing, output, and results
- **Remote Management**: Run playbooks on any node without SSH access
- **Reproducibility**: Version-controlled playbook execution via git commits
- **Automation**: CI/CD pipeline builds containers automatically
- **Security**: Vault ready for secrets when needed (already installed)

**Usage Example:**
```bash
# Run system update playbook on specific node with latest code
nomad job dispatch \
  -meta IMAGE_TAG=latest \
  -meta ANSIBLE_PLAYBOOK=/ansible/update.yml \
  ansible@rpi-swift-golden-condor

# Run specific git commit version on bootstrap server
nomad job dispatch \
  -meta IMAGE_TAG=master-abc1234 \
  -meta ANSIBLE_PLAYBOOK=/ansible/bootstrap-server.yml \
  ansible@cowboy-bootstrap

# Update all nodes (loop through node list)
for node in $(nomad node status -json | jq -r '.[].Name'); do
  nomad job dispatch \
    -meta IMAGE_TAG=latest \
    -meta ANSIBLE_PLAYBOOK=/ansible/base.yml \
    "ansible@${node}"
done
```

### Phase 4: Node Provisioning Profiles
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

### Phase 5: Consul Mesh Integration
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

### Phase 6: Ongoing Management via Nomad
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
- [ ] **Enable CI/CD deployment via Cloudflare Tunnel**
  - Deploy Cloudflare Tunnel as Nomad job to expose Nomad API
  - Configure tunnel to expose: Nomad API (for deployments), Consul API (for service discovery), and Vault API (for secrets)
  - Secure with Nomad/Consul/Vault ACL tokens
  - **End goal:** Enable teams to deploy from their own GitHub repositories via GitHub Actions workflows, allowing autonomous deployment to the cluster without SSH access or self-hosted runners
  - Document standard GitHub Actions workflow pattern for teams
- [ ] Create management CLI or UI
  - Submit Ansible tasks as Nomad jobs
  - Monitor task execution
  - View results and logs

**Deliverables:**
- Ansible tasks can be run across cluster via Nomad
- Common management tasks automated
- Centralized management interface

### Phase 7: Production Network Migration
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
- **Consul Connect service mesh with automatic mTLS**
- Built-in Certificate Authority for service certificates
- Stores provisioning profiles (KV store)
- Health checking and monitoring
- Service-to-service communication secured by Connect
- Provides encrypted storage backend for Vault

### Nomad
- Orchestrates all containerized services
- Schedules workloads across cluster
- Runs Ansible jobs for ongoing management
- Handles service lifecycle
- Integrates with Vault for workload secrets
- Native Consul Connect integration for service mesh

### Vault
- Centralized secrets management
- Dynamic secrets generation
- Encryption as a service
- Uses Consul as storage backend for HA
- **Secured via Consul Connect mTLS for service communication**
- AppRole authentication for Nomad workloads
- SSH secrets engine for node access
- PKI secrets engine for certificate management (supplementing Consul Connect CA)

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
**Decision:** Implement defense-in-depth security from Phase 1

**Security Layers:**
- **Consul Connect mTLS** (implemented in Phase 1)
  - Automatic service-to-service encryption via Consul's built-in CA
  - Zero-config mTLS for all registered services
  - Certificate rotation handled automatically
- **Vault for secrets management** (implemented in Phase 1)
  - Centralized storage for sensitive credentials
  - Dynamic secrets generation
  - Encryption as a service
- **Consul gossip encryption** (Phase 4)
  - Encrypts Consul's internal cluster communication
- **Consul ACLs** (Phase 4)
  - Fine-grained access control for services and KV store
- **Nomad ACLs** (Phase 4)
  - Workload authorization and job submission control
- **Vault PKI engine** (Phase 4+)
  - Can supplement or replace Connect CA for specific use cases
  - Generates certificates for non-Connect services
- **Bootstrap LAN isolation** (physical security)

**Implementation Timeline:**
- Phase 1: Consul Connect + Vault (automatic mTLS and secrets management)
- Phase 4: Add gossip encryption and ACLs, tokens managed in Vault
- Phase 4+: Extend PKI capabilities as needed

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
2. ✅ Consul Connect operational with automatic mTLS for service-to-service communication
3. ✅ Vault operational with Consul backend, secrets management functional
4. [ ] New nodes can PXE boot and automatically install Ubuntu
5. [ ] Nodes automatically execute `begin.sh` and join cluster
6. [ ] ARA server operational, logging all Ansible playbook runs
7. [ ] GitHub Actions building Ansible containers automatically
8. [ ] Ansible playbooks can be dispatched to any node via Nomad
9. [ ] Multiple provisioning profiles available for different roles (including dev/prod)
10. [ ] Consul mesh operational with service discovery and Connect enabled
11. [ ] Nomad can schedule workloads across cluster with Vault integration and Connect support
12. [ ] Dev→prod update workflow operational (updates tested on dev nodes before production)
13. [ ] Nodes can be migrated to production network post-bootstrap
14. [ ] System documented and reproducible

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

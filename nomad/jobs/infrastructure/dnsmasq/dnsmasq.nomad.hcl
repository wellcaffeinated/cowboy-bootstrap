# dnsmasq - DHCP, DNS, and TFTP server for PXE boot
# Runs on bootstrap server with host networking to bind DHCP/DNS/TFTP ports
# Mounts /opt/netboot/ipxe for serving iPXE bootloader files

job "dnsmasq" {
  datacenters = ["boulder"]
  type        = "service"

  group "dnsmasq" {
    count = 1

    # Run on bootstrap server only
    constraint {
      attribute = "${node.unique.name}"
      value     = "cowboy-bootstrap"
    }

    # Mount netboot directory from host
    volume "netboot" {
      type      = "host"
      source    = "netboot"
      read_only = true
    }

    # Host networking for DHCP (67/68), DNS (53), TFTP (69)
    network {
      mode = "host"
    }

    task "server" {
      driver = "docker"

      config {
        image        = "cowboy-dnsmasq:1"
        force_pull   = false
        network_mode = "host"

        # Capabilities for network operations
        cap_add = [
          "NET_BIND_SERVICE",  # Bind to privileged ports
          "NET_ADMIN",         # Network configuration
          "NET_RAW",           # Raw sockets for DHCP
        ]
      }

      volume_mount {
        volume      = "netboot"
        destination = "/netboot"
        read_only   = true
      }

      resources {
        cpu    = 200
        memory = 256
      }

      restart {
        attempts = 5
        delay    = "5s"
        interval = "30s"
        mode     = "fail"
      }
    }
  }
}

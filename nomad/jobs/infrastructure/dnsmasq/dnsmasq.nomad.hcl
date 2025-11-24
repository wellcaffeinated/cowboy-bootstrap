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

    # Host networking required for DHCP/TFTP
    network {
      mode = "host"
    }

    task "server" {
      driver = "docker"

      config {
        image        = "cowboy-dnsmasq:1"
        force_pull   = false  # Image is built locally, don't pull from registry
        network_mode = "host"

        # Grant specific capabilities for DHCP/TFTP
        cap_add = [
          "NET_BIND_SERVICE",  # Bind to ports < 1024
          "NET_ADMIN",         # Network configuration
          "NET_RAW",           # Raw packets for DHCP
        ]
      }

      resources {
        cpu    = 200
        memory = 256
      }

      # Restart policy - fail fast with retries
      restart {
        attempts = 5
        delay    = "5s"
        interval = "30s"
        mode     = "fail"
      }
    }
  }
}

# Shoelaces - iPXE boot orchestration server
# Serves iPXE boot scripts based on client MAC address/IP

job "shoelaces" {
  datacenters = ["boulder"]
  type        = "service"

  group "shoelaces" {
    count = 1

    # Run on bootstrap server only
    constraint {
      attribute = "${node.unique.name}"
      value     = "cowboy-bootstrap"
    }

    # Mount netboot directory for serving static files
    volume "netboot" {
      type      = "host"
      source    = "netboot"
      read_only = true
    }

    network {
      mode = "bridge"
      port "http" {
        static = 8081
        to     = 8081
      }
    }

    service {
      name = "shoelaces"
      port = "http"
      tags = ["netboot", "ipxe", "bootstrap"]

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "server" {
      driver = "docker"

      config {
        image        = "cowboy-shoelaces:1"
        force_pull   = false
        ports        = ["http"]
        args         = ["-bind-addr=0.0.0.0:8081", "-base-url=192.168.100.1:8081"]
      }

      volume_mount {
        volume      = "netboot"
        destination = "/data/static/ubuntu"
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

job "ara" {
  name        = "ara"
  type        = "service"
  datacenters = ["boulder"]

  group "ara" {
    count = 1

    network {
      mode = "bridge"
      port "http" { to = 8000 }
    }

    service {
      name     = "ara"
      port     = "http"
      provider = "nomad"
    }

    volume "ara_data" {
      type      = "host"
      source    = "ara_data"
      read_only = false
    }

    task "ara" {
      driver = "docker"

      config {
        image = "docker.io/recordsansible/ara-api:fedora43-pypi-latest"
      }

      env {
        ARA_ALLOWED_HOSTS = "['192.168.100.1']"
      }

      volume_mount {
        volume      = "ara_data"
        destination = "/opt/ara"
      }
    }
  }
}

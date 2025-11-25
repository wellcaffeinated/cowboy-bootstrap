# This Nomad job runs a batch process to download and set up all necessary files
# for a UEFI PXE netboot environment. It should be run once or whenever the
# netboot environment needs to be updated.

job "netboot-download" {
  datacenters = ["boulder"]

  # "batch" jobs run to completion and are suitable for one-off tasks.
  type = "batch"

  # Use a high priority to ensure setup tasks run promptly.
  priority = 80

  group "setup" {
    # Define and mount the host volume where netboot files will be stored.
    # This volume must be configured on the Nomad client nodes.
    # Example Nomad client config (/etc/nomad.d/nomad.hcl):
    #
    # client {
    #   host_volume "netboot" {
    #     path      = "/opt/netboot"
    #     read_only = false
    #   }
    # }
    volume "netboot" {
      type      = "host"
      source    = "netboot"
      read_only = false
    }

    task "download-and-prep" {
      # Use the Docker driver to run the containerized setup process.
      driver = "docker"

      # The container image created by the accompanying Dockerfile.
      # This image should be built and pushed to a registry accessible by the Nomad client.
      # For local testing, you can build it with 'docker build . -t ubuntu-netboot-setup'
      # and ensure the image is on the client node.
      config {
        image   = "ubuntu-netboot-setup:latest"
        command = "/usr/local/bin/setup-netboot-files.sh"
        args = [
          "24.04",
          "arm64 amd64",
          "/netboot",
        ]
      }

      # Mount the "netboot" host volume into the container at the "/netboot" path.
      # The setup script uses this path as its default root directory.
      volume_mount {
        volume      = "netboot"
        destination = "/netboot"
        read_only   = false
      }

      # Define resource constraints for the task.
      resources {
        cpu    = 500 # MHz
        memory = 1024 # MB
      }
    }
  }
}

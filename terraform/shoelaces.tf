# Build Shoelaces Docker image
resource "docker_image" "shoelaces" {
  name = "cowboy-shoelaces:1"

  build {
    context    = "${path.module}/${var.infra_path}/shoelaces"
    dockerfile = "Dockerfile"
    tag        = ["cowboy-shoelaces:1"]
  }

  keep_locally = true

  # Rebuild on configuration changes
  triggers = {
    template   = filemd5("${path.module}/${var.infra_path}/shoelaces/templates/default.ipxe.slc")
    dockerfile = filemd5("${path.module}/${var.infra_path}/shoelaces/Dockerfile")
  }
}

# Deploy Shoelaces to Nomad
resource "nomad_job" "shoelaces" {
  jobspec = file("${path.module}/${var.infra_path}/shoelaces/shoelaces.nomad.hcl")

  depends_on = [docker_image.shoelaces]
}

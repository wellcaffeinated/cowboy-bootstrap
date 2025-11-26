# Build dnsmasq Docker image
resource "docker_image" "dnsmasq" {
  name = "cowboy-dnsmasq:1"

  build {
    context    = "${path.module}/${var.infra_path}/dnsmasq"
    dockerfile = "Dockerfile"
    tag        = ["cowboy-dnsmasq:1"]
  }

  keep_locally = true
  triggers = {
    conf = filemd5("${path.module}/${var.infra_path}/dnsmasq/dnsmasq.conf")
  }
}

# Deploy dnsmasq to Nomad
resource "nomad_job" "dnsmasq" {
  jobspec = file("${path.module}/${var.infra_path}/dnsmasq/dnsmasq.nomad.hcl")

  depends_on = [docker_image.dnsmasq]
}

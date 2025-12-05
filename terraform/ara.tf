resource "nomad_job" "ara" {
  jobspec = file("${path.module}/../nomad/jobs/infrastructure/ara/ara.nomad.hcl")
}

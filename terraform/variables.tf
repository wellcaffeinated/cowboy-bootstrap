# Path to infrastructure jobs directory
variable "infra_path" {
  description = "Path to Nomad infrastructure jobs directory"
  type        = string
  default     = "../nomad/jobs/infrastructure"
}

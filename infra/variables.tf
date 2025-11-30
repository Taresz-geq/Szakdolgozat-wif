variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

data "google_project" "current" {
  project_id = var.project_id
}


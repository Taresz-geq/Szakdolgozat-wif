resource "google_artifact_registry_repository" "notes_repo" {
  provider      = google
  project       = var.project_id
  location      = var.region
  repository_id = "notes-api"
  format        = "DOCKER"
  description   = "Artifact Registry for Notes API images"
}

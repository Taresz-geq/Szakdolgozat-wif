resource "google_service_account" "notes_sa" {
  account_id   = "notes-api-sa"
  display_name = "Notes API Service Account"
}

resource "google_project_iam_member" "notes_sa_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.notes_sa.email}"
}

resource "google_project_iam_member" "notes_sa_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.notes_sa.email}"
}

resource "google_cloud_run_service_iam_member" "notes_invoker" {
  project  = var.project_id
  location = var.region
  service  = google_cloud_run_service.notes_service.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.notes_sa.email}"
}

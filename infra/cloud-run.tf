resource "google_cloud_run_service" "notes_service" {
  name     = "notes-api"
  location = var.region
  project  = var.project_id

  template {
    metadata {
      annotations = {
        "run.googleapis.com/cloudsql-instances" = google_sql_database_instance.notes_instance.connection_name
      }
    }

    spec {
      service_account_name = google_service_account.notes_sa.email

      containers {
        image = "${var.region}-docker.pkg.dev/${var.project_id}/notes-api/notes-api:latest"

        env {
          name  = "DB_USER"
          value = "postgres"
        }

        env {
          name = "DB_PASSWORD"
          value_from {
            secret_key_ref {
              name = google_secret_manager_secret.db_password.secret_id
              key  = "latest"
            }
          }
        }

        env {
          name  = "DB_NAME"
          value = google_sql_database.notes_db.name
        }

        env {
          name  = "DB_CONN"
          value = google_sql_database_instance.notes_instance.connection_name
        }
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [
    google_sql_database.notes_db,
    google_sql_user.notes_user,
    google_artifact_registry_repository.notes_repo,
    google_secret_manager_secret_iam_member.db_password_access,
    google_project_iam_member.cloud_sql_client
  ]
}



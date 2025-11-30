resource "google_sql_database_instance" "notes_instance" {
  name             = "notes-instance"
  project          = var.project_id
  region           = var.region
  database_version = "POSTGRES_14"

  settings {
    tier = "db-f1-micro"
  }

  deletion_protection = false
}

resource "google_sql_database" "notes_db" {
  name     = "notesdb"
  project  = var.project_id
  instance = google_sql_database_instance.notes_instance.name
}

resource "google_sql_user" "notes_user" {
  name     = "postgres"
  instance = google_sql_database_instance.notes_instance.name
  password = var.db_password
  project  = var.project_id
}

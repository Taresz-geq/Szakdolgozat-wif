resource "google_api_gateway_api" "notes_api" {
  provider = google-beta
  api_id   = "notes-api"
}

resource "google_api_gateway_api_config" "notes_api_config" {
  provider      = google-beta
  api           = google_api_gateway_api.notes_api.api_id
  api_config_id = "notes-config"

  openapi_documents {
    document {
      path = "openapi.yaml"
      contents = base64encode(
        templatefile("${path.module}/openapi.yaml.tpl", {
          cloud_run_url = google_cloud_run_service.notes_service.status[0].url
        })
      )
    }
  }
}

resource "google_api_gateway_gateway" "notes_gateway" {
  provider   = google-beta
  gateway_id = "notes-gateway"
  api_config = google_api_gateway_api_config.notes_api_config.id
  region     = var.region
}

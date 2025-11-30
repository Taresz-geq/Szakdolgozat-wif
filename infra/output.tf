output "cloud_run_url" {
  value = google_cloud_run_service.notes_service.status[0].url
}

output "api_gateway_url" {
  value = "https://${google_api_gateway_gateway.notes_gateway.default_hostname}"
}

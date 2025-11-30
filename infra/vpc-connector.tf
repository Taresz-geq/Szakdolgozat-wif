# resource "google_vpc_access_connector" "notes_connector" {
#   name    = "notes-connector"
#   region  = var.region
#   project = var.project_id

#   subnet {
#     name = google_compute_subnetwork.notes_connector_subnet.name
#   }

#   machine_type   = "e2-micro"
#   min_instances  = 2
#   max_instances  = 3
# }

# resource "google_compute_network" "notes_vpc" {
#   name                    = "notes-vpc"
#   project                 = var.project_id
#   auto_create_subnetworks = false
# }

# resource "google_compute_subnetwork" "notes_connector_subnet" {
#   name          = "notes-connector-subnet"
#   ip_cidr_range = "10.10.0.0/28"
#   region        = var.region
#   network       = google_compute_network.notes_vpc.name
#   project       = var.project_id
# }

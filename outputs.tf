
output "cert-map" {
  description   = "List of created certificate_map resource (if any)"
  value         = google_certificate_manager_certificate_map.m
}

output "dns-records" {
  description   = "A map of DNS records created (to authorize certs)"
  value         = google_dns_record_set.d
}

output "keys" {
  description   = "The list of all keys, some used in each of the below maps"
  value         = local.keys
}

output "dns-auths" {
  description   = "A map of DNS authentications created"
  value         = google_certificate_manager_dns_authorization.a
}

output "certs" {
  description   = "A map of certificates created"
  value         = google_certificate_manager_certificate.c
}

output "primary" {
  description   = "A 1- or 0-entry map with the PRIMARY map entry created"
  value         = google_certificate_manager_certificate_map_entry.primary
}

output "others" {
  description   = "A map of non-PRIMARY map entries created"
  value         = google_certificate_manager_certificate_map_entry.others
}

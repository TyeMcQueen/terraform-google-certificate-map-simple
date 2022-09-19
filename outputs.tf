
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
  description   = "A map of DNS authorizations created"
  value         = google_certificate_manager_dns_authorization.a
}

output "dns-certs" {
  description   = "A map of DNS-authorized certificates created"
  value         = google_certificate_manager_certificate.dns
}

output "lb-certs" {
  description   = "A map of LB-authorized certificates created"
  value         = google_certificate_manager_certificate.lb
}

output "primary" {
  description   = "A 1- or 0-entry map with the PRIMARY map entry created"
  value         = google_certificate_manager_certificate_map_entry.primary
}

output "others" {
  description   = "A map of non-PRIMARY map entries created"
  value         = google_certificate_manager_certificate_map_entry.others
}


terraform {
  required_version = ">= 0.13"
  required_providers {
    google = {
      source  = "hashicorp/google-beta"
      version = ">= 4.30"
    }
  }
}

# So we can look up the project ID:
data "google_client_config" "default" {
}

locals {
  # Try to give a hint what failed if local.project ends up empty:
  project = "" != var.project ? var.project : [
    for p in [ data.google_client_config.default.project ] :
    try( "" != p, false ) ? p
    : "google_client_config.default does not define '.project'" ][0]
}

resource "google_project_service" "required" {
  for_each  = toset([
    "certificatemanager.googleapis.com",
  ])
  project   = local.project
  service   = each.value

  disable_on_destroy            = false
  disable_dependent_services    = false
}

locals {
  # Parse var.dns-zone-ref to get a project ID and a managed zone title:
  dns-parts = split( "/", var.dns-zone-ref )
  zone-proj = ( 2 == length(local.dns-parts)
    ? local.dns-parts[0] : local.project )
  # Only use local.dns-data-title in 'data "google_dns_managed_zone"' block:
  dns-data-title = ( var.dns-zone-ref == "" ? "" :
    2 == length(local.dns-parts) ? local.dns-parts[1] :
    1 == length(local.dns-parts) ? local.dns-parts[0] :
    "For dns-zone-ref, resource ID is not supported (${var.dns-zone-ref})" )
}

# Look up managed DNS zone created elsewhere:
data "google_dns_managed_zone" "z" {
  count     = local.dns-data-title == "" ? 0 : 1
  name      = local.dns-data-title
  project   = local.zone-proj
}

locals {
  # Version of managed zone title that gives hint if no such zone found:
  zone-title = ( var.dns-zone-ref == "" ? ""
    : [ for name in [ data.google_dns_managed_zone.z[0].name ] :
        try( 0 < length(name), false ) ? name
        : "DNS Zone ${local.zone-proj}/${local.dns-data-title} not found" ][0] )
  zone-domain = ( var.dns-zone-ref == "" ? "/no-zone-ref"
    : [ for dom in [ data.google_dns_managed_zone.z[0].dns_name ] :
          try( 0 < length(dom), false )
            ? trimsuffix( dom, "." )
            : "/invalid-zone-ref" ][0] )

  # Map from value in var.hostnames to fully-qualified domain, skipping
  #     hostnames with "|" (used for creating DNS-authorized certs):
  fqdns = { for h in var.hostnames : h => (
    1 == length(split(".",h))
      ? "${h}.${local.zone-domain}"
      : "." == substr(h,-1,1) ? "${h}${local.zone-domain}" : h )
    if length(split("|",h)) < 2 }

  # Hosts for LB-authorized certs:
  lbhosts = [ for h in var.hostnames :
    split("|",h)[0] if "|LB" == substr(h,-3,3) ]
  # Map from short hostname to full hostname for creating LB-authorized certs:
  lbfqdns = { for h in local.lbhosts : h => (
    1 == length(split(".",h))
      ? "${h}.${local.zone-domain}"
      : "." == substr(h,-1,1) ? "${h}${local.zone-domain}" : h ) }

  # Just the list of fully qualified hostnames (no suffixes) for output
  # as keys for maps of resource records:
  fqs = [ for h in var.hostnames : split("|",h)[0] ]

  # Map from fq to usable resource name version of it:
  toname = { for fq in local.fqs : fq => (
    lower(replace( replace(fq,"*","-"), ".", "-" )) ) }

}

resource "google_certificate_manager_dns_authorization" "a" {
  for_each      = local.fqdns
  project       = local.project
  name          = "${var.name-prefix}${local.toname[each.value]}"
  description   = var.description
  domain        = each.value
  labels        = var.labels
}

locals {
  dns-auth  = google_certificate_manager_dns_authorization.a
  auth-rec  = { for h, a in local.dns-auth : h => a.dns_resource_record.0 }
}

resource "google_dns_record_set" "d" {
  for_each      = local.fqdns
  project       = local.zone-proj
  managed_zone  = local.zone-title
  name          = local.auth-rec[each.key].name
  type          = local.auth-rec[each.key].type
  ttl           = var.dns-ttl-secs
  rrdatas       = [ local.auth-rec[each.key].data ]
}

resource "google_certificate_manager_certificate" "dns" {
  for_each      = local.fqdns
  name          = "${var.name-prefix}${local.toname[each.value]}"
  description   = var.description
  labels        = var.labels
  managed {
    domains             = [ local.dns-auth[each.key].domain ]
    dns_authorizations  = [ local.dns-auth[each.key].id ]
  }
}

resource "google_certificate_manager_certificate" "lb" {
  for_each      = local.lbfqdns
  name          = "${var.name-prefix}${local.toname[each.value]}"
  description   = var.description
  labels        = var.labels
  managed {
    domains             = [ each.value ]
  }
}

resource "google_certificate_manager_certificate_map" "m" {
  count         = var.map-name == "" ? 0 : 1
  name          = var.map-name
  description   = var.description
  project       = local.project
  labels        = merge( var.labels, var.map-labels )
}

locals {
  new-certs = google_certificate_manager_certificate.dns
  lb-certs = google_certificate_manager_certificate.lb
  certs = { for h in var.hostnames : split("|",h)[0] =>
    "|LB" == substr(h,-3,3) ? local.lb-certs[split("|",h)[0]] :
    1 < length(split("|",h)) ? split("|",h)[1] : local.new-certs[h].id }

  primary-name = split( "|", var.hostnames[0] )[0]
  primary = ( var.map-name == "" ? {}
    : { (local.primary-name) = local.certs[local.primary-name] } )
  others = ( var.map-name == "" || length(var.hostnames) < 2 ? {}
    : { for h, id in local.certs : h => id if h != local.primary-name } )
}

resource "google_certificate_manager_certificate_map_entry" "primary" {
  for_each      = local.primary
  map           = google_certificate_manager_certificate_map.m[0].name
  name          = local.toname[each.key]
  description   = var.description
  certificates  = [ each.value ]
  matcher       = "PRIMARY"
  labels        = var.labels
}

resource "google_certificate_manager_certificate_map_entry" "others" {
  for_each      = local.others
  map           = google_certificate_manager_certificate_map.m[0].name
  name          = local.toname[each.key]
  description   = var.description
  certificates  = [ each.value ]
  hostname      = can(local.fqdns[each.key]) ? local.fqdns[each.key] : each.key
  labels        = var.labels
}

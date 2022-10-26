
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
    : "ERROR google_client_config.default does not define '.project'" ][0]
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
  zone-proj = (
    1 == length(local.dns-parts) ? local.project :
    2 == length(local.dns-parts) ? local.dns-parts[0] :
    "projects" == local.dns-parts[0] ? local.dns-parts[1] :
    "ERROR dns-zone-ref URL starts not with projects/ (${var.dns-zone-ref})" )
  # Only use local.dns-data-title in 'data "google_dns_managed_zone"' block:
  dns-data-title = ( var.dns-zone-ref == "" ? "" :
    1 == length(local.dns-parts) ? local.dns-parts[0] :
    2 == length(local.dns-parts) ? local.dns-parts[1] :
      local.dns-parts[ length(local.dns-parts) - 1 ] )
}

# Look up managed DNS zone created elsewhere:
data "google_dns_managed_zone" "z" {
  count     = var.dns-zone-ref == "" ? 0 : 1
  name      = local.dns-data-title
  project   = local.zone-proj
}

locals {
  # Version of managed zone title that gives hint if no such zone found:
  zone-title = ( var.dns-zone-ref == "" ? ""
    : [ for name in [ data.google_dns_managed_zone.z[0].name ] :
        try( 0 < length(name), false ) ? name :
        "ERROR DNS Zone ${local.zone-proj}/${local.dns-data-title} not found"
      ][0] )
  # zone-domain should not be used to compute anything that ends up in
  # `count` or `for_each` meta arguments for `resource` blocks.
  zone-domain = ( var.dns-zone-ref == "" ? "/ERROR-no-dns-zone-ref"
    : [ for dom in [ data.google_dns_managed_zone.z[0].dns_name ] :
          try( 0 < length(dom), false )
            ? trimsuffix( dom, "." )
            : "/ERROR-invalid-dns-zone-ref" ][0] )

  hostnames = [ for e in distinct(flatten([ var.hostnames1, var.hostnames2 ]))
    : e if "|" != substr(e,-1,1) ]

  # Map from input hostname (with optional suffix) to hostname w/o suffix:
  tohost = { for e in local.hostnames : e => split("|",e)[0] }

  # Map from input hostname (with optional suffix) to just the suffix:
  tosuff = { for e in local.hostnames : e => trimprefix( e, local.tohost[e] ) }

  # Map from input hostname (with optional suffix) to the suffix type:
  totype = { for e in local.hostnames : e => (
    local.tosuff[e] == ""    ? "DNS" :
    local.tosuff[e] == "|LB" ? "LB" : "EXT" ) }

  # Map from input hostname (with optional suffix) to a cert-id's index:
  toidx = { for e in local.hostnames :
    e => trimprefix( local.tosuff[e], "|" )
    if local.totype[e] == "EXT" }

  # Map from input hostname (minus suffix) to fully qualified hostname:
  htofq = { for e, h in local.tohost : h =>
    "" == h ? "primary" :
    1 == length(split(".",h)) ? "${h}.${local.zone-domain}" :
    "." == substr(h,-1,1) ? "${h}${local.zone-domain}" : h
  }

  # Map from input hostname (with optional suffix) to which cert map it is
  # included in ("3" means "both"):
  tonum = { for e in local.hostnames : e => (
    ! contains( var.hostnames1, e ) ? "2" :
    ! contains( var.hostnames2, e ) ? "1" : "3" ) }

  # Just the list of hostnames (minus suffixes) for output
  # as keys for maps of resource records:
  keys = distinct([ for e in local.hostnames : local.tohost[e] ])

  # Map from host to usable resource name version of it:
  htoname = { for h in local.keys : h => (
    lower(replace( replace(local.htofq[h],"*",var.star), ".", "-" )) ) }

  # Hostnames for DNS-authorized certs:
  dnsh  = [ for e, h in local.tohost : h if local.totype[e] == "DNS" ]

  # Fully qualified hostnames for LB-authorized certs:
  lbh   = [ for e, h in local.tohost : h if local.totype[e] == "LB" ]

  # Fully qualified hostnames for external certs:
  exth  = [ for e, h in local.tohost : h if local.totype[e] == "EXT" ]
}

resource "google_certificate_manager_dns_authorization" "a" {
  for_each      = toset(local.dnsh)
  project       = local.project
  name          = "${var.name-prefix}${local.htoname[each.value]}"
  description   = var.description
  domain        = trimprefix( local.htofq[each.value], "*." )
  labels        = var.labels
}

resource "google_dns_record_set" "d" {
  for_each      = toset(local.dnsh)
  project       = local.zone-proj
  managed_zone  = local.zone-title
  name          = ( google_certificate_manager_dns_authorization.a[
    each.value].dns_resource_record.0.name )
  type          = ( google_certificate_manager_dns_authorization.a[
    each.value].dns_resource_record.0.type )
  ttl           = var.dns-ttl-secs
  rrdatas       = [ google_certificate_manager_dns_authorization.a[
    each.value].dns_resource_record.0.data ]
}

resource "google_certificate_manager_certificate" "dns" {
  for_each      = toset(local.dnsh)
  name          = "${var.name-prefix}${local.htoname[each.value]}"
  description   = var.description
  labels        = var.labels
  managed {
    domains             = [ local.htofq[each.value] ]
    dns_authorizations  = [
      google_certificate_manager_dns_authorization.a[each.value].id ]
  }
}

resource "google_certificate_manager_certificate" "lb" {
  for_each      = toset(local.lbh)
  name          = "${var.name-prefix}lb-${local.htoname[each.value]}"
  description   = var.description
  labels        = var.labels
  managed {
    domains     = [ local.htofq[each.value] ]
  }
}

resource "google_certificate_manager_certificate_map" "m1" {
  count         = var.map-name1 == "" ? 0 : 1
  name          = var.map-name1
  description   = var.description
  project       = local.project
  labels        = merge( var.labels, var.map-labels )
}

resource "google_certificate_manager_certificate_map" "m2" {
  count         = var.map-name2 == "" ? 0 : 1
  name          = var.map-name2
  description   = var.description
  project       = local.project
  labels        = merge( var.labels, var.map-labels )
}

locals {
  id1 = "" == var.map-name1 ? [] : [ for id in [
    google_certificate_manager_certificate_map.m1[0].id ] :
      1 < length(split( "certificatemanager.googleapis.com", id ))
        ? id : "//certificatemanager.googleapis.com/${id}" ]
  id2 = "" == var.map-name2 ? [] : [ for id in [
    google_certificate_manager_certificate_map.m2[0].id ] :
      1 < length(split( "certificatemanager.googleapis.com", id ))
        ? id : "//certificatemanager.googleapis.com/${id}" ]

  prim1e        = var.map-name1 == "" ? "" : var.hostnames1[0]
  prim1         = var.map-name1 == "" ? "" : local.tohost[ local.prim1e ]
  prim1-suff    = var.map-name1 == "" ? "" : local.tosuff[ local.prim1e ]
  prim1-type    = var.map-name1 == "" ? "" : local.totype[ local.prim1e ]

  prim2e        = var.map-name2 == "" ? "" : var.hostnames2[0]
  prim2         = var.map-name2 == "" ? "" : local.tohost[ local.prim2e ]
  prim2-suff    = var.map-name2 == "" ? "" : local.tosuff[ local.prim2e ]
  prim2-type    = var.map-name2 == "" ? "" : local.totype[ local.prim2e ]

  dns1p = "DNS" != local.prim1-type ? [] : [ local.prim1 ]
  lb1p  = "LB"  != local.prim1-type ? [] : [ local.prim1 ]
  ext1p = "EXT" != local.prim1-type ? {} : {
    (local.prim1) = local.toidx[local.prim1e] }

  dns2p = "DNS" != local.prim2-type ? [] : [ local.prim2 ]
  lb2p  = "LB"  != local.prim2-type ? [] : [ local.prim2 ]
  ext2p = "EXT" != local.prim2-type ? {} : {
    (local.prim2) = local.toidx[local.prim2e] }

  dns1ents  = var.map-name1 == "" ? [] : [ for e, h in local.tohost : h
    if "2" != local.tonum[e] && h != local.prim1 && local.totype[e] == "DNS" ]
  lb1ents   = var.map-name1 == "" ? [] : [ for e, h in local.tohost : h
    if "2" != local.tonum[e] && h != local.prim1 && local.totype[e] == "LB" ]
  ext1ents  = var.map-name1 == "" ? {} : { for e, h in local.tohost :
    h => local.toidx[e]
    if "2" != local.tonum[e] && h != local.prim1 && local.totype[e] == "EXT" }

  dns2ents  = var.map-name2 == "" ? [] : [ for e, h in local.tohost : h
    if "1" != local.tonum[e] && h != local.prim2 && local.totype[e] == "DNS" ]
  lb2ents   = var.map-name2 == "" ? [] : [ for e, h in local.tohost : h
    if "1" != local.tonum[e] && h != local.prim2 && local.totype[e] == "LB" ]
  ext2ents  = var.map-name2 == "" ? {} : { for e, h in local.tohost :
    h => local.toidx[e]
    if "1" != local.tonum[e] && h != local.prim2 && local.totype[e] == "EXT" }
}

resource "google_certificate_manager_certificate_map_entry" "dns1" {
  for_each      = toset(local.dns1ents)
  map           = google_certificate_manager_certificate_map.m1[0].name
  name          = local.htoname[each.value]
  description   = var.description
  labels        = var.labels
  certificates  = [
    google_certificate_manager_certificate.dns[each.value].id ]
  hostname      = local.htofq[each.value]
}

resource "google_certificate_manager_certificate_map_entry" "dns2" {
  for_each      = toset(local.dns2ents)
  map           = google_certificate_manager_certificate_map.m2[0].name
  name          = local.htoname[each.value]
  description   = var.description
  labels        = var.labels
  certificates  = [
    google_certificate_manager_certificate.dns[each.value].id ]
  hostname      = local.htofq[each.value]
}

resource "google_certificate_manager_certificate_map_entry" "lb1" {
  for_each      = toset(local.lb1ents)
  map           = google_certificate_manager_certificate_map.m1[0].name
  name          = local.htoname[each.value]
  description   = var.description
  labels        = var.labels
  certificates  = [
    google_certificate_manager_certificate.lb[each.value].id ]
  hostname      = local.htofq[each.value]
}

resource "google_certificate_manager_certificate_map_entry" "lb2" {
  for_each      = toset(local.lb2ents)
  map           = google_certificate_manager_certificate_map.m2[0].name
  name          = local.htoname[each.value]
  description   = var.description
  labels        = var.labels
  certificates  = [
    google_certificate_manager_certificate.lb[each.value].id ]
  hostname      = local.htofq[each.value]
}

resource "google_certificate_manager_certificate_map_entry" "ext1" {
  for_each      = local.ext1ents
  map           = google_certificate_manager_certificate_map.m1[0].name
  name          = local.htoname[each.key]
  description   = var.description
  labels        = var.labels
  certificates  = [ var.cert-ids[tonumber(each.value)] ]
  hostname      = local.htofq[each.value]
}

resource "google_certificate_manager_certificate_map_entry" "ext2" {
  for_each      = local.ext2ents
  map           = google_certificate_manager_certificate_map.m2[0].name
  name          = local.htoname[each.key]
  description   = var.description
  labels        = var.labels
  certificates  = [ var.cert-ids[tonumber(each.value)] ]
  hostname      = local.htofq[each.value]
}

resource "google_certificate_manager_certificate_map_entry" "dns1p" {
  for_each      = toset(local.dns1p)
  map           = google_certificate_manager_certificate_map.m1[0].name
  name          = local.htoname[each.value]
  description   = var.description
  labels        = var.labels
  certificates  = [
    google_certificate_manager_certificate.dns[each.value].id ]
  matcher       = "PRIMARY"
}

resource "google_certificate_manager_certificate_map_entry" "dns2p" {
  for_each      = toset(local.dns2p)
  map           = google_certificate_manager_certificate_map.m2[0].name
  name          = local.htoname[each.value]
  description   = var.description
  labels        = var.labels
  certificates  = [
    google_certificate_manager_certificate.dns[each.value].id ]
  matcher       = "PRIMARY"
}

resource "google_certificate_manager_certificate_map_entry" "lb1p" {
  for_each      = toset(local.lb1p)
  map           = google_certificate_manager_certificate_map.m1[0].name
  name          = local.htoname[each.value]
  description   = var.description
  labels        = var.labels
  certificates  = [
    google_certificate_manager_certificate.lb[each.value].id ]
  matcher       = "PRIMARY"
}

resource "google_certificate_manager_certificate_map_entry" "lb2p" {
  for_each      = toset(local.lb2p)
  map           = google_certificate_manager_certificate_map.m2[0].name
  name          = local.htoname[each.value]
  description   = var.description
  labels        = var.labels
  certificates  = [
    google_certificate_manager_certificate.lb[each.value].id ]
  matcher       = "PRIMARY"
}

resource "google_certificate_manager_certificate_map_entry" "ext1p" {
  for_each      = local.ext1p
  map           = google_certificate_manager_certificate_map.m1[0].name
  name          = local.htoname[each.key]
  description   = var.description
  labels        = var.labels
  certificates  = [ var.cert-ids[tonumber(each.value)] ]
  matcher       = "PRIMARY"
}

resource "google_certificate_manager_certificate_map_entry" "ext2p" {
  for_each      = local.ext2p
  map           = google_certificate_manager_certificate_map.m2[0].name
  name          = local.htoname[each.key]
  description   = var.description
  labels        = var.labels
  certificates  = [ var.cert-ids[tonumber(each.value)] ]
  matcher       = "PRIMARY"
}


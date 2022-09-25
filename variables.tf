
variable "hostnames" {
  description   = <<-EOD
    Required list of hostnames that (by default) you want GCP-managed
    certificates created for using DNS authorization.  If a hostname
    contains no "." characters or ends with a "." character, then the
    zone domain name is appended (requires `dns-zone-ref`).

    The first host name will be the "PRIMARY" certificate (handed out
    for unmatched hostnames) if a certificate map is created.

    Example:
      hostnames = [ "api", "web.stg.", "my-product.my-domain.com" ]

    Appending a literal "|LB" to a hostname will cause an LB-authorized
    cert to be created instead of a DNS-authorized one.

    Other types of certificates can be included in the created map by
    appending to a hostname a "|" followed by the `.id` of the certificate
    that you created outside of this module.  Doing this with `map-name`
    left as "" will silently do nothing.

    Example:
      hostnames         = [
        "honeypot", "web.stg.|LB",
        join( "|", "*.my-domain.com",
          google_certificate_manager_certificate.my-cert.id ),
      ]

    Using a fully qualified hostname that is not followed by "|" will only
    work if the hostname would be a valid addition to the Zone referenced
    by `dns-zone-ref`.
  EOD
  type          = list(string)
}

variable "dns-zone-ref" {
  description   = <<-EOD
    Either the name given to a GCP-Managed DNS Zone resource in this project,
    "$${project-id}/$${name}" for a DNS Zone in a different project, or ""
    to not use such a Zone.  This is where records to meet DNS authorization
    challenges will be added.  The `.dns_name` of the zone will also be
    appended to any hostnames that contain no "." characters or that end in
    ".".

    If all of your hostnames contain "|" (followed by "LB" or a certificate
    `.id`), then you can set `dns-zone-ref = ""` which would require that
    every hostname be fully qualified, containing at least one "." character
    and not ending with a "." character.

    Examples:
      dns-zone-ref = "my-dns-zone"
      dns-zone-ref = google_dns_managed_zone.my-zone.name
  EOD
  type          = string
  default       = ""
}

variable "map-name" {
  description   = <<-EOD
    An optional name for the Certificate Map to be created.  If left as ""
    then no certificate map is created.  Otherwise, a certificate map is
    created holding all of the created/referenced certificates and where the
    certificate for the first value in `hostnames` is marked as "PRIMARY".

    Example: map-name = "my-api"
  EOD
  type          = string
  default       = ""
}

variable "description" {
  description   = <<-EOD
    An optional description to be used on every created resource (except
    DNS records which don't allow descriptions).

    Example: description = "Created by Terraform module certificate-map-simple"
  EOD
  type          = string
  default       = ""
}

variable "labels" {
  description   = <<-EOD
    A map of label names and values to be applied to every resource created
    by this module (except DNS records which don't allow labels).

    Example:
      labels = { team = "my-team", terraform = "my-workspace" }
  EOD
  type          = map(string)
  default       = {}
}

variable "map-labels" {
  description   = <<-EOD
    A map of label names and values to be applied only to the created
    certificate map.  This is in addition to those in the `labels` input
    variable.  Though, if the same label name appears in both, then only
    the value from `map-labels` will be used on the certificate map.

    Example: map-labels = { service = "my-api" }
  EOD
  type          = map(string)
  default       = {}
}

variable "project" {
  description   = <<-EOD
    GCP Project ID to create Certificate Manager resources in.  Defaults to
    "" which means to use the project from the default Google client config.
  EOD
  type          = string
  default       = ""
}

variable "name-prefix" {
  description   = <<-EOD
    An optional prefix string to prepend to GCP resource `name`s for both
    DNS Authorization resources and Certificate resources.  Can be useful
    when migrating to a new configuration that uses some of the same
    hostnames as the configuration you are migrating away from.

    Example: name-prefix = "v2-"
  EOD
  type          = string
  default       = ""
}

variable "dns-ttl-secs" {
  description   = <<-EOD
    Time-To-Live, in seconds, for created DNS records (challenge data).
  EOD
  type          = number
  default       = 900
}



variable "hostnames1" {
  description   = <<-EOD
    List of hostnames that (by default) you want GCP-managed certificates
    created for using DNS authorization.  If a hostname contains no "."
    characters or ends with a "." character, then the zone domain name is
    appended (requires `dns-zone-ref`).

    The first host name will be the "PRIMARY" certificate (handed out for
    unmatched hostnames) for `map-name1` (if not "").

    Example:
      hostnames1 = [ "api", "web.stg.", "my-product.my-domain.com" ]

    Appending a literal "|LB" to a hostname will cause an LB-authorized
    cert to be created instead of a DNS-authorized one.

    Other types of certificates can be included in the created map by
    appending to a hostname a "|" followed by an index (starting at 0)
    into `cert-ids` selecting the `.id` of a certificate that you created
    outside of this module.  Doing this with `map-name1` left as "" will
    silently do nothing.  If the first hostname references an entry in
    `cert-ids`, then you can even omit the hostname part.

    Example:
      hostnames1 = [ "|0", "web.stg.|LB", "*.my-domain.com|1" ]
      cert-ids   = [
        google_certificate_manager_certificate.honeypot.id,
        google_certificate_manager_certificate.wild.id,
      ]

    Using a fully qualified hostname that is not followed by "|" will only
    work if the hostname would be a valid addition to the Zone referenced
    by `dns-zone-ref`.

    To simplify using this module with the terraform-google-ingress-to-gke
    module, hostnames that end with just the "|" character are simply
    ignored.
  EOD
  type          = list(string)
  default       = []
}

variable "hostnames2" {
  description   = <<-EOD
    Identical to `hostnames1` except that they are used for `map-name2`
    (if not "").

    At least one of `hostnames1` and `hostnames2` should not be left empty.
    You should only use one except during disruption-free migration.
  EOD
  type          = list(string)
  default       = []
}

variable "map-name1" {
  description   = <<-EOD
    An optional name for the (1st) Certificate Map to be created.  If
    left as "" then the (1st) certificate map is not created.  Otherwise,
    a certificate map is created holding each certificate associated with
    an entry in `hostnames1`, with the first marked as "PRIMARY".

    If not "", then `hostnames1` must not be empty.  You should only use one
    of `map-name1` and `map-name2` except during disruption-free migration.

    Example: map-name1 = "my-api"
  EOD
  type          = string
  default       = ""
}

variable "map-name2" {
  description   = <<-EOD
    An optional name for the (2nd) Certificate Map to be created.  If
    left as "" then the (2nd) certificate map is not created.  Otherwise,
    a certificate map is created holding each certificate associated with
    an entry in `hostnames2`, with the first marked as "PRIMARY".

    If not "", then `hostnames2` must not be empty.  You should only use one
    of `map-name1` and `map-name2` except during disruption-free migration.

    Example: map-name2 = "my-api-v2"
  EOD
  type          = string
  default       = ""
}

variable "cert-ids" {
  description   = <<-EOD
    An optional list of the `.id`s for certificates that you created outside
    of this module.  You use each by appending "|" followed by its position
    in this list (starting at 0) to a hostname (in `hostnames1` and/or
    `hostnames2`).

    Example:
      cert-ids   = [
        google_certificate_manager_certificate.api.id,
        google_certificate_manager_certificate.web.id,
      ]
      hostnames1 = [ "api|0", "web|1" ]
  EOD
  type          = list(string)
  default       = []
}

variable "dns-zone-ref" {
  description   = <<-EOD
    Either the name given to a GCP-Managed DNS Zone resource in this project,
    "$${project-id}/$${name}" for a DNS Zone in a different project, or ""
    to not use such a Zone.  This is where records to meet DNS authorization
    challenges will be added.  The `.dns_name` of the zone will also be
    appended to any hostnames that contain no "." characters or that end in
    ".".

    If the DNS zone is managed by this Terraform workspace, then it is best
    if you set this value by referencing the resource block that creates
    the zone, like `dns-zone-ref = google_dns_managed_zone.my-zone.name`.
    This tells Terraform of the dependency, ensuring that the zone creation
    will happen before the module is invoked.

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

variable "star" {
  description   = <<-EOD
    What to use in place of `*` in resource names.  If you want to
    have separate certs for `*.my-domain.com` and `star.my-domain.com`,
    then you should change this value to avoid name collisions.  Must
    use only characters allowed in GCP resource names (likely just
    lowercase letters, numbers, and "-").

    Example: star = "wild"
  EOD
  type          = string
  default       = "star"
}

variable "dns-ttl-secs" {
  description   = <<-EOD
    Time-To-Live, in seconds, for created DNS records (challenge data).
  EOD
  type          = number
  default       = 900
}



variable "hostnames" {
  description   = <<-EOD
    Required list of hostnames that you want GCP-managed certificates for
    using DNS authorization.  If a hostname contains no "." characters, then
    the zone domain name is appended.  The first host name will be the
    "PRIMARY" certificate (handed out for unmatched hostnames).

    Example: hostnames = [ "api", "web", "my-product.my-domain.com" ]

    Other types of certificates can be included in the created map by
    appending to a hostname a "|" followed by the `.id` of the certificate.
    Doing this with `map-name` left as "" will silently do nothing.

    Example:
      hostnames         = [
        "honeypot",
        join( "|", "*.my-domain.com",
          google_certificate_manager_certificate.my-cert.id ),
      ]
  EOD
  type          = list(string)
}

variable "dns-zone-ref" {
  description   = <<-EOD
    (Required) Either the name given to a GCP-Managed DNS Zone resource in
    this project or "$${project-id}/$${name}" for a DNS Zone in a different
    project.  This is where records to meet DNS authentication challenges
    will be added.  The `.dns_name` of the zone will also be appended to
    any hostnames that contain no "." characters.

    Examples:
      dns-zone-ref = "my-dns-zone"
      dns-zone-ref = google_dns_managed_zone.my-zone.name
  EOD
  type          = string
}

variable "map-name" {
  description   = <<-EOD
    An optional name for the Certificate Map to be created.  If left as ""
    then no certificate map is created.  Otherwise, a certificate map is
    create holding all of the created certificates and where the certificate
    for the first value in `hostnames` is marked as "PRIMARY".

    Example: map-name = "my-api"
  EOD
  type          = string
  default       = ""
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
    DNS Authorization resources and Certificate resources.  May be needed
    if you are using multiple DNS Zones in one project and so might have
    a Certificate for "api.widget.example.com" and another for
    "api.gadget.example.com" but can't use the `name` of "api" for both.

    Example: name-prefix = "core-"
  EOD
  type          = string
  default       = ""
}

variable "dns-ttl-secs" {
  description   = <<-EOD
    Time-To-Live, in seconds, for created DNS records.
  EOD
  type          = number
  default       = 900
}

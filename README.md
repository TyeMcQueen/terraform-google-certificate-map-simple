# terraform-google-certificate-map-simple

A Terraform module for using GCP Certificate Manager to create one or
more GCP-managed SSL Certificates (especially DNS-authenticated ones)
and (optionally) place them all into a certificate map.

## Benefits

This module makes it easy to allocate GCP-managed SSL certificates before
even having a working load balancing configuration so you can troubleshoot
any problems with certificate creation before you set up the load balancer
that will use the certificates.

### Resolve Certificate Creation Problems Early

Each certificate creation attempt will usually take 20 minutes or more so
trouble shooting can drag on.  So it is good to be able to start this
process early.

### No Need To Expose Broken Load Balancer

LB-authenticated certificates require you to expose a Load Balancer instance
and even have your desired host name configured to point to it before the
certificate can be created.  Exposing your service like this before it is
working and before it can have a valid certificate may not be ideal.

### Less To Trouble-Shoot

The reduced requirements also mean that there is less that you have
to trouble-shoot when a certificate fails to be issued (compared to
LB-authenticated certificates).

### Better Reliability

DNS-authenticated certificates rely on less infrastructure and you can
safely tear down and/or recreate your load balancer and your host DNS
entries and not impact the certificates.  It is too easy to accidentally
cause an LB-authenticated certificate to be recreated, causing at least
a 20-minute outage.

### Better Security

Any IP address exposed on the internet will get a considerable stream of
probe attempts from hackers and "script kiddies".  If you use certs not
via Certificate Manager, then any probe attempts that use HTTPS will be
handed a certificate letting the hackers know what host name to use with
that IP address.

By using Certificate Manager certificate maps you can specify a specific
certificate to provide for requests that are not using a known host name.
So you can control the host name that the hackers discover.  You can use
a "honeypot" host name that is not used for legitimate traffic and thus
more easily be able to identify requests that you can just reject,
simplifying keeping your endpoint secure and making it easy to remove a
lot of noise from your logs.

## Basic Usage

The following module usage creates 3 GCP-Managed certificates, including the
required DNS challenge entries.  And creates a certificate map including
all of the certificates and where the cert for "honeypot" is given out for
unrecognized host names.

    module "my-cert-map" {
      source  = "github.com/TyeMcQueen/terraform-google-certificate-map-simple"
      version = "0.1.0"

      dns-zone-ref      = "my-zone"
      map-name          = "my-map"
      hostnames         = [ "honeypot", "api", "web" ]
    }

Of course, you probably want to use a less obvious name for your honeypot.

The DNS entries for honeypot.my-domain.com etc. will be managed outside
of the module and do not need to be created before you use this module.  All
you need is a GCP-Managed DNS Zone in your project with the specified name,
for example:

    resource "google_managed_dns_zone" "my-zone" {
      name      = "my-zone"
      dns_name  = "my-domain.com."
    }

You can use the created certificate map via the output variable `cert-map`
which will be an empty list if `map-name` was left empty or a list
containing a single certificate map resource otherwise:

    resource "google_compute_target_https_proxy" "https" {
      name              = ...
      url_map           = ...
      certificate_map   = module.my-cert-map.cert-map[0].id
    }

## Certificates But No Map

The following module usage does not specify `map-name` and so will only
create the certificates and not a certificate map.

    module "certs" {
      source  = "github.com/TyeMcQueen/terraform-google-certificate-map-simple"

      dns-zone-ref      = "my-zone"
      hostnames         = [ "honeypot", "api", "web" ]
    }

## Certificates Not Using DNS-Authentication

Creating a certificate not using DNS authentication only requires a single
`resource` block, so this module does not simplify that part of the process.

But you can use such certificates in the certificate map that this modules
creates.  Simply append to the hostname (in `hostnames`) a "|" followed by
the `.id` of the certificate.

    module "my-cert-map" {
      source  = "github.com/TyeMcQueen/terraform-google-certificate-map-simple"

      dns-zone-ref      = "my-zone"
      map-name          = "my-map"
      hostnames         = [
        "honeypot",
        join( "|", "*.my-domain.com",
          google_certificate_manager_certificate.api-web-cert.id ),
      ]
    }

## More Options

See [Input Variables](/variables.tf) for details about all of the input
variables you can use with this module.  Many less commonly used options
are not covered in the above example.

You can also see the [Ouput](/outputs.tf) declaration but that is quite
simple for this module.

## Limitations

### Types Of Certificates

This module does not simplify the creation of a single DNS-authenticated
certificate that covers multiple hostnames.  It also does not simplify
creation of DNS-authenticated certificates where the DNS is not managed
in GCP or is managed in a GCP project that your Terraform workspace does
not have access to.

But if you create such certificates, you can include them in the certificate
map created by this module as outlined in "Certificates Not Using
DNS-Authentication" above.

It also does not support creating certificates in 2 (or more) different
GCP-managed DNS Zones.  However, you can invoke the module once to simply
create the certificate(s) in one Zone and then invoke it again to create
the certificate(s) in the 2nd zone and create the certificate map,
incorporating the first set of certificate(s) as described above.

Note that when invoking a module more than once you should use a different
name after the `module` keyword, despite that oddly probably requiring you
to run `terraform init` again.

### Types Of Certificate Map Entries

This module does not support having multiple certificates per map entry.

It does not support creating certificate maps that lack a "PRIMARY" entry.

### Google Providers

This module uses the `google-beta` provider and allows the user to control
which version (via standard Terraform features for such).  We would like
to allow the user to pick between using the `google` and the `google-beta`
provider, but Terraform does not allow such flexibility with provider
usage in modules at this time.

You must use at least v4.30 of the `google-beta` provider as earlier
versions did not support Certificate Manager.

You must use at least Terraform v0.13 as the module uses some features
that were not available in earlier versions.

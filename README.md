# terraform-google-certificate-map-simple

A Terraform module for using GCP Cloud Certificate Manager to create one
or more GCP-managed SSL Certificates (especially DNS-authorized ones)
and (optionally) place them all into a certificate map.


## Contents

* [Benefits](#benefits)
* [Basic Usage](#basic-usage)
* [Certificates But No Map](#certificates-but-no-map)
* [Other Certificate Types](#other-certificate-types)
* [More Options](#more-options)
* [Limitations](#limitations)


## Benefits

This module makes it easy to allocate GCP-managed SSL certificates before
even having a working load balancing configuration so you can troubleshoot
any problems with certificate creation before you set up the load balancer
that will use the certificates.

### Resolve Certificate Creation Problems Early

Each certificate creation attempt will usually take about 20 minutes (or
more) so trouble shooting can drag on.  So it is good to be able to start
this process early.

### No Need To Expose Broken Load Balancer

LB-authorized certificates require you to expose a Load Balancer instance
and even have your desired host name configured to point to it before the
certificate can be created.  Exposing your service like this before it is
working and before it can have a valid certificate may not be ideal.

### Less To Trouble-Shoot

The reduced requirements also mean that there is less that you have
to trouble-shoot when a certificate fails to be issued (compared to
LB-authorized certificates).

### Better Reliability

DNS-authorized certificates rely on less infrastructure and you can
safely tear down and/or recreate your load balancer and your host DNS
entries and not impact the certificates.  It is too easy to accidentally
cause an LB-authorized certificate to be recreated, causing a 20-minute
outage (or longer).

### Better Security

Any IP address exposed on the internet will get a considerable stream of
probe attempts from hackers and "script kiddies".  If you use certs not
via Cloud Certificate Manager, then any probe attempts that use HTTPS will
be handed a certificate letting the hackers know what host name to use with
that IP address.

By using Cloud Certificate Manager certificate maps you can specify a
specific certificate to provide for requests that are not using a known host
name.  So you can control the host name that the hackers discover.  You can
use a "honeypot" host name that is not used for legitimate traffic and thus
more easily identify requests that you can just reject, simplifying keeping
your endpoint secure and making it easy to remove a lot of noise from your
logs.

The other benefits require the use of DNS-authorized certificates.  You
get this benefit by using a certificate map, even if you use LB-authorized
certificates in it.


## Basic Usage

The following module usage creates 3 GCP-Managed certificates, including the
required DNS challenge entries.  And creates a certificate map including
all of the certificates and where the cert for "honeypot" is given out for
unrecognized host names.

    module "my-cert-map" {
      source        = (
        "github.com/TyeMcQueen/terraform-google-certificate-map-simple" )
      dns-zone-ref  = "my-zone"
      map-name1     = "my-map"
      hostnames1    = [ "honeypot", "api", "web" ]
    }

Of course, you probably want to use a less obvious name for your honeypot.
And the most common use case would only have 2 hostnames: your honeypot and
your real service hostname.

The DNS entries for honeypot.my-domain.com etc. will be managed outside
of the module and do not need to be created before you use this module.  All
you need is a GCP-Managed DNS Zone in your project with the specified name,
for example:

    resource "google_managed_dns_zone" "my-zone" {
      name      = "my-zone"
      dns_name  = "my-domain.com."
    }

You can use the created certificate map via the output variable `map1`
which will be a 0- or 1-entry list containing the resource record of the
created certificate map.

    resource "google_compute_target_https_proxy" "my-https" {
      # ...
      certificate_map   = module.my-cert-map.map1[0].id
    }

For DNS-authorized certs created by this module, the hostname must be a
subdomain of the GCP-Managed Zone referenced by `dns-zone-ref`.  That domain
is automatically appended to hostnames that either do not contain any "."
characters or that end in a "." character.  So, with the above domain
definition, you could use hostnames like "api", "web.stg.", or
"web.my-domain.com" and get DNS-authorized certs.


## Certificates But No Map

The following module invocation does not specify any map names and so
will only create the certificates and not any certificate maps.

    module "my-certs" {
      source        = (
        "github.com/TyeMcQueen/terraform-google-certificate-map-simple" )
      dns-zone-ref  = "my-zone"
      hostnames1    = [ "honeypot", "api", "web" ]
    }


## Without a GCP-Managed DNS Zone

If your hostname(s) will not reside in a GCP-Managed DNS Zone that
your Terraform workspace can make changes to, then you may want to
use LB-authorized certificates in your certificate map.

    module "my-cert-map" {
      source        = (
        "github.com/TyeMcQueen/terraform-google-certificate-map-simple" )
      map-name1     = "my-map"
      hostnames1    = [
        "honeypot.my-team.example.com|LB",
        "api.my-team.example.com|LB",
      ]
    }

Note that we don't specify `dns-zone-ref`, we append "|LB" to the end
of each hostname, and each hostname is fully qualified.


## Other Certificate Types

Creating a certificate not using DNS authorization only requires a single
`resource` block, so this module does not simplify all of those cases.  We do
simplify the creation of simple LB-authorized certificates by just appending
the literal string "|LB" to the end of a hostname, as noted above.

And you can use certificates that you create elsewhere in the certificate
map that this module creates.  Simply append to the hostname a "|" followed
by the `.id` of the certificate.

    module "my-cert-map" {
      source        = (
        "github.com/TyeMcQueen/terraform-google-certificate-map-simple" )
      dns-zone-ref  = "my-zone"
      map-name1     = "my-map"
      hostnames1    = [
        "honeypot|LB",
        join( "|", "*.my-domain.com",
          google_certificate_manager_certificate.wild-cert.id ),
      ]
    }

This example specifies `dns-zone-ref` so that the short hostname "honeypot"
can be used.  But no DNS-authorized certificates are created so Terraform
only needs read-only access to that zone.


## More Options

See [Input Variables](/variables.tf) for details about all of the input
variables you can use with this module.  Many less commonly used options
are not covered in the above examples.

See [Ouput](/outputs.tf) for the declarations of all available output
values.  Every created resource will be included in one of the output
values.

As documented, you can use `module.NAME.map1[0].id` to associate the
created certificate map with a load balancer.

You can use `module.NAME.certs[HOSTNAME]` to access items in the
`.provisioning_issue` and `.authorization_attempt_info` records to get
information about the status of a certificate.


## Limitations

### Types Of Certificates

This module does not simplify the creation of a single certificate that
covers multiple hostnames (either DNS- or LB-authorized).  It also does not
simplify creation of DNS-authorized certificates where the DNS is not managed
in GCP or is managed in a GCP project that your Terraform workspace does
not have access to.

But if you create such certificates, you can include them in the certificate
map created by this module as outlined in [Other Certificate Types](
#other-certificate-types).

This module does not support Certificates with `scope = "EDGE_CACHE"`.

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
versions did not support Cloud Certificate Manager.

You must use at least Terraform v0.13 as the module uses some features
that were not available in earlier versions.

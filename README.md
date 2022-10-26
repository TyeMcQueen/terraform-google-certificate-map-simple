# terraform-google-certificate-map-simple

A Terraform module for using GCP Cloud Certificate Manager to create one
or more GCP-managed SSL Certificates (especially DNS-authorized ones) and
(optionally) place them all into a certificate map.


## Contents

* [Benefits](#benefits)
* [Basic Usage](#basic-usage)
* [Using Created Certificate Map](#using-created-certificate-map)
* [Certificates But No Map](#certificates-but-no-map)
* [Wildcard Certificate Map](#wildcard-certificate-map)
* [Without a GCP-Managed DNS Zone](#without-a-gcp-managed-dns-zone)
* [Other Certificate Types](#other-certificate-types)
* [More Options](#more-options)
* [Infrastructure Created](#infrastructure-created)
* [Limitations](#limitations)
* [A warning about deletions](#deletions)
* [Input Variables](#input-variables)


## Benefits

This module makes it easy to allocate GCP-managed SSL certificates before
even having a working load balancing configuration so you can troubleshoot
any problems with certificate creation before you set up the load balancer
that will use the certificates.

### Support Disruption-Free Migration

Using DNS-authorized certificates allows for disruption-free migration of
HTTPS traffic.  This was not possible before without resorting at least
temporarily to customer-managed SSL certificates.

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
be handed a certificate letting the hackers know what host name to use
with that IP address.

By using Cloud Certificate Manager certificate maps you can designate a
specific certificate to be returned for requests that are not using a known
hostname.  So you can control the host name that the hackers discover.  You
can use a "honeypot" host name that is not used for legitimate traffic and
thus more easily identify requests that you can just reject, simplifying
keeping your endpoint secure and making it easy to remove a lot of noise
from your logs.

The other benefits require the use of DNS-authorized certificates.  You
get this benefit by using a certificate map, even if you use LB-authorized
certificates in it.


## Basic Usage

The following module usage creates 3 GCP-Managed certificates, including
the required DNS challenge entries.  And creates a certificate map including
all of the certificates and where the cert for "honeypot" is given out for
unrecognized host names.

    module "my-cert-map" {
      source        = (
        "github.com/TyeMcQueen/terraform-google-certificate-map-simple" )
      dns-zone-ref  = "my-zone"
      map-name1     = "my-map"
      hostnames1    = [ "honeypot", "api", "web" ]
    }

Of course, you probably want to use a less obvious name for your honeypot
(having it not in the same sub-domain is also wise).  And the most common
use case would only have 2 hostnames: your honeypot and your real service
hostname.

The DNS entries for honeypot.my-domain.com etc. will be managed outside
of the module and do not need to be created before you use this module.  All
you need is a GCP-Managed DNS Zone in your project with the specified name,
for example:

    resource "google_managed_dns_zone" "my-zone" {
      name      = "my-zone"
      dns_name  = "my-domain.com."
    }

For DNS-authorized certs created by this module, the hostname must be a
subdomain of the GCP-Managed Zone referenced by `dns-zone-ref`.  That domain
is automatically appended to hostnames that either do not contain any "."
characters or that end in a "." character.  So, with the above domain
definition, you could use hostnames like "api", "web.stg.", or
"web.my-domain.com" and get DNS-authorized certs.

### Why The "1"s?

You may have wondered about the input variable names `map-name1` and
`hostnames1`.  There are also `map-name2` and `hostnames2` and you
will usually find either the first pair used or the 2nd pair but not
both at the same time.  This provides a way to make changes to your
certificate map with no disruption to the ingress of your service.  This
approach was selected due to complex aspects of how different parts of
certificate map infrastructure connect together and how Terraform manages
dependencies between items of infrastructure.  You can read more about
how these are used at [Deletions](#deletions).


## Using Created Certificate Map

You can use the certificate map created by this module via the output
value `map-id1[0]` (or `map-id2[0]`) which will be the ID of the created
certificate map.  For example:

    resource "google_compute_target_https_proxy" "my-https" {
      # ...
      certificate_map   = module.my-cert-map.map-id1[0]
    }

Due to a likely bug in the updated APIs that allow you to attach a
certificate map to a load balancer, you should use this output variable
rather than `map1[0].id` so that "//certificatemanager.googleapis.com"
will be prepended, as the APIs currently require.


## Certificates But No Map

The following module invocation does not specify any map names and so
will only create the certificates and not any certificate maps.

    module "my-certs" {
      source        = (
        "github.com/TyeMcQueen/terraform-google-certificate-map-simple" )
      dns-zone-ref  = "my-zone"
      hostnames1    = [ "honeypot", "api", "web" ]
    }

You could use the 2nd ("api") certificate above via the output
value `module.my-certs.dns-certs["api"].id` or
`module.my-certs.dns-certs[module.my-certs.keys[1]].id`.


## Wildcard Certificate Map

The following module invocation will create a certificate map with a single
wildcard certificate via a GCP-Managed DNS Zone.

    module "my-wildcard-cert-map" {
      source        = (
        "github.com/TyeMcQueen/terraform-google-certificate-map-simple" )
      dns-zone-ref  = "my-zone"
      map-name1     = "star-map"
      hostnames1    = [ "*" ]
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

Certificates that you created elsewhere can be used in the certificate map
that this module creates.  Simply append to the hostname a "|" followed
by an offset into `cert-ids`.  When you do that for the first hostname
listed, you can also omit the hostname.

    module "my-cert-map" {
      source        = (
        "github.com/TyeMcQueen/terraform-google-certificate-map-simple" )
      dns-zone-ref  = "my-zone"
      map-name1     = "my-map"
      hostnames1    = [ "|0", "api|1" ]
      cert-ids      = [
        google_certificate_manager_certificate.honey.id,
        google_certificate_manager_certificate.api.id,
      ]
    }

This example specifies `dns-zone-ref` so that the short hostname "api"
can be used.  But no DNS-authorized certificates are created so Terraform
only needs read-only access to that zone.


## More Options

See [Input Variables](#input-variables) or [variables.tf](/variables.tf) for
details about all of the input variables you can use with this module.  Many
less commonly used options are not covered in the above examples.

See [Output](/outputs.tf) for the declarations of all available output
values.  Every created resource will be included in one of the output
values.

As documented, you can use `module.NAME.map-id1[0]` to associate the
created certificate map with a load balancer.

You can use the output values `module.NAME.dns-certs[HOSTNAME]` and
`module.NAME.lb-certs[HOSTNAME]` to access items in the `.provisioning_issue`
and `.authorization_attempt_info` records to get information about the status
of a certificate.


## Infrastructure Created

### Enable Cloud Certificate Manager API

Using the module enables the Certificate Manager API in the GCP project.
Note that this can take longer than Terraform will wait and so the first
time you use this module, you may have to wait a minute and then `apply`
a second time.  There are no input variables nor output values associated
with this.

### Output Value Maps

The resource records for most of the infrastructure created are returned in
output values that are maps where the key is the hostname (minus any "|"
suffix).  The output value `module.NAME.keys` is the list of these hostnames,
first those from `hostnames1` followed by those from `hostnames2`, but
skipping any duplicates (and any hostnames that end in just "|").

For example, consider this invocation of the module:

    module "my-certs" {
      # ...
      hostnames1    = [ "api", "*", "web" ]
    } #                  0      1    2

You could get the `.id` for the wildcard cert created via
`module.my-certs.dns-certs["*"].id` or via
`module.my-certs.dns-certs[module.my-certs.keys[1]].id`.

### DNS-Authorized SSL Certificates

For each hostname you list (in `hostnames1` or `hostnames2`) that does not
contain a "|", a DNS-authorized SSL Certificate is created.  When this module
creates such a certificate, it also creates a DNS Authorization and the DNS
Record that fulfills that authorization.  This last item requires write
access to the GCP-Managed DNS Zone where the hostname would be registered.
Obviously, `dns-zone-ref` must be set for this to work.

The only other [input variables](#input-variables) that impact these
items are:

* `project`
* `name-prefix`, `star`, `description`, and `labels` (except for DNS records,
    which do not support custom names, descriptions, nor labels)
* `dns-ttl-secs` (only the DNS records)

Output values:

* `dns-certs` - A map of resource records for created DNS-auth'ed certificates
* `dns-auths` - A map of resource records for created DNS authorizations
* `dns` - A map of resource records for DNS Records granting authorization

### LB-Authorized SSL Certificates

For each hostname you list (in `hostnames1` or `hostnames2`) that ends in
"|LB", an LB-Authorized SSL Certificate is created.

The only other [input variables](#input-variables) that impact their
creation are:

* `project`, `name-prefix`, `description`, and `labels`

Output values:

* `lb-certs` - A map of resource records for created LB-auth'ed certificates

### Certificate Maps

For each of `map-name1` and `map-name2` that are not left blank, this
module creates a certificate map having the specified name.  The entries
correspond to the entries in the same-numbered `hostnames1` and/or
`hostnames2` variables.

The only other [input variables](#input-variables) that impact their
creation are:

* `project`, `description`, `labels`, and `map-labels`

The output value with the resource record for the `map-name1` certificate
map is `module.NAME.map1[0]`.  For `map-name2`, it is `module.NAME.map2[0]`.

To make use of a certificate map, you'll want its `.id`.  However, what
is likely a bug in the updated APIs that allow a certificate map to be
attached currently means that the `.id` of a Terraform resource record
for a certificate map will not work.  So rather than using
`module.NAME.map1[0].id`, you should use `module.NAME.map-id1[0]` which
will have "//certificate-manager.googleapis.com" prepended to it.

### Certificate Map Entries

When a certificate map is created, an entry is created for each hostname
listed in the same-numbered input variable (`hostnames1` or `hostnames2`),
except for hostnames that end in just "|".

The only other [input variables](#input-variables) that impact their
creation are:

* `cert-ids`, `project`, `description`, and `labels`

The creation of certificate map entries is actually done using a combination
of many different resource blocks.  These are combined into 4 different
output values: `primary1`, `others1`, `primary2`, and `others2`.  The
`primary1` and `primary2` values will each be a 0- or 1-entry list containing
the resource records for the PRIMARY entries.  The `others1` and `others2`
value will each be a Terraform map from hostnames to resource records for
the non-PRIMARY entries.


## Limitations

* [Google Providers](#google-providers)
* [Deletions](#deletions)
* [Unique DNS Authorizations](#unique-dns-authorizations)
* [Types Of Certificates](#types-of-certificates)
* [Types Of Certificate Map Entries](#types-of-certificate-map-Entries)

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

### Deletions

Great care and significant testing has gone in to ensuring that changes to
the inputs used in an invocation of this module can be successfully applied
by Terraform (Terraform was unable to deal with the dependency graph created
by many incarnations of this module).

But that does not mean that such changes would not (temporarily) impact the
function of your ingress.

You must be very cautious about applying any changes that involve deleting
any resources.  Even if Terraform managed to create the replacement before
deleting the prior version (which is itself unlikely and is sometimes not
even supported by GCP), a newly created certificate is not immediately
active.

To make changes without disruption, you first need to add a second
certificate map.  Also, all of the future certificates need to be
DNS-authorized or customer-managed certificates as LB-authorized
certificates just cannot be migrated to without disruption.

[If you are using the [http-ingress](
https://github.com/TyeMcQueen/terraform-google-http-ingress) or
[ingress-to-gke](
https://github.com/TyeMcQueen/terraform-google-ingress-to-gke) module in
a way where it uses this (the certificate-map-simple module) directly,
then this is the point where you need to "unnest" the module invocations
by calling this module directly and passing the created certificate map's
ID to the other module (removing `map-name` and adding `cert-map-ref`).
Then `plan` those changes and verify that you did the unnesting correctly
by noting that Terraform sees no need to make any changes to your actual
infrastructure.]

For example, consider the below simple module invocation.

    module "my-cert-map" {
      source        = (
        "github.com/TyeMcQueen/terraform-google-certificate-map-simple" )
      dns-zone-ref  = "my-zone"
      map-name1     = "my-map"
      hostnames1    = [ "honeypot|LB", "api|LB" ]
    }

If you wanted to move from LB-authorized certs to DNS-authorized certs
without disruption to your service, then you would first provision a 2nd
cert map as shown below.  Make a copy of your existing `map-name1` and
`hostnames1` values, change the "1"s to "2"s in the copied input variable
names, modify the map name (add "-v2" or similar), and make your desired
changes to the `hostnames2` values.

    module "my-cert-map" {
      # ...
      map-name1     = "my-map"
      hostnames1    = [ "honeypot|LB", "api|LB" ]
      map-name2     = "my-map2"
      hostnames2    = [ "honeypot", "api" ]
    }

Make sure to leave the original `map-name1` and `hostnames1` values
unchanged.  Apply the above changes and then wait for the new certificates
to become active.  Then you can switch to the new certificate map.

    resource "google_compute_target_https_proxy" "my-https" {
      # ...
      # Previous configuration:
      # certificate_map = module.my-cert-map.map1[0].id
      certificate_map   = module.my-cert-map.map2[0].id
    }

Apply those changes while leaving the "1" settings in place.  This will
allow you to quickly roll back if you find a problem with your changes.

Finally, you can delete the "1" settings and just leave the "2" settings,
which will delete any no-longer-used certificates, the old map, and related
infrastructure.

    module "my-cert-map" {
      # ...
      map-name2     = "my-map2"
      hostnames2    = [ "honeypot", "api" ]
    }

If you later need to make another set of changes, then do the same steps
but changing the "2"s back to "1"s this time.  If the "2"s bother you,
be warned that you can't just change them back to "1"s, as that would
cause disruption (required by the restrictions of how Terraform tracks
dependencies in such a complex case as this).  Of course, you could repeat
the migration process: switch back to the original map name while copying
the updated `hostnames2` over `hostnames1`, apply those changes, move to the
3rd certificate map, apply again, and finally delete the "2" versions.

Note that you can do this type of disruption-free update by invoking
the module twice.  But if there are DNS-authorized certs that are used
in both of the certificate maps, then doing it this way gets much uglier
because it is not possible to create duplicate DNS-authorized certs.
The end result will also stay uglier because it is impossible to transfer
a DNS-authorized cert created by the first invocation of the module to
the second.  This is why the module itself allows for creating a pair of
certificate maps (that can share certificates created by the module).

### Unique DNS Authorizations

This is not a limitation of this module but is a significant limitation of
Cloud Certificate Manager at the time of this writing.  DNS Authorizations
must be unique across all of GCP for each domain.  This means that trying
to create a DNS Authorization for the same domain in the same project will
fail to `apply`.  Creating duplicate DNS Authorizations in different projects
will mean that only one of them can be active at a time (because they each
will use the same challenge record name but require different data in it).

Each DNS-authorized certificate must link to a valid (but not necessarily
active) DNS Authorization so you can't have duplicate DNS-authorized certs
in a single GCP project.  This has a couple of implications for the use of
this module.

First, changing the value of `name-prefix` while keeping at least one
DNS-authorized cert configured will fail to `apply`.  To change
`name-prefix`, you must first remove all DNS-authorized certs, then you
can change `name-prefix`, and then add the DNS-authorized certs in a
third `apply`.

Second, doing a disruption-free migration from a configuration that is
using a DNS-authorized cert will require sharing the cert between the
new and old certificate maps (unless you use a customer-managed cert
as a replacement in the new certificate map).  This is best done by using
both `map-name1` and `map-name2` as described above.

Though it is possible to reference a DNS-authorized cert created by one
invocation of this module in a new invocation of it.  But then it will
not be simple to migrate the ownership of the DNS Authorization to the
new invocation after the migration.

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


## Input Variables

* [cert-ids](/variables.tf#L88)
* [description](/variables.tf#L134)
* [dns-ttl-secs](/variables.tf#L206)
* [dns-zone-ref](/variables.tf#L106)
* [hostnames1](/variables.tf#L2)
* [hostnames2](/variables.tf#L44)
* [labels](/variables.tf#L145)
* [map-labels](/variables.tf#L157)
* [map-name1](/variables.tf#L56)
* [map-name2](/variables.tf#L72)
* [name-prefix](/variables.tf#L179)
* [project](/variables.tf#L170)
* [star](/variables.tf#L192)

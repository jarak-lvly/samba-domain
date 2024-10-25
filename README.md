# Samba Active Directory Domain Controller for Docker

Forked from https://github.com/Fmstrat/samba-domain  
  
A well documented, tried and tested Samba Active Directory Domain Controller that works with the standard Windows management tools; built from scratch using internal DNS and kerberos and not based on existing containers.
  
  
## Documentation

Latest documentation available at: [https://nowsci.com/samba-domain/](https://nowsci.com/samba-domain/)


## Additional Information

I needed to customize for our environment:  JOINING a Samba DC into an existing Windows AD Domain (functional level 2016).
For this subnet, there are Windows 11 nodes and one linux (app) server.  This set up was for proof of concept before rolling out to production.  
  
Read the documentation at nowsci.com.  I've pretty much left things in the files/scripts as is.  I modified what I needed to for my env and commented out the bits I didn't use.

## Notes
  
### Test lab environment in Hyper-V 
Docker host = Rocky Linux 8.10  
Docker container = Ubuntu 24.04  
Samba Version = 4.19.5-Ubuntu  
Win AD DC = Windows Server 2022 Std  
Win AD client = Windows 11 Pro  
Follow instructions in wiki.samba.org: "Setting up RFC2307 in AD".  The test lab needed to have RFC2307 NIS extensions installed in AD.  
  
   
### Differences
On docker host:  
On the nowsci doc page, they show an example of creating an interface alias, but I had issues on my hyper-v test lab environment.  My workaround was to create a docker ipvlan network.  
  
Dockerfile and init scripts:  
I needed the latest samba build (ubuntu 24.04 had version 4.19.5).  
For testing logon caching -- I created a pam_winbind.conf file that copies over.  
I used a krb5.conf file that works in my environment.  It adds some key value pairs that the init script doesn't add, unless you run the ubuntu-join-domain.sh script, but that uses extra things that I don't need.  
AD Domain functional level is at 2016; add in using the domain join options.  

Windows:   
SYSVOL:  
We don't create/modify GPOs that often, nor do we have a lot of GPOs.  I zipped up the SYSVOL Policies and scripts directories and copied over to the samba DC.  The test Win 11 Pro box picked up the GPOs without any issues.  For this test, it was only for some mapped drives, environment variables, and some files that point to the centralized share (where things get sourced, etc.).  YMMV. 
  
Before JOINING the samba DC to the domain, double check that the users have these attributes set in AD:  
uidNumber  
gidNumber  
  
and maybe these if you need them:  
loginShell  
unixHomeDirectory  

Our production AD already has these unix attributes set, but in the test lab they weren't.  I had to stop samba, clear out the cache and then restart samba in order for the samba DC uid/gids to match what was in Win AD.  


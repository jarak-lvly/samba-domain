#!/bin/bash

set -e

appSetup () {

    # Set variables
    DOMAIN=${DOMAIN:-SAMDOM.LOCAL}
    DOMAINPASS=${DOMAINPASS:-youshouldsetapassword^123}
    JOIN=${JOIN:-false}
    JOINSITE=${JOINSITE:-NONE}
    MULTISITE=${MULTISITE:-false}
    NOCOMPLEXITY=${NOCOMPLEXITY:-false}
    INSECURELDAP=${INSECURELDAP:-false}
    DNSFORWARDER=${DNSFORWARDER:-NONE}
    HOSTIP=${HOSTIP:-NONE}
    RPCPORTS=${RPCPORTS:-"49152-49172"}
    DOMAIN_DC=${DOMAIN_DC:-${DOMAIN_DC}}
    
    LDOMAIN=${DOMAIN,,}
    UDOMAIN=${DOMAIN^^}
    URDOMAIN=${UDOMAIN%%.*}

    # If multi-site, we need to connect to the VPN before joining the domain
    if [[ ${MULTISITE,,} == "true" ]]; then
        /usr/sbin/openvpn --config /docker.ovpn &
        VPNPID=$!
        echo "Sleeping 30s to ensure VPN connects ($VPNPID)";
        sleep 30
    fi

    # Set host ip option
    if [[ "$HOSTIP" != "NONE" ]]; then
        HOSTIP_OPTION="--host-ip=$HOSTIP"
    else
        HOSTIP_OPTION=""
    fi

    # Set up krb5.conf
    mv /etc/krb5.conf /etc/krb5.conf.orig

    # orig
    # echo "[libdefaults]" > /etc/krb5.conf
    # echo "    dns_lookup_realm = false" >> /etc/krb5.conf
    # echo "    dns_lookup_kdc = true" >> /etc/krb5.conf
    # echo "    default_realm = ${UDOMAIN}" >> /etc/krb5.conf

    # Copy pre-existing krb5.conf (minimal) from existing AD domain
    cp -f /files/krb5.conf /etc/.

    # Set up samba
    # If the finished file isn't there, this is brand new, we're not just moving to a new container
    FIRSTRUN=false

    # For some reason /var/lib/samba/private is not there so check first
    # If it is not there you might get an error e.g. : "Failed to open /var/lib/samba/private/secrets.tdb"
    if [[ ! -d /var/lib/samba/private ]]; then
        mkdir /var/lib/samba/private
    else
        echo "Directory /var/lib/private already exists"
    fi

    if [[ ! -f /etc/samba/external/smb.conf ]]; then
        FIRSTRUN=true
        mv /etc/samba/smb.conf /etc/samba/smb.conf.orig
        if [[ ${JOIN,,} == "true" ]]; then
            if [[ ${JOINSITE} == "NONE" ]]; then
                samba-tool domain join ${LDOMAIN} DC -U"${URDOMAIN}\administrator" \
                    --password="${DOMAINPASS}" \
                    --dns-backend=SAMBA_INTERNAL \
                    --option="ad dc functional level = 2016" \
                    --option="winbind offline logon = yes" \
                    --option="winbind request timeout = 10"
            else
                samba-tool domain join ${LDOMAIN} DC -U"${URDOMAIN}\administrator" \
                    --password="${DOMAINPASS}" \
                    --dns-backend=SAMBA_INTERNAL \
                    --option="ad dc functional level = 2016" \
                    --option="winbind offline logon = yes" \
                    --option="winbind request timeout = 10" \
                    --site=${JOINSITE}
            fi
        else
            samba-tool domain provision --use-rfc2307 \
                --domain=${URDOMAIN} \
                --realm=${UDOMAIN} \
                --server-role=dc \
                --dns-backend=SAMBA_INTERNAL \
                --option="winbind offline logon = yes" \
                --option="winbind request timeout = 10" \
                --option="ad dc functional level = 2016" \
                --function-level=2016 \
                --adminpass='${DOMAINPASS}' \
                ${HOSTIP_OPTION}
            if [[ ${NOCOMPLEXITY,,} == "true" ]]; then
                samba-tool domain passwordsettings set --complexity=off
                samba-tool domain passwordsettings set --history-length=0
                samba-tool domain passwordsettings set --min-pwd-age=0
                samba-tool domain passwordsettings set --max-pwd-age=0
            fi
        fi
        sed -i "/\[global\]/a \
            \\\tidmap_ldb:use rfc2307 = yes\\n\
            template shell = /bin/bash\\n\
            template homedir = /home/%U\\n\
            idmap config ${URDOMAIN} : schema_mode = rfc2307\\n\
            idmap config ${URDOMAIN} : unix_nss_info = yes\\n\
            idmap config ${URDOMAIN} : backend = ad\\n\
            rpc server dynamic port range = ${RPCPORTS}\
            " /etc/samba/smb.conf
        sed -i "s/LOCALDC/${URDOMAIN}DC/g" /etc/samba/smb.conf
        if [[ $DNSFORWARDER != "NONE" ]]; then
            sed -i "/dns forwarder/d" /etc/samba/smb.conf
            sed -i "/\[global\]/a \
                \\\tdns forwarder = ${DNSFORWARDER}\
                " /etc/samba/smb.conf
        fi
        if [[ ${INSECURELDAP,,} == "true" ]]; then
            sed -i "/\[global\]/a \
                \\\tldap server require strong auth = no\
                " /etc/samba/smb.conf
        fi
        # Once we are set up, we'll make a file so that we know to use it if we ever spin this up again
        cp -f /etc/samba/smb.conf /etc/samba/external/smb.conf
    else
        cp -f /etc/samba/external/smb.conf /etc/samba/smb.conf
    fi

    # Set up winbind offline logon / pam_winbind cached login
    # Note the winbind options added during domain join
    if [[ ! -f /etc/security/pam_winbind.conf ]]; then
        cp files/pam_winbind.conf /etc/security/pam_winbind.conf
    else
        cp /etc/security/pam_winbind.conf /etc/security/pam_winbind.conf.orig
        sed -i "s/^;cached_login = no/cached_login = yes/" /etc/security/pam_winbind.conf
        sed -i "s/^;krb5_ccache_type =.*/krb5_ccache_type = FILE/" /etc/security/pam_winbind.conf
    fi

    # Create dir for socket
    if [[ ! -d /var/run/supervisor ]] ; then
        mkdir /var/run/supervisor
    else
        echo "Directory /var/run/supervisor already exists"
    fi

    # Set up supervisor and double check default path of supervisord.conf
    if [[ ! -f /etc/supervisor/supervisord.conf.orig ]] ; then
        cp -p /etc/supervisor/supervisord.conf /etc/supervisor/supervisord.conf.orig
        sed -i '/^\[supervisord\]$/a nodaemon=true' /etc/supervisor/supervisord.conf
        sed -i 's|/var/run|/var/run/supervisor|g' /etc/supervisor/supervisord.conf
        echo "[program:ntpd]" >> /etc/supervisor/conf.d/samba_supervisord.conf
        echo "command=/usr/sbin/ntpd -c /etc/ntpsec/ntp.conf -n" >> /etc/supervisor/conf.d/samba_supervisord.conf
        echo "[program:samba]" >> /etc/supervisor/conf.d/samba_supervisord.conf
        echo "command=/usr/sbin/samba -i" >> /etc/supervisor/conf.d/samba_supervisord.conf
    else
        echo "Supervisor mods already exist"
    fi

    if [[ ${MULTISITE,,} == "true" ]]; then
        if [[ -n $VPNPID ]]; then
            kill $VPNPID
        fi
        echo "" >> /etc/supervisor/conf.d/supervisord.conf
        echo "[program:openvpn]" >> /etc/supervisor/conf.d/supervisord.conf
        echo "command=/usr/sbin/openvpn --config /docker.ovpn" >> /etc/supervisor/conf.d/supervisord.conf
    fi

    # Set up ntp config
    echo "" >> /etc/ntpsec/ntp.conf
    echo "# Additional" >> /etc/ntpsec/ntp.conf
    echo "ntpsigndsocket  /usr/local/samba/var/lib/ntp_signd/" >> /etc/ntpsec/ntp.conf
    echo "restrict 172.29.48.0 mask 255.255.255.0 nomodify" >> /etc/ntpsec/ntp.conf
    sed -i 's/\bnopeer\b//g' /etc/ntpsec/ntp.conf

    # Temp fix for this bug
    if [[ ! -d /var/log/ntpsec ]] ; then
        mkdir /var/log/ntpsec
        chown ntpsec:ntpsec /var/log/ntpsec
    else
        echo "Directory /var/log/ntpsec already exists"
    fi

    appStart ${FIRSTRUN}
}

# replace with 20000 the existing Domain Users gidnumber
fixDomainUsersGroup () {
    GIDNUMBER=$(ldbedit -H /var/lib/samba/private/sam.ldb -e cat "samaccountname=domain users" | { grep ^gidNumber: || true; })
    if [ -z "${GIDNUMBER}" ]; then
        echo "dn: CN=Domain Users,CN=Users,${DOMAIN_DC}
changetype: modify
add: gidNumber
gidNumber: 20000" | ldbmodify -H /var/lib/samba/private/sam.ldb
        net cache flush
    fi
}

setupSSH () {
    echo "dn: CN=sshPublicKey,CN=Schema,CN=Configuration,${DOMAIN_DC}
changetype: add
objectClass: top
objectClass: attributeSchema
attributeID: 1.3.6.1.4.1.24552.500.1.1.1.13
cn: sshPublicKey
name: sshPublicKey
lDAPDisplayName: sshPublicKey
description: MANDATORY: OpenSSH Public key
attributeSyntax: 2.5.5.10
oMSyntax: 4
isSingleValued: FALSE
objectCategory: CN=Attribute-Schema,CN=Schema,CN=Configuration,${DOMAIN_DC}
searchFlags: 8
schemaIDGUID:: cjDAZyEXzU+/akI0EGDW+g==" > /tmp/Sshpubkey.attr.ldif
    echo "dn: CN=ldapPublicKey,CN=Schema,CN=Configuration,${DOMAIN_DC}
changetype: add
objectClass: top
objectClass: classSchema
governsID: 1.3.6.1.4.1.24552.500.1.1.2.0
cn: ldapPublicKey
name: ldapPublicKey
description: MANDATORY: OpenSSH LPK objectclass
lDAPDisplayName: ldapPublicKey
subClassOf: top
objectClassCategory: 3
objectCategory: CN=Class-Schema,CN=Schema,CN=Configuration,${DOMAIN_DC}
defaultObjectCategory: CN=ldapPublicKey,CN=Schema,CN=Configuration,${DOMAIN_DC}
mayContain: sshPublicKey
schemaIDGUID:: +8nFQ43rpkWTOgbCCcSkqA==" > /tmp/Sshpubkey.class.ldif
    ldbadd -H /var/lib/samba/private/sam.ldb /var/lib/samba/private/sam.ldb /tmp/Sshpubkey.attr.ldif --option="dsdb:schema update allowed"=true
    ldbadd -H /var/lib/samba/private/sam.ldb /var/lib/samba/private/sam.ldb /tmp/Sshpubkey.class.ldif --option="dsdb:schema update allowed"=true
}

appStart () {
    /usr/bin/supervisord -c /etc/supervisor/supervisord.conf > /var/log/supervisor/supervisor.log 2>&1 &

    if [ "${1}" = "true" ]; then
        #echo "Sleeping 10 before checking on Domain Users of gid 3000000 and setting up sshPublicKey"
        echo "Sleeping 10 before checking on Domain Users of gid 20000"
        sleep 15
        fixDomainUsersGroup
        # we are not storing SSH keys in AD so comment out
        # setupSSH
    fi
    while [ ! -f /var/log/supervisor/supervisor.log ]; do
        echo "Waiting for log files..."
        sleep 1
    done
    sleep 3
    tail -F /var/log/supervisor/*.log
}

appSetup

exit 0

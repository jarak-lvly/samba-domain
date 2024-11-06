FROM ubuntu:24.04

# https://nowsci.com/samba-domain

ENV DEBIAN_FRONTEND noninteractive

RUN \
    apt-get update && \
    apt-get install -y \
        pkg-config \
        attr \
        acl \
        file \
        dos2unix \
        samba \
        samba-ad-dc \
        samba-common \
        samba-dsdb-modules \
        smbclient \
        ldap-utils \
        winbind \
        libnss-winbind \
        libpam-winbind \
        krb5-user \
        krb5-kdc \
        supervisor \
        openvpn \
        ldb-tools \
        vim-tiny \
        curl \
        dnsutils \
        iproute2 \
        iputils-ping \
        ntp && \
    apt-get clean autoclean && \
    apt-get autoremove --yes && \
    rm -rf /var/lib/{apt,dpkg,cache,log}/ && \
    rm -rf /tmp/* /var/tmp/*

VOLUME [ "/var/lib/samba", "/etc/samba/external" ]

RUN mkdir -p /files
COPY ./files/ /files/
RUN chmod 755 /files/init.sh /files/domain.sh
CMD /files/init.sh

#!/bin/ksh

#
# nfskrb5test1.ksh - KDC test script for Windows NFS krb5 setup test #001
#
# Written by Roland Mainz <roland.mainz@nrubsig.org>
#

#
# This is a very simple *TEST* script which sets up a Kerberos5 KDC and
# NFSv4.1 server with GSSAPI on the same machine
#
# This script requires the following Debian 11/13 packages:
# $ apt-get install krb5-user krb5-kdc libkrb5-dev krb5-admin-server keyutils ksh nfs-kernel-server nfs-common nfs4-acl-tools
#
# setup Windows machine
# On Windows machine use (via Cygwin bash/ksh93 shell):
# --- snip ---
# # KDC and NFS server must have entries in "/cygdrive/c/Windows/System32/drivers/etc/hosts"
# printf '10.49.202.233\t\tdebnfskrb5001.nfschicken.test\n' >>/cygdrive/c/Windows/System32/drivers/etc/hosts
# printf '10.49.202.233\t\tdebnfskrb5001\n' >>/cygdrive/c/Windows/System32/drivers/etc/hosts
# ksetup /setrealm NFSCHICKEN.TEST
# ksetup /addkdc NFSCHICKEN.TEST debnfskrb5001.nfschicken.test
# ksetup /setrealmflags NFSCHICKEN.TEST tcpsupported
# ksetup /mapuser rmainz@NFSCHICKEN.TEST roland_mainz
# ksetup /setcomputerpassword myhorriblepassword12
# # user has to do the Windows logon as user "rmainz@NFSCHICKEN.TEST", NOT as "roland_mainz"
# # mount with
# nfs_mount -o sec=krb5,rw 'K' nfs://10.49.202.233//nfsdata
# --- snip ---
#
#

export PATH='/usr/bin:/bin:/sbin'

builtin mkdir
#builtin rm

set -o xtrace
set -o nounset
set -o errexit

kdctestdir='/tmp/kdctest1'
compound config=(
	hostname="$(hostname --fqdn)"
	kdcport=88
	kadmindport=749
	# nfsdomain must be LOWERCASE!
	nfsdomain='nfschicken.test'
	# realmname must be UPPERCASE!
	realmname='NFSCHICKEN.TEST'
)


rm -Rfv -- "$kdctestdir"
rm -Rfv "/tmp/krb5cc_dir_$(id -u)"
mkdir -p -- "$kdctestdir"


export KRB5_KDC_PROFILE="${kdctestdir}/kdc.conf"
export KRB5_CONFIG="${kdctestdir}/krb5.conf"

if [[ ! -d '/nfsdata' ]] ; then
	mkdir /nfsdata
	chmod a+rwxt /nfsdata

	printf '/nfsdata\tgss/krb5(rw,no_subtree_check) gss/krb5i(rw,no_subtree_check) gss/krb5p(rw,no_subtree_check)\n' >>'/etc/exports'
fi


printf 'NEED_SVCGSSD="yes"\n' >>/etc/default/nfs-kernel-server

cat >'/etc/idmapd.conf' <<EOF
# Verbosity = 8 logs all idmapper lookups
Verbosity = 8
Pipefs-Directory = /run/rpc_pipefs
# set your own domain here, if it differs from FQDN minus hostname
# Domain = localdomain
# Value for "Domain" must be lowercase, value for "Local-Realms" uppercase
Domain = ${config.nfsdomain}
Local-Realms = ${config.realmname}

[Mapping]
Nobody-User = nobody
Nobody-Group = nogroup
EOF

cat >"${KRB5_CONFIG}" <<EOF
[libdefaults]
    default_realm = ${config.realmname}
    default_ccache_name = DIR:/tmp/krb5cc_dir_%{uid}

[realms]
    ${config.realmname} = {
        kdc = ${config.hostname}:${config.kdcport}
        admin_server = ${config.hostname}:${config.kadmindport}
    }
EOF


cat >"${KRB5_KDC_PROFILE}" <<EOF
[kdcdefaults]
    kdc_ports = ${config.kdcport}
    kdc_tcp_ports = ${config.kdcport}

[realms]
    ${config.realmname} = {
	kadmind_port = ${config.kadmindport}
	acl_file = ${kdctestdir}/kadm5.acl
	admin_keytab = ${kdctestdir}/kadm5.keytab
	database_name = ${kdctestdir}/principal
	key_stash_file = ${kdctestdir}/.k5.${config.realmname}

	max_life = 12h 0m 0s
	max_renewable_life = 7d 0h 0m 0s
	master_key_type = aes256-cts-hmac-sha1-96
	supported_enctypes = aes256-cts-hmac-sha1-96:normal aes128-cts-hmac-sha1-96:normal arcfour-hmac:normal
    }

[logging]
    kdc = FILE:${kdctestdir}/kdc.log
    admin_server = FILE:${kdctestdir}/kadmin.log
    default = FILE:${kdctestdir}/default.log

EOF

{
	printf '%s\n' 'myhorriblepassword12'
	printf '%s\n' 'myhorriblepassword12'
} | kdb5_util create -r "${config.realmname}" -s



#
# add principals
#
compound -A principal_list=(
	# add admin user
	['admin']=(
		principal="admin/admin@${config.realmname}"
		password='myhorriblepassword12'
	)

	# add plain (Windows) user
	['user1']=(
		principal="rmainz@${config.realmname}"
		password='myhorriblepassword12'
	)

	# add Linux host
	['linuxhost1']=(
		principal="host/debnfskrb5001@${config.realmname}"
		password='myhorriblepassword12'
	)
	['linuxhost1_fqdn']=(
		principal="host/debnfskrb5001.nfschicken.test@${config.realmname}"
		password='myhorriblepassword12'
	)

	# add NFS service on Linux host
	['linuxhost1_nfs_service']=(
		principal="nfs/debnfskrb5001@${config.realmname}"
		password='myhorriblepassword12'
	)
	['linuxhost1_nfs_service_fqdn']=(
		principal="nfs/debnfskrb5001.nfschicken.test@${config.realmname}"
		password='myhorriblepassword12'
	)

	# add Windows machine
	['win1']=(
		principal="host/wingrendel02@${config.realmname}"
		password='myhorriblepassword12'
	)
	['win1_fqdn']=(
		principal="host/wingrendel02.nfschicken.test@${config.realmname}"
		password='myhorriblepassword12'
	)
)

for pi in "${!principal_list[@]}" ; do
	nameref pie="principal_list[$pi]"

	{
		printf "addprinc %s\n" "${pie.principal}"
		printf '%s\n' "${pie.password}"
		printf '%s\n' "${pie.password}"
	} | kadmin.local
done

#
# create /etc/krb5.keytab for NFS server
#
rm -f /tmp/nfs01.keytab
{
	printf 'ktadd -k /tmp/nfs01.keytab nfs/debnfskrb5001.nfschicken.test@NFSCHICKEN.TEST\n'
} | kadmin.local
mv -f /tmp/nfs01.keytab /etc/krb5.keytab

#
# start KDC
#
krb5kdc -n &
(( kdc_pid=$! ))

# wait for KDC to start
sleep 10

#
# simple function test
#
{
	printf '%s\n' 'myhorriblepassword12'
} | kinit "admin/admin@${config.realmname}"
{
	printf '%s\n' 'myhorriblepassword12'
} | kinit "rmainz@${config.realmname}"

klist -A

#
# restart NFS server to pickup changes in /etc/exports and KRB5 changes
#
systemctl restart nfs-idmapd.service
sleep 5
systemctl restart nfs-kernel-server

#
# sleep for two weeks
#
sleep $((60*60*24*7*2))

kill $kdc_pid
wait $kdc_pid

# EOF.

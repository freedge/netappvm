random notes to build a lab with Netapp Ontap

we forget about active directory, but can have NFS, CIFS, S3 working.
- we will need a SSL cert for S3
```
openssl req -x509 -days 3650 -newkey rsa:4096 -keyout ca_private_key.pem -out ca_cert.pem -nodes -subj "/CN=testca"

openssl req -new -newkey rsa:4096 -sha256 -nodes \
  -keyout example.key -out example.csr -subj "/CN=test1" \
  -reqexts SAN \
  -config <(cat /etc/ssl/openssl.cnf \
        <(printf "\n[SAN]\nsubjectAltName=DNS:s3,DNS:s3.example.test,DNS:test1,DNS:test1.example.test")) 

openssl x509 -extfile <(printf "subjectAltName=DNS:s3,DNS:s3.example.test,DNS:test1,DNS:test1.example.test") -req -in example.csr -days 365 -CA ca_cert.pem -CAkey ca_private_key.pem -CAcreateserial -out my_signed_cert.pem
```
- also need a host_vars/nasim01a.yaml file with a ```licenses``` list and a ```netapp_password``` string

- boot VM with run.sh
- connect to the web server... choose single node
- wait some time, validate and wait some more time...


- build an a venv with the needed modules and collections, install with
```
ansible-playbook  install.yaml  -e ansible_python_interpreter=`pwd`/myenv/bin/python
```

- to activate Auditing, the root aggregate needs more disks
```
aggr add-disks -aggregate aggr0_test1_01 -diskcount 3
```

- NFS mount for example with
```
mount 10.224.123.7:/myvol /mnt/nfs/ -t nfs -o sec=sys,nfsvers=3,noac,noexec,nodev,nosuid
```

- CIFS mount on smb://10.224.123.7/myshare with user TEST1\tata, domain workgroup1

- S3 service 

NAS buckets are not doable with Ansible: https://github.com/ansible-collections/netapp.ontap/issues/153
```
vserver object-store-server bucket create -type nas -vserver vs -bucket mybucket -nas-path /myvol
vserver name-mapping create -position 1 -direction s3-unix -vserver vs -pattern user -replacement me
vserver name-mapping create -position 1 -direction s3-win -vserver vs -pattern user -replacement TEST1\\tata
```

```
curl --cacert ca_cert.pem --resolve s3.example.test:443:10.224.123.8 https://s3.example.test/
```

presigned URL require signature V4 (https://community.netapp.com/t5/ONTAP-Discussions/S3-buckets-and-presigned-URLs/m-p/443294#M42029)
ETAG do not match the file MD5 and If-Modified-Since is not supported. Connection will be resetted if file content changes.
Symlink or path to .snapshot are supported.



Random FreeBSD / Netapp stuff

after booting up the VM following a hard shutdown:

(from [doc](https://kb.netapp.com/onprem/ontap/Hardware/System_doesn't_start_after_reboot_due_to_%22Unable_to_recover_the_local_database_of_Data_Replication_Module%22))
```
system configuration recovery node mroot-state clear -recovery-state  all
```
and reboot from the hypervisor.

After VM pause, NTP synchro need to be forced:
```
set -privilege diagnostic
cluster date show
cluster time-service ntp status show
cluster time-service ntp server delete -server 192.168.1.254
cluster time-service ntp server create -server 192.168.1.254 -is-preferred true
```


```
network interface show
security login unlock -username diag
security login password -username diag
set -privilege diagnostic

# getting some more logs
debug sktrace tracepoint show
debug sktrace tracepoint modify -module HTTP_PARSER -node test1-01 -level * -enabled true
debug sktrace tracepoint modify -module S3_AUTH -node test1-01 -level * -enabled true
debug sktrace tracepoint modify -module HTTP_AUTH -node test1-01 -level * -enabled true

systemshell
cd /mroot/etc/log/mlog/
tail -f sktrace.log

jls # listing jails
sudo jexec 1 csh

netstat -a | grep https
sockstat
sudo fstat mgwd.log # lsof equivalent
kldstat # lsmod

```

# kerberos stuff

need a kerberos server:
```
podman run --rm --name krb5-server -e KRB5_REALM=EXAMPLE.TEST -e KRB5_KDC=localhost -e KRB5_PASS=mypass -p 10088:88 -p 10464:464 -p 10749:749 gcavalcante8808/krb5-server
```

we add some principals:
```
KRB5_CONFIG=krb5.conf kinit admin/admin@EXAMPLE.TEST
KRB5_CONFIG=krb5.conf kadmin
add_principal host/raw.example.test@EXAMPLE.TEST
add_principal host/gw.example.test@EXAMPLE.TEST
add_principal host/nfs.example.test@EXAMPLE.TEST
add_principal nfs/nfs.example.test@EXAMPLE.TEST
add_principal vagrant@EXAMPLE.TEST
add_principal nfs/service@EXAMPLE.TEST

ktadd -k raw.keytab host/raw.example.test@EXAMPLE.TEST
ktadd -k gw.keytab host/gw.example.test@EXAMPLE.TEST
```

we configure Ontap for Kerberos
```
ansible-playbook  krb5.yaml  -e ansible_python_interpreter=`pwd`/myenv/bin/python
```

TODO: doable with Ansible?

```
vserver nfs kerberos interface modify -vserver vs -lif lif1.0 -kerberos enabled -spn nfs/nfs.example.test@EXAMPLE.TEST -admin-username nfs/service
```

TODO: configure custom location for these files and try on Ubuntu

On the server we prepare a /etc/krb5.conf and /etc/krb5.keytab, then
mount with
```
mount 10.224.123.7:/myvol /mnt/nfs/ -t nfs -o sec=krb5p,nfsvers=4.2,noac,noexec,nodev,nosuid -vv
```


random notes to build a lab with Netapp Ontap

we forget about krb and active directory, but can have NFS, CIFS, S3 working.
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

- log on SSH and run that
```
security login create -vserver test1 -user-or-group-name admin -application ssh -authentication-method publickey -role admin
set -confirmations off
disk assign -all -node test1-01
# need to wait a bit after that one...
aggr add-disks -aggregate aggr0_test1_01 -diskcount 3
set -privilege advanced
security login unlock -username diag
security login password -username diag
```

- build an a venv with the needed modules and collections, install with
```
ansible-playbook  install.yaml  -e ansible_python_interpreter=`pwd`/myenv/bin/python
```


- NFS mount with
```
mount 10.224.123.7:/myvol /mnt/nfs3/ -t nfs -o sec=sys,nfsvers=3,noac,noexec
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



Random FreeBSD / Netapp stuff

after booting up the VM following a hard shutdown:

(from [doc](https://kb.netapp.com/onprem/ontap/Hardware/System_doesn't_start_after_reboot_due_to_%22Unable_to_recover_the_local_database_of_Data_Replication_Module%22))
```
system configuration recovery node mroot-state clear -recovery-state  all
```
and reboot.


```
network interface show
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

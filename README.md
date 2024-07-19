random notes to build a lab with Netapp Ontap

we forget about active directory, but can have NFS, CIFS, S3 working.
- we will need a SSL cert for S3
```
openssl req -x509 -days 3650 -newkey rsa:4096 -keyout ca_private_key.pem -out ca_cert.pem -nodes -subj "/CN=testca"

openssl req -new -newkey rsa:4096 -sha256 -nodes \
  -keyout example.key -out example.csr -subj "/CN=test1" \
  -reqexts SAN \
  -config <(cat /etc/ssl/openssl.cnf \
        <(printf "\n[SAN]\nsubjectAltName=DNS:s3.example.test,DNS:localhost,DNS:test1.example.test"))

openssl x509 -extfile <(printf "subjectAltName=DNS:s3.example.test,DNS:test1.example.test,DNS:localhost") -req -in example.csr -days 365 -CA ca_cert.pem -CAkey ca_private_key.pem -CAcreateserial -out my_signed_cert.pem
```

with TPM: key needs to be shorter
```
sudo apt-get install tpm2-openssl

openssl req -provider tpm2 -provider default -x509 -days 3650 -newkey rsa:2048 -keyout ca_private_key.pem -out ca_cert.pem -nodes -subj "/CN=testca"

openssl req -new -newkey rsa:2048 -sha256 -nodes \
  -keyout example.key -out example.csr -subj "/CN=test1" \
  -reqexts SAN \
  -config <(cat /etc/ssl/openssl.cnf \
        <(printf "\n[SAN]\nsubjectAltName=DNS:s3.example.test,DNS:test1.example.test")) 

openssl x509 -extfile <(printf "subjectAltName=DNS:s3.example.test,DNS:test1.example.test") -req -in example.csr -days 365 -CA ca_cert.pem -CAkey ca_private_key.pem -CAcreateserial -out my_signed_cert.pem

```

with TPM: but on Fedora, and with ecc
```
dnf install tpm2-openssl
openssl ecparam -provider tpm2 -propquery provider=tpm2 -name prime256v1 -genkey -noout -out ca_private_key.pem
openssl req -provider tpm2 -provider default -x509 -days 3650 -key ca_private_key.pem -out ca_cert.pem -nodes -subj "/CN=testca"
openssl req -new -newkey ec:<(openssl ecparam -name secp384r1) -sha256 -nodes \
  -keyout example.key -out example.csr -subj "/CN=test1" \
  -reqexts SAN \
  -config <(cat /etc/ssl/openssl.cnf \
        <(printf "\n[SAN]\nsubjectAltName=DNS:s3.example.test,DNS:test1.example.test"))
openssl x509 -provider tpm2 -extfile <(printf "subjectAltName=DNS:s3.example.test,DNS:test1.example.test") -req -in example.csr -days 365 -CA ca_cert.pem -CAkey ca_private_key.pem -CAcreateserial -out my_signed_cert.pem

```

with name constraint:
```
openssl genrsa -out ca_private_key.pem 4096 && openssl req -new -key ca_private_key.pem -extensions v3_ca -batch -out ca.csr -utf8 -subj '/CN=testca'
openssl x509 -req -sha256 -days 3650 -in ca.csr -signkey ca_private_key.pem -extfile <(cat << EOF
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
nameConstraints = critical, permitted;DNS:.example.test, permitted;DNS:localhost
EOF
) -out ca_cert.pem
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

- [x] NAS buckets are not doable with Ansible: https://github.com/ansible-collections/netapp.ontap/issues/153

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

```
source user.env
aws s3 --endpoint-url=https://s3.example.test/ ls s3://myvol/
```



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


sqlite3 -json /mroot/etc/cluster_config/rdb/Management/_sql/rdb.db "select * from nfs_Servers;"

```

# kerberos stuff

need a kerberos server:
```
podman run --rm --name krb5-server -e KRB5_REALM=EXAMPLE.TEST -e KRB5_KDC=localhost -e KRB5_PASS=mypass -p 10088:88 -p 10464:464 -p 10749:749 gcavalcante8808/krb5-server
```

we add some principals:
```
rm -f raw.keytab gw.keytab vagrant.keytab
alias ka="KRB5_CONFIG=krb5.conf kadmin -w mypass -p admin/admin@EXAMPLE.TEST"
ka add_principal -pw mypass host/raw.example.test@EXAMPLE.TEST
ka add_principal -pw mypass host/gw.example.test@EXAMPLE.TEST
ka add_principal -pw mypass host/nfs.example.test@EXAMPLE.TEST
ka add_principal -pw mypass nfs/nfs.example.test@EXAMPLE.TEST
ka add_principal -pw mypass vagrant@EXAMPLE.TEST
ka add_principal -pw mypass nfs/service@EXAMPLE.TEST
ka ktadd -k raw.keytab host/raw.example.test@EXAMPLE.TEST
ka ktadd -k gw.keytab host/gw.example.test@EXAMPLE.TEST
ka ktadd -k vagrant.keytab vagrant@EXAMPLE.TEST
```

we configure Ontap for Kerberos
```
ansible-playbook  krb5.yaml  -e ansible_python_interpreter=`pwd`/myenv/bin/python
```

following line is now done with Ansible (netapp.ontap 22.6.0)

```
vserver nfs kerberos interface modify -vserver vs -lif lif1.0 -kerberos enabled -spn nfs/nfs.example.test@EXAMPLE.TEST -admin-username nfs/service
```

On the server we prepare the needed config, then mount:
```
ansible-playbook nfsclient.yaml
mount nfs.example.test:/myvol /mnt/nfs/ -t nfs -o noexec,nodev,nosuid
```

more:
```
diag nblade nfs kerberos-context-cache show
```

Connecting and forwarding the kerberos ticket
```
KRB5_CONFIG=krb5.conf kinit -k -t ./vagrant.keytab  vagrant@EXAMPLE.TEST
KRB5_CONFIG=krb5.conf ssh -K -o PreferredAuthentications=gssapi-with-mic vagrant@raw.example.test
```

We use [gssproxy](https://github.com/gssapi/gssproxy/blob/main/docs/NFS.md)

```
kerberos-context-cache clear-all
```

About gssproxy:
- https://bugzilla.redhat.com/show_bug.cgi?id=2188797
- https://github.com/gssapi/gssproxy/issues/75

# NFSv4 and ids


```
test1::> vserver nfs modify -vserver vs -v4-numeric-ids disabled

test1::> vserver security file-directory show -vserver vs -path /myvol/fff

                Vserver: vs
              File Path: /myvol/fff
      File Inode Number: 108
         Security Style: ntfs
        Effective Style: ntfs
         DOS Attributes: 20
 DOS Attributes in Text: ---A----
Expanded Dos Attributes: -
           UNIX User Id: 1000
          UNIX Group Id: 1000
         UNIX Mode Bits: 777
 UNIX Mode Bits in Text: rwxrwxrwx
                   ACLs: NTFS Security Descriptor
                         Control:0x8004
                         Owner:TEST1\tata
                         Group:TEST1\None
                         DACL - ACEs
                           ALLOW-Everyone-0x1f01ff-(Inherited)
```

This works in ```/etc/idmapd.conf```

```
[Static]

vagrant@EXAMPLE.TEST = mylocaluser

[Translation]
Method = static
```

# trident

[gh](https://github.com/NetApp/trident)

[dockerhub](https://hub.docker.com/r/netapp/trident-operator/tags)

[manual deployment](https://docs.netapp.com/us-en/trident/trident-get-started/kubernetes-deploy-operator.html#critical-information-about-astra-trident-23-01)
check for a release where image version exists.

in Kind:

```
curl -L https://raw.githubusercontent.com/NetApp/trident/master/deploy/namespace.yaml | kubectl apply -f -
curl -L https://raw.githubusercontent.com/NetApp/trident/stable/v23.01/deploy/bundle_post_1_25.yaml | kubectl apply -f -
curl -L https://raw.githubusercontent.com/NetApp/trident/v23.01.1/deploy/crds/tridentorchestrator_cr.yaml | kubectl apply -f -
```

there is a ```tridentctl``` utility in the release.
```
[vagrant@raw ~]$ kubectl get pod -n trident 
NAME                                  READY   STATUS    RESTARTS   AGE
trident-controller-77f66f4848-pthhh   6/6     Running   0          4m41s
trident-node-linux-7xqc9              2/2     Running   0          4m41s
trident-node-linux-8g527              2/2     Running   0          4m41s
trident-node-linux-8hmml              2/2     Running   0          4m41s
trident-operator-86696fb84f-dzf7b     1/1     Running   0          18m
[vagrant@raw ~]$ trident-installer/tridentctl -n trident version
+----------------+----------------+
| SERVER VERSION | CLIENT VERSION |
+----------------+----------------+
| 23.01.1        | 23.01.1        |
+----------------+----------------+
```

Creating backend as per [sample](https://github.com/NetApp/trident/blob/v23.01.1/trident-installer/sample-input/backends-samples/ontap-nas/backend-ontap-nas.json)
storage class, pvc, pod as [documented](https://docs.netapp.com/us-en/trident/trident-get-started/kubernetes-postdeployment.html#step-4-mount-the-volumes-in-a-pod)

```
test1::> volume show -vserver vs -volume trident_pvc_a81edc1f_3c77_4714_9de7_9841ed1bc5c7
                                                                                                                  
                                      Vserver Name: vs                         
                                       Volume Name: trident_pvc_a81edc1f_3c77_4714_9de7_9841ed1bc5c7
                                    Aggregate Name: aggr1
     List of Aggregates for FlexGroup Constituents: aggr1
                                   Encryption Type: none 
                  List of Nodes Hosting the Volume: test1-01
                                       Volume Size: 60MB
                                Volume Data Set ID: 1027
                         Volume Master Data Set ID: 2159746539
                                      Volume State: online  
                                      Volume Style: flex     
                             Extended Volume Style: flexvol
                           FlexCache Endpoint Type: none
                            Is Cluster-Mode Volume: true
                             Is Constituent Volume: false
                     Number of Constituent Volumes: -  
                                     Export Policy: default
                                           User ID: 0
                                          Group ID: 0    
                                    Security Style: unix 
                                  UNIX Permissions: ---rwxrwxrwx
                                     Junction Path: /trident_pvc_a81edc1f_3c77_4714_9de7_9841ed1bc5c7
                              Junction Path Source: RW_volume
                                   Junction Active: true 
```
from within the node
```
root@ovn-worker:/# mount | grep nfs
10.224.123.7:/trident_pvc_a81edc1f_3c77_4714_9de7_9841ed1bc5c7 on /var/lib/kubelet/pods/c8558149-3720-4726-ba94-cd4c6c5e121c/volumes/kubernetes.io~csi/pvc-a81edc1f-3c77-4714-9de7-9841ed1bc5c7/mount type nfs4 (rw,relatime,vers=4.2,rsize=65536,wsize=65536,namlen=255,hard,proto=tcp,timeo=600,retrans=2,sec=null,clientaddr=10.89.0.4,local_lock=none,addr=10.224.123.7)
```

volume can be customized with [annotations](https://netapp-trident.readthedocs.io/en/stable-v21.07/kubernetes/concepts/objects.html?highlight=trident.netapp.io%2FunixPermissions#kubernetes-persistentvolumeclaim-objects)

I don't see how to encrypt traffic.
Also, krb5p [not supported](https://access.redhat.com/solutions/6132061) in OpenShift

Importing out existing volume from above
```
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: imported
  namespace: frigo
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: imported
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: imported
provisioner: csi.trident.netapp.io
parameters:
  backendType: "ontap-nas"
reclaimPolicy: Retain
```

```
[vagrant@raw ~]$ trident-installer/tridentctl  import volume customBackendName vol1 -f pvcimport.yaml --no-manage -n trident
+------------------------------------------+--------+---------------+----------+--------------------------------------+--------+---------+
|                   NAME                   |  SIZE  | STORAGE CLASS | PROTOCOL |             BACKEND UUID             | STATE  | MANAGED |
+------------------------------------------+--------+---------------+----------+--------------------------------------+--------+---------+
| pvc-d1d404f9-d79e-4ea2-bbc4-93577ddb087c | 40 MiB | imported      | file     | 033c9716-cd8a-4158-9123-0d993623f616 | online | false   |
+------------------------------------------+--------+---------------+----------+--------------------------------------+--------+---------+
```

to use krb5p, we need to add config for krb5.conf and nfs.conf, add the keytab on the host.

- [ ] TODO: some kind of machine config or controller for that?

```
sudo podman cp /etc/krb5.keytab ovn-worker:/etc/krb5.keytab
sudo podman exec -ti ovn-worker mkdir /etc/krb5.conf.d/
sudo podman cp /etc/krb5.conf.d/ontap.conf ovn-worker:/etc/krb5.conf.d/ontap.conf
sudo podman cp /etc/krb5.conf ovn-worker:/etc/krb5.conf
sudo podman cp /etc/nfs.conf.d/ontap.conf ovn-worker:/etc/nfs.conf.d/ontap.conf

apt-get update
apt-get install gssproxy

sudo podman cp /etc/gssproxy/99-network-fs-clients.conf ovn-worker:/etc/gssproxy/99-network-fs-clients.conf
sudo podman cp /var/lib/gssproxy/clients/1000.keytab ovn-worker:/var/lib/gssproxy/clients/100000.keytab
```


```
spec:
  securityContext:
    runAsUser: 100000
    runAsGroup: 100000
    supplementalGroups: [5555]
  volumes:
    - name: task-pv-storage
      persistentVolumeClaim:
        claimName: basic
```
we use keytab for uid=1000, run as user 100000, and files appear owned by 1000
which is great and weird.

```chgrp``` works assuming the group name is defined on both client and server side.

# more gssproxy

```
gssproxy -u -d -i -s /var/run/user/1000/user.socket
```

```
podman run --privileged \
  -v /var/run/user/1000/user.socket:/srv/user.socket \
  -e GSSPROXY_SOCKET=/srv/user.socket \
  -e GSS_USE_PROXY=yes \
  --rm -ti  --network=host ssh bash

ssh -K -o PreferredAuthentications=gssapi-with-mic vagrant@raw.example.test -vvv
```

to get rid of the ```--privileged```, we can generate a policy with Udica and augment it with
```
(block my_gssed
    (blockinherit container)

    (allow process ssh_port_t (tcp_socket (name_connect)))
    (allow process userdomain (unix_stream_socket (connectto)))
)
```

```
chcon system_u:object_r:container_file_t:s0:c42,c43 /var/run/user/1000/user.socket

podman run \
  --security-opt label=type:my_gssed.process \
  --security-opt label=level:s0:c42,c43 \
  -v /var/run/user/1000/user.socket:/srv/user.socket \
  ...
```

# CIFS

```
smbclient --use-kerberos=off -d 2 -W WORKGROUP1 -n TEST1 -U tata '\\10.224.123.7\myshare'

mount -t cifs //10.224.123.7/myshare /mnt/nfs2 -o workgroup=workgroup1,credentials=/etc/samba/samba.user,seal,vers=3,uid=1000,gid=1000
```

samba.user file looks like
```
username=tata
password=..
domain=WORKGROUP1
```

# links

[kerberos](https://www.netapp.com/media/19384-tr-4616.pdf)

[REST API](https://docs.netapp.com/us-en/ontap-automation/reference/api_reference.html#access-a-copy-of-the-ontap-rest-api-reference-documentation)

[NFS best practice](https://www.netapp.com/media/10720-tr-4067.pdf)

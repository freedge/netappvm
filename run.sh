setfacl -m u:libvirt-qemu:x .
virsh destroy nasim01a
virsh undefine nasim01a
sha256sum vsim-netapp-DOT9.12.1-cm_nodar.ova  | grep f499dfdebb73d30683ebd61cd15f3fa3c0e02d0efe1db18260fdf61ba8057c54 || exit 9
#sha256sum vsim-netapp-DOT9.11.1-cm_nodar.ova  | grep 55f07abf40493364f61bf89458c001efb7f52a44024d7ffd4719280367d92907 || exit 9
#md5sum vsim-netapp-DOT9.7-cm_nodar.ova | grep 083ba688315f4c6c802a769c121a7164 || exit 9
rm -f vsim-NetApp???-simulate-disk{1,2,3,4}.qcow2
tar xvf vsim-netapp-DOT9.12.1-cm_nodar.ova
for i in {1..4}; do     qemu-img convert -f vmdk -O qcow2 vsim-NetAppDOT-simulate-disk${i}.vmdk vsim-NetAppDOT-simulate-disk${i}.qcow2; done

virt-install --name nasim01a --memory 12288 --vcpus 2 --os-variant freebsd11.2 \
	--disk=vsim-NetAppDOT-simulate-disk{1..4}.qcow2,bus=ide --autostart --network network=br-vagrant,model=e1000,mac=02:18:A6:97:B3:A0 --network network=br-vagrant,model=e1000,mac=02:d6:ca:b8:90:ce --network network=br-vagrant,model=e1000,mac=02:0a:1f:e3:5f:ef --network network=br-vagrant,model=e1000,mac=02:c0:80:ec:5b:93 --autostart --vnc --virt-type kvm --machine pc --boot hd,network,menu=on --noautoconsole

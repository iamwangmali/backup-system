EXCLUDES="/dev /proc /sys"
#EXCLUDES="$EXCLUDES /tmp /run /var"
EXCLUDES="$EXCLUDES /cdrom /lost+found /mnt /media /opt"
EXCLUDES="$EXCLUDES /swapfile"
EXCLUDES="$EXCLUDES /home/* /root/*"

WORKDIR=/home/remastersys
DUMMYSYS=$WORKDIR/dummysys
ISODIR=$WORKDIR/isofiles
LIVECDLABEL="ubuntu-22.04"
CUSTOMISO="custom-ubuntu22.04.iso"

apt autoremove
apt autoclean
apt clean

rm -rf $WORKDIR/$CUSTOMISO
rm -rf $ISODIR/casper/filesystem.squashfs

mkdir -p $WORKDIR
mkdir -p $DUMMYSYS
mkdir -p $ISODIR


mkdir -p $ISODIR/{casper,install,preseed}


mkdir -p $DUMMYSYS/etc/casper        #check if necessary
#mkdir -p $DUMMYSYS/{dev,proc,sys}
mkdir -p $DUMMYSYS/{tmp,run,var}
mkdir -p $DUMMYSYS/{mnt,media}
chmod ug+rwx,o+rwt $DUMMYSYS/tmp

VAREXCLUDES=""
for addvar in $EXCLUDES ; do
	VAREXCLUDES="$VAREXCLUDES --exclude="$addvar" "
done


#rsync --exclude='*.log.*' --exclude='*.pid' --exclude='*.bak' --exclude='*.[0-9].gz' --exclude='*.deb' $VAREXCLUDES-a /var/. $DUMMYSYS/var/.

rsync -aAXv --exclude $WORKDIR $VAREXCLUDES / $DUMMYSYS/

rm -f $DUMMYSYS/etc/mtab
rm -f $DUMMYSYS/etc/fstab
rm -f $DUMMYSYS/etc/udev/rules.d/70-persistent*
ls $DUMMYSYS/var/lib/apt/lists | grep -v ".gpg" | grep -v "lock" | grep -v "partial" | grep -v "auxfiles" | xargs -i rm $DUMMYSYS/var/lib/apt/lists/{} ;  

mkdir -p $DUMMYSYS/{etc-backup,var-backup,tmp-backup,run-backup}
rsync -a /etc/. $DUMMYSYS/etc-backup/.
rsync -a /var/. $DUMMYSYS/var-backup/.
rsync -a /tmp/. $DUMMYSYS/tmp-backup/.
rsync -a /run/. $DUMMYSYS/run-backup/.
	
#rm -f $DUMMYSYS/etc/hostname

#if dist, we need LIVEUSER auto login

if [ -f util/preseed/*.seed ]; then
	cp util/preseed/* $ISODIR/preseed/
fi

chmod +x restore.sh
cp ./restore.sh $DUMMYSYS/sbin/

#################################finish sync files##############################

# bootloader localization 
TRYLIVECD="try or install ubuntu22.04"
LiveCDFailSafe="(fail safe)"
MemTestPlus="Memory Test (Memtest86+)"


cp /boot/memtest86+.bin $ISODIR/boot/

mkdir -p $ISODIR/boot/grub
#mkdir -p $ISODIR/usr/share/grub
cp -a /boot/grub/* $ISODIR/boot/grub/
#cp -a /usr/share/grub/* $ISODIR/usr/share/grub/

cp util/grub/grub.cfg $ISODIR/boot/grub/grub.cfg
cp util/grub/splash.png $ISODIR/boot/grub/grub.png

grubcfg="$ISODIR/boot/grub/grub.cfg"

# grub.cfg translation
sed -i -e 's/__LIVECDLABEL__/'"$TRYLIVECD"'/g' "$grubcfg"
sed -i -e 's/__LIVECDFAILSAFE__/'"$TRYLIVECD $LiveCDFailSafe"'/g' "$grubcfg"
sed -i -e 's/__MEMTESTPLUS__/'"$MemTestPlus"'/g' "$grubcfg"

if [ ! -d /etc/plymouth ]; then
	sed -i -e 's/splash//g' $ISODIR/boot/grub/grub.cfg
fi


#################################finish config grub ###############################

#if [ "$1" = "backup" ]; then
#    LIVEUSER="$(grep '^[^:]*:[^:]*:1000:' /etc/passwd | awk -F ":" '{ print $1 }')"
#    LIVEUSER_FULL_NAME="$(getent passwd $LIVEUSER | cut -d ':' -f 5 | cut -d ',' -f 1)"
#    #fix Thunar volmanrc for live
#    for i in $(ls -d /home/*); do
#        if [ -f "$i/.config/Thunar/volmanrc" ]; then
#            sed -i -e 's/TRUE/FALSE/g' $i/.config/Thunar/volmanrc
#            cp -f $i/.config/volmanrc /root/.config/Thunar/volmanrc
#        fi
#    done
#fi



	#if [ ! -d /etc/live ]; then
	#	mkdir -p /etc/live
	#fi                         

    #echo "export LIVE_USERNAME=\"$LIVEUSER\"" > /etc/live/config.conf
    #echo "export LIVE_USER_FULLNAME=\"$LIVEUSER_FULL_NAME\"" >> /etc/live/config.conf
    #echo "export LIVE_HOSTNAME=\"$LIVEUSER\"" >> /etc/live/config.conf
    #echo "export LIVE_USER_DEFAULT_GROUPS=\"audio,cdrom,dialout,floppy,video,plugdev,netdev,powerdev,adm,sudo\"" >> /etc/live/config.conf
    #lang=$(locale | grep -w 'LANG' | cut -d= -f2) # like "pt_BR.UTF-8"
    #echo "export LIVE_LOCALES=\"$lang\"" >> /etc/live/config.conf
    #timezone=$(cat /etc/timezone) # like "America/Sao_Paulo"     
    #echo "export LIVE_TIMEZONE=\"$timezone\"" >> /etc/live/config.conf

    #echo "export LIVE_NOCONFIGS=\"user-setup,sudo,locales,locales-all,tzdata,gdm,gdm3,kdm,lightdm,lxdm,nodm,slim,xinit,keyboard-configuration,gnome-panel-data,gnome-power-manager,gnome-screensaver,kde-services,debian-installer-launcher,login\"" >> /etc/live/config.conf                                                                                                                                                                                                                                                                                                                                                        

    #fix for a bug in the debian live boot scripts that starts a second X server                                                                                                      
    #if [ "$1" = "dist" ] && [ -f /etc/X11/default-display-manager ]; then                                                                                                             
    #    echo "export LIVE_NOCONFIGS=\"xinit\"" >> /etc/live/config.conf                                                                                                               
    #fi                                                                                                                                                                                
                                                                                                                                                                                 
    #cp /etc/live/config.conf $DUMMYSYS/etc/live/
	
	
	
	
#cat /etc/casper.conf
echo "export USERNAME=\"ubuntu\"" > $DUMMYSYS/etc/casper.conf
echo "export USERFULLNAME=\"Live session user\"" >> $DUMMYSYS/etc/casper.conf
echo "export HOST=\"ubuntu\"" >> $DUMMYSYS/etc/casper.conf
echo "export BUILD_SYSTEM=\"Ubuntu\"" >> $DUMMYSYS/etc/casper.conf

	


cp /boot/vmlinuz-$(uname -r) $ISODIR/casper/vmlinuz
cp /boot/initrd.img-$(uname -r) $ISODIR/casper/initrd.img


REALFOLDERS=""
for d in $(ls -d $DUMMYSYS/*); do
	REALFOLDERS="$REALFOLDERS $d"
done

SQUASHFSOPTS="-no-recovery -always-use-fragments -b 1M -comp zstd"

if true; then
	time mksquashfs $REALFOLDERS $ISODIR/casper/filesystem.squashfs -comp zstd
else
	time mksquashfs $REALFOLDERS $ISODIR/casper/filesystem.squashfs $SQUASHFSOPTS -e \
		root/.thumbnails \
		root/.cache \
		root/.bash_history \
		root/.lesshst \
		root/.nano_history \
		boot/grub \
		$WORKDIR $EXCLUDES 2>>$WORKDIR/remastersys.log
fi


#return Thunar volmanrc back to normal
#for i in $(ls -d /home/*); do
#	if [ -f "$i/.config/Thunar/volmanrc" ]; then
#		sed -i -e 's/FALSE/TRUE/g' $i/.config/Thunar/volmanrc
#		cp -f $i/.config/volmanrc /root/.config/Thunar/volmanrc
#	fi
#done
OLD_DIR=$(pwd)
cd $ISODIR
rm md5sum.txt
find ./ -type f -print0 | xargs -0 md5sum | tee md5sum.txt
cd $OLD_DIR


grub-mkrescue \
	-o $WORKDIR/$CUSTOMISO "$ISODIR" -- \
		-x -rockridge on -find / -exec mkisofs_r -- \
			-volid "$LIVECDLABEL" -for_backup -joliet on \
			-compliance "iso_9660_level=3:deep_paths:long_paths:long_names" \
			-file_size_limit off -- \
				-outdev $WORKDIR/$CUSTOMISO -blank as_needed \
				-map $ISODIR / 2>>$WORKDIR/remastersys.log 1>>$WORKDIR/remastersys.log

md5sum $WORKDIR/$CUSTOMISO > $WORKDIR/$CUSTOMISO.md5
	

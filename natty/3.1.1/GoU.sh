#!/bin/bash
GF_CREATEUSER=1
GF_USER=glassfish
GF_USERHOME=/home/glassfish
GF_ASADMIN=$GF_USERHOME/bin/asadmin

GF_CREATEADMGROUP=1
GF_ADMGROUP=glassfishadm

GF_NOOPENJDK=1
GF_INSTALLJDK=1

GF_MPWD="master-password"
CERT_CN="CN"
CERT_O="organization"
CERT_L="city"
CERT_S="region"
CERT_C="country"

function createUser {
	if [ "$GF_CREATEUSER" = "1" ]; then 
		if [ "$(grep "^$GF_USER:" /etc/passwd|wc -l)" = "0" ]; then 
			adduser --home "$GF_USERHOME" --system --shell /bin/bash "$GF_USER"
		fi
	fi
}

function createGroup {
	if [ "$GF_CREATEADMGROUP" = "1" ]; then 
		if [ "$(grep "^$GF_ADMGROUP" /etc/group|wc -l)" = "0" ]; then 
			groupadd "$GF_ADMGROUP"
			usermod -a -G "$GF_ADMGROUP" "$GF_USER"
		fi
	fi
}

function configureOracleJava {
	if [ "$GF_NOOPENJDK" = "1" ]; then 
		apt-get remove openjdk-6-jre openjdk-6-jdk
	fi

	if [ "$GF_INSTALLJDK" = "1" ]; then 
		apt-get install python-software-properties
		add-apt-repository --remove "deb http://archive.canonical.com/ natty partner"
		add-apt-repository "deb http://archive.canonical.com/ natty partner"
		apt-get update
		apt-get install sun-java6-jdk  sun-java6-jre
		apt-get autoremove
		update-alternatives --config java
		cd /etc/alternatives
		ls -lrt java*
	fi
	 
	echo "JAVA_HOME=/usr/lib/jvm/java-6-sun" >> /etc/environment
	echo "AS_JAVA=/usr/lib/jvm/java-6-sun" >> /etc/environment
}

function getGlassfish {
	mkdir -p $GF_USERHOME/downloads
	cd $GF_USERHOME/downloads
	wget http://download.java.net/glassfish/3.1.1/release/glassfish-3.1.1.zip
	unzip glassfish-3.1.1.zip
	mv $GF_USERHOME/downloads/glassfish3/* $GF_USERHOME/
}

function prepareGlassfish {
	apt-get install unzip
	sudo su -c "$0 gg" glassfish

	chgrp -R glassfishadm "$GF_USERHOME"
	chown -R glassfish "$GF_USERHOME"
 
	chmod -R ug+rwx $GF_USERHOME/bin/
	chmod -R ug+rwx $GF_USERHOME/glassfish/bin/
	chmod -R o-rwx $GF_USERHOME/bin/
	chmod -R o-rwx $GF_USERHOME/glassfish/bin/

	su -c "$GF_ASADMIN start-domain domain1;$GF_ASADMIN stop-domain domain1" glassfish

	exec 3>&1
	
	echo "#! /bin/sh" > /etc/init.d/glassfish
	exec 1>> /etc/init.d/glassfish
	echo ""
	echo "export AS_JAVA=/usr/lib/jvm/java-6-sun"
	echo ""
	echo "GLASSFISHPATH=$GF_USERHOME/bin"
	echo "case \"\$1\" in"
	echo "start)"
	echo "echo \"starting glassfish from \$GLASSFISHPATH\""
	echo "sudo -u glassfish \$GLASSFISHPATH/asadmin start-domain domain1"
	echo ";;"
	echo "restart)"
	echo "\$0 stop"
	echo "\$0 start"
	echo ";;"
	echo "stop)"
	echo "echo \"stopping glassfish from \$GLASSFISHPATH\""
	echo "sudo -u glassfish \$GLASSFISHPATH/asadmin stop-domain domain1"
	echo ";;"
	echo "*)"
	echo "echo \$\"usage: \$0 {start|stop|restart}\""
	echo "exit 3"
	echo ";;"
	echo "esac"
	echo ""

	exec 1>&3
	exec 3>&-
	
	chmod a+x /etc/init.d/glassfish
	update-rc.d glassfish defaults
	/etc/init.d/apache2 stop
	update-rc.d -f apache2 remove
}

function configureGlassfish {

	$GF_ASADMIN change-master-password --savemasterpassword=true
	$GF_ASADMIN start-domain domain1 
	$GF_ASADMIN change-admin-password 
	$GF_ASADMIN login
	$GF_ASADMIN stop-domain domain1

	cd $GF_USERHOME/glassfish/domains/domain1/config/
	keytool -list -keystore keystore.jks -storepass $GF_MPWD
	keytool -delete -alias s1as -keystore keystore.jks -storepass $GF_MPWD
	keytool -delete -alias glassfish-instance -keystore keystore.jks -storepass $GF_MPWD
	keytool -keysize 2048 -genkey -alias myAlias -keyalg RSA -dname "CN=$CERT_CN,O=$CERT_O,L=$CERT_L,S=$CERT_S,C=$CERT_C" -validity 3650 -keypass $GF_MPWD -storepass $GF_MPWD -keystore keystore.jks
	keytool -keysize 2048 -genkey -alias s1as -keyalg RSA -dname "CN=$CERT_CN,O=$CERT_O,L=$CERT_L,S=$CERT_S,C=$CERT_C" -validity 3650 -keypass $GF_MPWD -storepass $GF_MPWD -keystore keystore.jks
	keytool -keysize 2048 -genkey -alias glassfish-instance -keyalg RSA -dname "CN=$CERT_CN,O=$CERT_O,L=$CERT_L,S=$CERT_S,C=$CERT_C" -validity 3650 -keypass $GF_MPWD -storepass $GF_MPWD -keystore keystore.jks
	keytool -list -keystore keystore.jks -storepass $GF_MPWD

	keytool -export -alias glassfish-instance -file glassfish-instance.cert -keystore keystore.jks -storepass $GF_MPWD
	keytool -export -alias s1as -file s1as.cert -keystore keystore.jks -storepass $GF_MPWD

	keytool -delete -alias glassfish-instance -keystore cacerts.jks -storepass $GF_MPWD
	keytool -delete -alias s1as -keystore cacerts.jks -storepass $GF_MPWD

	keytool -import -alias s1as -file s1as.cert -keystore cacerts.jks -storepass $GF_MPWD
	keytool -import -alias glassfish-instance -file glassfish-instance.cert -keystore cacerts.jks -storepass $GF_MPWD

	$GF_ASADMIN start-domain domain1

	$GF_ASADMIN set server-config.network-config.protocols.protocol.admin-listener.security-enabled=true
	$GF_ASADMIN enable-secure-admin
	$GF_ASADMIN list-jvm-options
	$GF_ASADMIN delete-jvm-options -- -client
	$GF_ASADMIN create-jvm-options -- -server
	$GF_ASADMIN delete-jvm-options -- -Xmx512m
	$GF_ASADMIN create-jvm-options -- -Xmx2048m
	$GF_ASADMIN create-jvm-options -- -Xms1024m
	$GF_ASADMIN create-jvm-options -Dproduct.name=""
	$GF_ASADMIN stop-domain domain1
	$GF_ASADMIN start-domain domain1
	$GF_ASADMIN list-jvm-options

	$GF_ASADMIN set server.network-config.protocols.protocol.http-listener-1.http.xpowered-by=false
	$GF_ASADMIN set server.network-config.protocols.protocol.http-listener-2.http.xpowered-by=false
	$GF_ASADMIN set server.network-config.protocols.protocol.admin-listener.http.xpowered-by=false

}

case "$1" in
cu)
	createUser
	;;

cg)
	createGroup
	;;
	
coj)
	configureOracleJava
	;;

gg)
	getGlassfish
	;;
	
pg)
	prepareGlassfish
	;;
	
cfg)
	configureGlassfish
	;;
	
*)
	sudo $0 cu
	sudo $0 cg
	sudo $0 coj
	sudo $0 pg
	sudo su -c "$0 cfg" glassfish
	sudo /etc/init.d/glassfish restart
	;;
esac

exit 0
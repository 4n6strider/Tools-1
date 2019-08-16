#!/bin/bash
# By @doomedraven - https://twitter.com/D00m3dR4v3n
# minfds=1048576

# Static values
# Where to place everything
NETWORK_IFACE=virbr1
# for tor
IFACE_IP="192.168.1.1"
# DB password
PASSWD="SuperPuperSecret"

DIST_MASTER_IP=X.X.X.X

function issues() {
cat << EOI
Problems with PyOpenSSL?
    sudo rm -rf /usr/local/lib/python2.7/dist-packages/OpenSSL/
    sudo rm -rf /home/cuckoo/.local/lib/python2.7/site-packages/OpenSSL/
    sudo apt install --reinstall python-openssl

Problem with PIP?
    sudo python -m pip uninstall pip && sudo apt install python-pip --reinstall

Problems with Django importlib
/usr/local/lib/python2.7/dist-packages/ratelimit/middleware.py
    try:
        # Django versions >= 1.9
        from django.utils.module_loading import import_module
    except ImportError:
        # Django versions < 1.9
        from django.utils.importlib import import_module
EOI
}

function usage() {
cat << EndOfHelp
    You need to edit NETWORK_IFACE, IFACE_IP and PASSWD for correct install

    Usage: $0 <command> <cuckoo_version> <iface_ip>
        Example: $0 all cape 192.168.1.1
    Commands - are case insensitive:
        All - Installs dependencies, V2/CAPE, sets supervisor
        Cuckoo - Install V2/CAPE Cuckoo
        Dependencies - Install all dependencies with performance tricks
        Supervisor - Install supervisor config for CAPE; for v2 use cuckoo --help ;)
        Dist - will install CAPE distributed stuff
        redsocks2 - install redsocks2
        Issues - show some known possible bugs/solutions

    Useful links - THEY CAN BE OUTDATED; RTFM!!!
        * https://cuckoo.sh/docs/introduction/index.html
        * https://medium.com/@seifreed/how-to-deploy-cuckoo-sandbox-431a6e65b848
        * https://infosecspeakeasy.org/t/howto-build-a-cuckoo-sandbox/27
    Cuckoo V2 customizations neat howto
        * https://www.adlice.com/cuckoo-sandbox-customization-v2/
EndOfHelp
}

function redsocks2() {
    cd /tmp || return
    sudo apt install -y git libevent-dev libreadline-dev zlib1g-dev libncurses5-dev
    sudo apt install -y libssl1.0-dev 2>/dev/null
    sudo apt install -y libssl-dev 2>/dev/null
    git clone https://github.com/semigodking/redsocks redsocks2 && cd redsocks2
    DISABLE_SHADOWSOCKS=true make -j$(nproc) #ENABLE_STATIC=true
    sudo cp redsocks2 /usr/bin/
}

function distributed() {
    sudo apt install uwsgi -y 2>/dev/null
    sudo mkdir -p /data/{config,}db
    sudo chown mongodb:mongodb /data/ -R
    cat >> /etc/uwsgi/apps-available/cuckoo_api.ini << EOL
[uwsgi]
    plugins = python
    callable = application
    ;change this patch if is different
    chdir = /opt/CAPE/utils
    master = true
    mount = /=api.py
    processes = 5
    manage-script-name = true
    socket = 0.0.0.0:8090
    http-timeout = 200
    pidfile = /tmp/api.pid
    ; if you will use with nginx, comment next line
    protocol=http
    enable-threads = true
    lazy-apps = true
    timeout = 600
    chmod-socket = 664
    chown-socket = cuckoo:cuckoo
    gui = cuckoo
    uid = cuckoo
    stats = 127.0.0.1:9191
EOL

    ln -s /etc/uwsgi/apps-available/cuckoo_api.ini /etc/uwsgi/apps-enabled
    service uwsgi restart

    if [ ! -f /etc/systemd/system/mongod.service ]; then
        cat >> /etc/systemd/system/mongod.service <<EOL
# /etc/systemd/system/mongodb.service
[Unit]
Description=High-performance, schema-free document-oriented database
Wants=network.target
After=network.target

[Service]
ExecStartPre=/bin/mkdir -p /data/db
ExecStartPre=/bin/chown mongodb:mongodb /data/db -R
# https://www.tutorialspoint.com/mongodb/mongodb_replication.htm
ExecStart=/usr/bin/numactl --interleave=all /usr/bin/mongod --quiet --shardsvr --port 27017
# --replSet rs0
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
# enable on ramfs servers
# --wiredTigerCacheSizeGB=50
#User=mongodb
#Group=mongodb
#StandardOutput=syslog
#StandardError=syslog
#SyslogIdentifier=mongodb

[Install]
WantedBy=multi-user.target
EOL
fi

    if [ ! -f /etc/systemd/system/mongos.service ]; then
        cat >> /etc/systemd/system/mongos.service << EOL
[Unit]
Description=Mongo shard service
After=network.target
After=bind9.service
[Service]
PIDFile=/var/run/mongos.pid
User=root
ExecStart=/usr/bin/mongos --configdb cuckoo_config/${DIST_MASTER_IP}:27019 --port 27020
[Install]
WantedBy=multi-user.target
EOL
fi

    systemctl daemon-reload
    systemctl enable mongod.service
    systemctl enable mongos.service
    systemctl start mongod.service
    systemctl start mongos.service

    echo -e "\n\n\n[+] CAPE distributed documentation: https://github.com/kevoreilly/CAPE/blob/master/docs/book/src/usage/dist.rst"
}

function dependencies() {
    sudo timedatectl set-timezone UTC

    export LANGUAGE=en_US.UTF-8
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8

    sudo snap install canonical-livepatch
    #sudo canonical-livepatch enable APITOKEN

    # deps
    apt-get install jq sqlite3 tmux net-tools checkinstall graphviz git numactl python python-dev python-pip python-m2crypto swig upx-ucl libssl-dev wget zip unzip p7zip-full rar unrar unace-nonfree cabextract geoip-database libgeoip-dev libjpeg-dev mono-utils ssdeep libfuzzy-dev exiftool checkinstall ssdeep uthash-dev libconfig-dev libarchive-dev libtool autoconf automake privoxy software-properties-common wkhtmltopdf xvfb xfonts-100dpi tcpdump libcap2-bin -y
    apt-get install supervisor python-pil subversion python-capstone uwsgi uwsgi-plugin-python python-pyelftools -y
    #clamav clamav-daemon clamav-freshclam
    # if broken sudo python -m pip uninstall pip && sudo apt install python-pip --reinstall
    #pip install --upgrade pip
    # /usr/bin/pip
    # from pip import __main__
    # if __name__ == '__main__':
    #     sys.exit(__main__._main())
    pip install requests[security] pyOpenSSL pefile tldextract httpreplay imagehash oletools olefile capstone PyCrypto voluptuous xmltodict future python-dateutil requests_file -U
    pip install git+https://github.com/doomedraven/socks5man.git
    pip install git+https://github.com/doomedraven/sflock.git
    # re2
    apt-get install libre2-dev -y
    pip install re2

    sudo pip install matplotlib==2.2.2 numpy==1.15.0 six==1.11.0 statistics==1.0.3.5 lief==0.9.0

    echo "[+] Installing MongoDB"
    sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 9DA31620334BD75D9DCB49F368818C72E52529D4
    echo "deb [ arch=amd64 ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/4.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb.list

    sudo apt-get update
    sudo apt-get install -y mongodb-org-mongos mongodb-org-server mongodb-org-shell mongodb-org-tools
    pip install pymongo -U

    cat >> /etc/systemd/system/mongodb.service <<EOF
    [Unit]
    Description=High-performance, schema-free document-oriented database
    Wants=network.target
    After=network.target

    [Service]
    # https://www.tutorialspoint.com/mongodb/mongodb_replication.htm
    ExecStart=/usr/bin/numactl --interleave=all /usr/bin/mongod --quiet --shardsvr --bind_ip 0.0.0.0 --port 27017
    # --replSet rs0
    ExecReload=/bin/kill -HUP $MAINPID
    Restart=always
    # enable on ramfs servers
    # --wiredTigerCacheSizeGB=50
    User=mongodb
    Group=mongodb
    StandardOutput=syslog
    StandardError=syslog
    SyslogIdentifier=mongodb

    [Install]
    WantedBy=multi-user.target
EOF

    systemctl enable mongodb.service
    systemctl restart mongodb.service
    apt install -y libjpeg-dev zlib1g-dev
    pip install sqlalchemy sqlalchemy-utils jinja2 markupsafe bottle django==1.11.23 chardet pygal django-ratelimit rarfile jsbeautifier dpkt nose dnspython pytz requests python-magic geoip pillow java-random python-whois git+https://github.com/crackinglandia/pype32.git git+https://github.com/kbandla/pydeep.git flask flask-restful flask-sqlalchemy socks5man
    apt-get install -y openjdk-11-jdk-headless
    apt-get install -y openjdk-8-jdk-headless
    pip install distorm3 openpyxl git+https://github.com/volatilityfoundation/volatility.git PyCrypto #git+https://github.com/buffer/pyv8

    # Postgresql
    apt-get install postgresql libpq-dev -y
    pip install psycopg2

    # sudo su - postgres
    #psql
    sudo -u postgres -H sh -c "psql -c \"CREATE USER cuckoo WITH PASSWORD '$PASSWD'\"";
    sudo -u postgres -H sh -c "psql -c \"CREATE DATABASE cuckoo\"";
    sudo -u postgres -H sh -c "psql -d \"cuckoo\" -c \"GRANT ALL PRIVILEGES ON DATABASE cuckoo to cuckoo;\""
    #exit

    echo '[+] Installing Yara'
    apt-get install libtool libjansson-dev libmagic1 libmagic-dev jq autoconf checkinstall -y
    cd /tmp/ || return
    yara_info=$(curl -s https://api.github.com/repos/VirusTotal/yara/releases/latest)
    yara_version=$(echo $yara_info |jq .tag_name|sed "s/\"//g")
    yara_repo_url=$(echo $yara_info | jq ".zipball_url" | sed "s/\"//g")
    wget -q $yara_repo_url
    unzip $yara_version
    #wget "https://github.com/VirusTotal/yara/archive/v$yara_version.zip" && unzip "v$yara_version.zip"
    directory=`ls | grep "VirusTotal-yara-*"`
    cd $directory || return
    ./bootstrap.sh
    ./configure --enable-cuckoo --enable-magic --enable-dotnet --enable-profiling
    make -j"$(getconf _NPROCESSORS_ONLN)"
    checkinstall -D --pkgname="yara-$yara_version" --pkgversion="$yara_version|cut -c 2-" --default
    ldconfig
    cd ..
    rm "VirusTotal-yara-*.zip"
    git clone --recursive https://github.com/VirusTotal/yara-python
    cd yara-python || return
    pip install .
    pip3 install .

    # elastic as reporting module is incomplate
    #java + elastic
    #add-apt-repository ppa:webupd8team/java -y
    #wget -qO - https://packages.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
    #echo "deb http://packages.elastic.co/elasticsearch/2.x/debian stable main" | sudo tee -a /etc/apt/sources.list.d/elasticsearch-2.x.list
    #apt-get update
    #apt-get install oracle-java8-installer -y
    #apt-get install elasticsearch -y
    #/etc/init.d/elasticsearch start

    sudo apt-get install apparmor-utils -y
    sudo aa-disable /usr/sbin/tcpdump
    # ToDo check if user exits

    adduser -r cuckoo
    usermod -G cuckoo -a cuckoo
    groupadd pcap
    usermod -a -G pcap cuckoo
    chgrp pcap /usr/sbin/tcpdump
    setcap cap_net_raw,cap_net_admin=eip /usr/sbin/tcpdump

    '''
    cd /tmp/ || return
    git clone https://github.com/rieck/malheur.git
    cd malheur || return
    ./bootstrap
    ./configure --prefix=/usr
    make -j"$(getconf _NPROCESSORS_ONLN)"
    sudo checkinstall -D --pkgname=malheur --default
    dpkg -i malheur_0.6.0-1_amd64.deb
    '''

    # Speedup suricata >= 3.1
    # https://redmine.openinfosecfoundation.org/projects/suricata/wiki/Hyperscan
    # https://github.com/01org/hyperscan
    cd /tmp || return
    git clone https://github.com/01org/hyperscan.git
    cd hyperscan/ || return
    mkdir builded
    cd builded || return
    sudo apt-get install cmake libboost-dev ragel libhtp2 -y
    # doxygen sphinx-common libpcap-dev
    cmake -DBUILD_STATIC_AND_SHARED=1 ../
    # tests
    #bin/unit-hyperscan
    make -j"$(getconf _NPROCESSORS_ONLN)"
    sudo checkinstall -D --pkgname=hyperscan --default

    echo '[+] Configure Suricata'
    mkdir /var/run/suricata
    sudo chown cuckoo:cuckoo /var/run/suricata -R

    # if we wan suricata with hyperscan:
    sudo apt-get -y install libpcre3 libpcre3-dbg libpcre3-dev \
    build-essential autoconf automake libtool libpcap-dev libnet1-dev \
    libyaml-0-2 libyaml-dev zlib1g zlib1g-dev libcap-ng-dev libcap-ng0 \
    make libmagic-dev libjansson-dev libjansson4 pkg-config
    sudo apt-get -y install libnetfilter-queue-dev libnetfilter-queue1 libnfnetlink-dev libnfnetlink0


    echo "/usr/local/lib" | sudo tee --append /etc/ld.so.conf.d/usrlocal.conf
    sudo ldconfig

    #cd /tmp || return
    #wget https://github.com/luigirizzo/netmap/archive/v11.4.zip
    #unzip v11.4.zip
    #cd netmap-* || return
    #./configure
    #make -j"$(getconf _NPROCESSORS_ONLN)"
    # https://redmine.openinfosecfoundation.org/projects/suricata/wiki/Ubuntu_Installation
    cd /tmp || return
    wget "https://www.openinfosecfoundation.org/download/suricata-current.tar.gz"
    tar -xzf "suricata-current.tar.gz"
    rm "suricata-current.tar.gz"
    cd suricata-* || return
    ./configure --enable-nfqueue --prefix=/usr --sysconfdir=/etc --localstatedir=/var --with-libhs-includes=/usr/local/include/hs/ --with-libhs-libraries=/usr/local/lib/
    make -j"$(getconf _NPROCESSORS_ONLN)"
    sudo checkinstall -D --pkgname=suricata --default
    suricata --build-info|grep Hyperscan
    make install-conf

    cd python || return
    python setup.py build
    python setup.py install
    touch /etc/suricata/threshold.config


    """
    You can now start suricata by running as root something like '/usr/bin/suricata -c /etc/suricata//suricata.yaml -i eth0'.

    If a library like libhtp.so is not found, you can run suricata with:
    LD_LIBRARY_PATH=/usr/lib /usr/bin/suricata -c /etc/suricata//suricata.yaml -i eth0

    While rules are installed now, its highly recommended to use a rule manager for maintaining rules.
    The two most common are Oinkmaster and Pulledpork. For a guide see:
    https://redmine.openinfosecfoundation.org/projects/suricata/wiki/Rule_Management_with_Oinkmaster
    """

    # Download etupdate to update Emerging Threats Open IDS rules:
    sudo pip install suricata-update
    mkdir -p "/etc/suricata/rules"
    cp "/usr/share/suricata/rules/*" "/etc/suricata/rules/"
    crontab -l | { cat; echo "15 * * * * sudo /usr/bin/suricata-update -o /etc/suricata/rules/"; } | crontab -
    crontab -l | { cat; echo "15 * * * * /usr/bin/suricatasc -c reload-rules"; } | crontab -

    #change suricata yaml
    sed -i 's|#default-rule-path: /etc/suricata/rules|default-rule-path: /var/lib/suricata/rules|g' /etc/suricata/suricata.yaml
    sed -i 's/#rule-files:/rule-files:/g' /etc/suricata/suricata.yaml
    sed -i 's/# - suricata.rules/ - suricata.rules/g' /etc/suricata/suricata.yaml
    sed -i 's/RUN=yes/RUN=no/g' /etc/default/suricata
    sed -i 's/mpm-algo: ac/mpm-algo: hs/g' /etc/suricata/suricata.yaml
    sed -i 's/mpm-algo: auto/mpm-algo: hs/g' /etc/suricata/suricata.yaml
    sed -i 's/#run-as:/run-as:/g' /etc/suricata/suricata.yaml
    sed -i 's/#  user: suri/   user: cuckoo/g' /etc/suricata/suricata.yaml
    sed -i 's/#  user: suri/   group: cuckoo/g' /etc/suricata/suricata.yaml
    sed -i 's/    depth: 1mb/    depth: 0/g' /etc/suricata/suricata.yaml
    sed -i 's/request-body-limit: 100kb/request-body-limit: 0/g' /etc/suricata/suricata.yaml
    sed -i 's/response-body-limit: 100kb/response-body-limit: 0/g' /etc/suricata/suricata.yaml
    sed -i 's/EXTERNAL_NET: "!$HOME_NET"/EXTERNAL_NET: "ANY"/g' /etc/suricata/suricata.yaml
    # enable eve-log
    python -c "pa = '/etc/suricata/suricata.yaml';q=open(pa, 'rb').read().replace('eve-log:\n      enabled: no\n', 'eve-log:\n      enabled: yes\n');open(pa, 'wb').write(q);"


    # https://www.torproject.org/docs/debian.html.en
    echo "deb http://deb.torproject.org/torproject.org $(lsb_release -cs) main" >> /etc/apt/sources.list
    echo "deb-src http://deb.torproject.org/torproject.org $(lsb_release -cs) main" >> /etc/apt/sources.list
    sudo apt-get install gnupg2 -y
    gpg --keyserver keys.gnupg.net --recv A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89
    #gpg2 --recv A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89
    #gpg2 --export A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 | apt-key add -
    wget -qO - https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | sudo apt-key add -
    sudo apt-get update
    apt install tor deb.torproject.org-keyring libzstd1 -y

    cat >> /etc/tor/torrc <<EOF
TransPort $IFACE_IP:9040
DNSPort $IFACE_IP:5353
NumCPUs $(getconf _NPROCESSORS_ONLN)
EOF

    #Then restart Tor:
    sudo systemctl enable tor
    sudo systemctl start tor

    #Edit the Privoxy configuration
    #sudo sed -i 's/R#        forward-socks5t             /     127.0.0.1:9050 ./        forward-socks5t             /     127.0.0.1:9050 ./g' /etc/privoxy/config
    #service privoxy restart

    echo "* soft nofile 1048576" >> /etc/security/limits.conf
    echo "* hard nofile 1048576" >> /etc/security/limits.conf
    echo "root soft nofile 1048576" >> /etc/security/limits.conf
    echo "root hard nofile 1048576" >> /etc/security/limits.conf
    echo "fs.file-max = 100000" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.lo.disable_ipv6 = 1" >> /etc/sysctl.conf
    echo "net.bridge.bridge-nf-call-ip6tables = 0" >> /etc/sysctl.conf
    echo "net.bridge.bridge-nf-call-iptables = 0" >> /etc/sysctl.conf
    echo "net.bridge.bridge-nf-call-arptables = 0" >> /etc/sysctl.conf

    sudo sysctl -p

    ### PDNS
    sudo apt-get install git binutils-dev libldns-dev libpcap-dev libdate-simple-perl libdatetime-perl libdbd-mysql-perl -y
    cd /tmp || return
    git clone git://github.com/gamelinux/passivedns.git
    cd passivedns/ || return
    autoreconf --install
    ./configure
    make -j"$(getconf _NPROCESSORS_ONLN)"
    sudo checkinstall -D --pkgname=passivedns --default

    cd /usr/local/lib/python2.7/dist-packages/volatility || return
    mkdir resources
    cd resources || return
    touch "__init__.py"
    git clone https://github.com/nemequ/lzmat
    cd lzmat || return
    gcc -Wall -fPIC -c lzmat_dec.c
    gcc -shared -Wl,-soname,lzmat_dec.so.1 -o lzmat_dec.so.1.0 lzmat_dec.o
    mv "$(ls)" ..
    cd .. && rm -r lzmat

    cd /tmp || return
    git clone https://github.com/unicorn-engine/unicorn.git
    sudo apt-get install libglib2.0-dev -y
    cd unicorn || return
    ./make.sh
    sudo ./make.sh install
    pip install unicorn Capstone

}

function install_CAPE() {
    cd /opt || return
    git clone https://github.com/ctxis/CAPE/ CAPE
    sed -i 's/libvirt-python//g' CAPE/requirements.txt
    sed -i 's/clamd//g' CAPE/requirements.txt
    pip install -r CAPE/requirements.txt
    #chown -R root:cuckoo /usr/var/malheur/
    #chmod -R =rwX,g=rwX,o=X /usr/var/malheur/
    # Adapting owner permissions to the cuckoo path folder
    chown cuckoo:cuckoo -R "/opt/CAPE"
    sed -i "s/process_results = on/process_results = off/g" /opt/CAPE/conf/cuckoo.conf
    sed -i "s/tor = off/tor = on/g" /opt/CAPE/conf/cuckoo.conf
    sed -i "s/memory_dump = off/memory_dump = on/g" /opt/CAPE/conf/cuckoo.conf
    sed -i "s/achinery = vmwareserver/achinery = kvm/g" /opt/CAPE/conf/cuckoo.conf
    sed -i "s/interface = br0/interface = $NETWORK_IFACE/g" /opt/CAPE/conf/aux.conf

}

function supervisor() {
    #### Cuckoo Start at boot
    cat >> /etc/supervisor/conf.d/cuckoo.conf <<EOF
[program:cuckoo]
command=python cuckoo.py
directory=/opt/CAPE/
user=cuckoo
autostart=true
autorestart=true
stopasgroup=true
stderr_logfile=/var/log/supervisor/cuckoo.err.log
stdout_logfile=/var/log/supervisor/cuckoo.out.log
[program:web]
command=python manage.py runserver 0.0.0.0:8000
directory=/opt/CAPE/web
user=cuckoo
autostart=true
autorestart=true
stopasgroup=true
stderr_logfile=/var/log/supervisor/web.err.log
stdout_logfile=/var/log/supervisor/web.out.log
[program:process]
command=python process.py -p7 auto
user=cuckoo
directory=/opt/CAPE/utils
autostart=true
autorestart=true
stopasgroup=true
stderr_logfile=/var/log/supervisor/process.err.log
stdout_logfile=/var/log/supervisor/process.out.log
[program:rooter]
command=python rooter.py
directory=/opt/CAPE/utils
user=root
autostart=true
autorestart=true
stopasgroup=true
stderr_logfile=/var/log/supervisor/router.err.log
stdout_logfile=/var/log/supervisor/router.out.log
[program:suricata]
command=bash -c "mkdir /var/run/suricata; chown cuckoo:cuckoo /var/run/suricata; LD_LIBRARY_PATH=/usr/local/lib /usr/bin/suricata -c /etc/suricata/suricata.yaml --unix-socket -k none --user cuckoo --group cuckoo"
user=root
autostart=true
autorestart=true
stopasgroup=true
stderr_logfile=/var/log/supervisor/suricata.err.log
stdout_logfile=/var/log/supervisor/suricata.out.log
EOF


    # fix for too many open files
    python -c "pa = '/etc/supervisor/supervisord.conf';q=open(pa, 'rb').read().replace('[supervisord]\nlogfile=', '[supervisord]\nminfds=1048576 ;\nlogfile=');open(pa, 'wb').write(q);"
    sudo systemctl enable supervisor
    sudo systemctl start supervisor

    #supervisord -c /etc/supervisor/supervisord.conf
    supervisorctl -c /etc/supervisor/supervisord.conf reload

    supervisorctl reread
    supervisorctl update
    # msoffice decrypt encrypted files

}



# Doesn't work ${$1,,}
COMMAND=$(echo "$1"|tr "[A-Z]" "[a-z]")

case $COMMAND in
    '-h')
        usage
        exit 0;;
esac


if [ $# -eq 3 ]; then
    cuckoo_version=$2
    IFACE_IP=$3
elif [ $# -eq 2 ]; then
    cuckoo_version=$2
elif [ $# -eq 0 ]; then
    echo "[-] check --help"
    exit 1
fi

cuckoo_version=$(echo "$cuckoo_version"|tr "[A-Z]" "[a-z]")


#check if start with root
if [ "$EUID" -ne 0 ]; then
   echo 'This script must be run as root'
   exit 1
fi

OS="$(uname -s)"

case "$COMMAND" in
'all')
    dependencies
    if [ "$cuckoo_version" = "v2" ]; then
        pip install cuckoo
    else
        install_CAPE
    fi
    supervisor
    distributed
    redsocks2
    crontab -l | { cat; echo "@reboot $CUCKOO_ROOT/utils/suricata.sh"; } | crontab -
    crontab -l | { cat; echo "@reboot $CUCKOO_ROOT/socksproxies.sh"; } | crontab -
    crontab -l | { cat; echo "@reboot cd $CUCKOO_ROOT/utils/ && ./smtp_sinkhole.sh"; } | crontab -
    # suricata with socket is faster
    cat >> $CUCKOO_ROOT/utils/suricata.sh <<EOF
#!/bin/sh
# Add "@reboot $CUCKOO_ROOT/utils/suricata.sh" to the root crontab.
mkdir /var/run/suricata
chown cuckoo:cuckoo /var/run/suricata
LD_LIBRARY_PATH=/usr/local/lib /usr/bin/suricata -c /etc/suricata/suricata.yaml --unix-socket -k none -D
while [ ! -e /var/run/suricata/suricata-command.socket ]; do
    sleep 1
done
EOF
    ;;
'supervisor')
    supervisor;;
'cuckoo')
    if [ "$cuckoo_version" = "v2" ]; then
        pip install cuckoo
        print "[*] run cuckoo under cuckoo user, NEVER RUN IT AS ROOT!"
    else
        install_CAPE
    fi;;
'dist')
    distributed;;
'redsocks2')
    redsocks2;;
'dependencies')
    dependencies;;
'issues')
    issues;;
*)
    usage;;
esac

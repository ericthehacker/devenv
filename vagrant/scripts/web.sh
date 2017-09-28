#!/usr/bin/env bash
##
 # Copyright © 2016 by David Alger. All rights reserved
 # 
 # Licensed under the Open Software License 3.0 (OSL-3.0)
 # See included LICENSE file for full text of OSL-3.0
 # 
 # http://davidalger.com/contact/
 ##

set -e

source ./scripts/lib/utils.sh

########################################
:: configuring ssl root for cert signing
########################################

if ! [[ -d $SSL_DIR/rootca/ ]]; then
    mkdir -p $SSL_DIR/rootca/{certs,crl,newcerts,private}

    touch $SSL_DIR/rootca/index.txt
    echo 1000 > $SSL_DIR/rootca/serial
fi

# create a CA root certificate if none present
if [[ ! -f $SSL_DIR/rootca/private/ca.key.pem ]]; then
    openssl genrsa -out $SSL_DIR/rootca/private/ca.key.pem 4096

    openssl req -config /etc/openssl/rootca.conf -new -x509 -days 7300 -sha256 -extensions v3_ca \
        -key $SSL_DIR/rootca/private/ca.key.pem \
        -out $SSL_DIR/rootca/certs/ca.cert.pem \
        -subj "/C=US/O=Vagrant DevEnv"

    # alert user where to find root ca cert and what to do with it
    >&2 echo "Note: You must add $SSL_DIR/rootca/certs/ca.cert.pem to trusted certs on host."
fi

# add local CA root to the trusted key-store and enable Shared System Certificates
cp $SSL_DIR/rootca/certs/ca.cert.pem /etc/pki/ca-trust/source/anchors/local-ca.key.pem

update-ca-trust
update-ca-trust enable

# create local ssl private key
[[ ! -d /etc/nginx/ssl ]] && mkdir -p /etc/nginx/ssl
openssl genrsa -out /etc/nginx/ssl/local.key.pem 2048

########################################
:: installing web services
########################################

yum install -y redis sendmail varnish httpd nginx

# install php php-fpm and cross-version dependencies
yum $extra_repos install -y php php-fpm php-cli php-opcache php-xdebug \
    php-mysqlnd php-mhash php-curl php-gd php-intl php-mcrypt php-xsl php-mbstring php-soap php-bcmath php-zip php-ldap \
    php-pecl-memcache

# the ioncube-loader package for php7 does not exist yet
[[ "$PHP_VERSION" < 70 ]] && yum $extra_repos install -y php-ioncube-loader

# versions prior to PHP 5.6 don't prioritize ini files so some special handling is required
if [[ -f /etc/php.d/xdebug.ini ]]; then
    mv /etc/php.d/xdebug.ini /etc/php.d/xdebug.ini.rpmnew
    touch /etc/php.d/xdebug.ini    # prevents yum update from re-creating the file
fi

if [[ -f /etc/php.d/ioncube_loader.ini ]]; then
    mv /etc/php.d/ioncube_loader.ini /etc/php.d/05-ioncube_loader.ini
    touch /etc/php.d/ioncube_loader.ini     # prevent yum update from re-creating the file
fi

if [[ -f /etc/php-fpm.d/www.conf ]]; then
    mv /etc/php-fpm.d/www.conf /etc/php-fpm.d/www.conf.rpmnew
    touch /etc/php-fpm.d/www.conf     # prevent yum update from re-creating the file
fi

# phpredis does not yet have php7 support
[[ "$PHP_VERSION" < 70 ]] && yum $extra_repos install -y php-pecl-redis

########################################
:: configuring web services
########################################

perl -pi -e 's/Listen 80//' /etc/httpd/conf/httpd.conf
perl -0777 -pi -e 's#(<Directory "/var/www/html">.*?)AllowOverride None(.*?</Directory>)#$1AllowOverride All$2#s' \
        /etc/httpd/conf/httpd.conf

# disable error index file if installed
[ -f "/var/www/error/noindex.html" ] && mv /var/www/error/noindex.html /var/www/error/noindex.html.disabled

# create www-data user
adduser --system --user-group --no-create-home www-data
usermod -a -G www-data vagrant
usermod -a -G www-data nginx
usermod -a -G www-data apache

# allow vagrant user to access anything apache can (php sessions in /var/lib/php would be an example)
usermod -a -G apache vagrant
usermod -a -G apache nginx
usermod -a -G apache www-data

chgrp www-data /var/log/php-fpm     # allow www-data group to write log files
mkdir -p /etc/php-fpm.d/sites.d     # create directory for site specific overrides

chown -R root /var/log/php-fpm      # ditch apache ownership
chgrp -R www-data /var/lib/php      # ditch apache group

chkconfig redis on
service redis start

chkconfig httpd on
service httpd start

#chkconfig varnish on
#service varnish start

chkconfig nginx on
service nginx start

chkconfig php-fpm on
service php-fpm start

########################################
:: installing develop tools
########################################

npm install -g grunt-cli

install_tool https://getcomposer.org/composer.phar /usr/local/bin/composer

install_tool http://files.magerun.net/n98-magerun-latest.phar /usr/local/bin/n98-magerun /usr/local/bin/mr1
install_tool http://files.magerun.net/n98-magerun2-latest.phar /usr/local/bin/n98-magerun2 /usr/local/bin/mr2

ln -s /usr/local/bin/mr1 /usr/local/bin/mr

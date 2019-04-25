# from https://www.drupal.org/docs/8/system-requirements/drupal-8-php-requirements
FROM php:7.2.17-apache

# install the PHP extensions we need
RUN set -ex; \
	\
	if command -v a2enmod; then \
		a2enmod rewrite; \
	fi; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	\
	apt-get update; \
	apt-get install -y --no-install-recommends \
		libjpeg-dev \
		libpng-dev \
		libpq-dev \
	; \
	\
	docker-php-ext-configure gd --with-png-dir=/usr --with-jpeg-dir=/usr; \
	docker-php-ext-install -j "$(nproc)" \
		gd \
		opcache \
		pdo_mysql \
		pdo_pgsql \
		zip \
	; \
	\
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark; \
	ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
		| awk '/=>/ { print $3 }' \
		| sort -u \
		| xargs -r dpkg-query -S \
		| cut -d: -f1 \
		| sort -u \
		| xargs -rt apt-mark manual; \
	\
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
		echo 'opcache.memory_consumption=512'; \
		echo 'opcache.interned_strings_buffer=8'; \
		echo 'opcache.max_accelerated_files=4000'; \
		echo 'opcache.revalidate_freq=60'; \
		echo 'opcache.fast_shutdown=1'; \
		echo 'opcache.enable_cli=1'; \
		echo 'upload_max_filesize = 50M'; \
		echo 'post_max_size = 50M'; \
		echo 'memory_limit = 512M'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini

WORKDIR /var/www/html
# END Drupal Dockerfile 

# BEGIN Customizations
ENV DRUPAL_DATABASE_NAME="" \
    DRUPAL_DATABASE_HOST="" \
    DRUPAL_DATABASE_PASSWORD="" \
    DRUPAL_DATABASE_USER="" \
    DRUPAL_DATABASE_PORT="3306" \
		DRUPAL_HASH_SALT="" \
		DRUPAL_SITE_URL="" \
		DRUSH_VERSION=8 \
		SERVER_ADMIN_EMAIL="noreply@ag.ny.gov" \
		DOCUMENT_ROOT="/var/www/html/docroot" \
		SSL_CERT_FILE="" \
		SSL_CERT_KEY="" \
		SSL_CERT_CHAIN=""

RUN apt-get update && \
		apt-get install -y \
		imagemagick \
		openssh-server

RUN { \
		echo '#! /bin/sh'; \
		echo 'service ssh start'; \
	} > /etc/init.d/sshd.sh 

RUN chmod +x /etc/init.d/sshd.sh

# Enable SSL and Docroot changes for Drupal
# RUN sed -i 's_/var/www/html_/var/www/html/docroot_' /etc/apache2/sites-available/000-default.conf
# RUN sed -i 's_/var/www/html_/var/www/html/docroot_' /etc/apache2/sites-available/default-ssl.conf

COPY ./conf.d/000-default.conf /etc/apache2/sites-available/000-default.conf
COPY ./conf.d/default-ssl.conf /etc/apache2/sites-available/default-ssl.conf
COPY ./conf.d/security.conf /etc/apache2/conf-available/security.conf

RUN a2enmod ssl headers
RUN a2ensite default-ssl.conf

# Composer
RUN curl -sS https://getcomposer.org/installer | php && \
    chmod +x composer.phar && \
    mv composer.phar /usr/local/bin/composer

# Drush
RUN /usr/local/bin/composer global require drush/drush:^${DRUSH_VERSION} && \
    ln -s /root/.composer/vendor/drush/drush/drush /usr/local/bin/drush

# Setup SSH https://github.com/wadmiraal/docker-drupal/blob/master/Dockerfile
RUN echo 'root:root' | chpasswd
RUN useradd -ms /bin/bash drupal
RUN echo 'drupal:drupal' | chpasswd
RUN sed -i 's/^#PermitRootLogin.\+/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN mkdir /var/run/sshd && chmod 0755 /var/run/sshd
RUN mkdir -p /root/.ssh/ && touch /root/.ssh/authorized_keys
RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

COPY ./conf.d/apache2-foreground /usr/local/bin
RUN chmod +x /usr/local/bin/apache2-foreground

# Cleanup
RUN apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
		rm -fr /tmp/* /var/lib/apt/lists/* /var/tmp/* && \
    apt-get autoremove -y && \
    apt-get autoclean && \
    apt-get clean

EXPOSE 80 443 22

# vim:set ft=dockerfile:
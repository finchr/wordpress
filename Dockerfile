FROM wordpress:6.6-php8.3-apache

## RUN cp $PHP_INI_DIR/php.ini-production $PHP_INI_DIR/php.ini
COPY cloud-run.ini $PHP_INI_DIR/conf.d/cloud-run.ini

COPY ./html /var/www/html
RUN chown -R www-data:www-data /var/www/html

WORKDIR /var/www/html

# Use the PORT environment variable in Apache configuration files.
# https://cloud.google.com/run/docs/reference/container-contract#port

ENV PHP_INI_DIR /usr/local/etc/php

# Fix compliance failure "Apache ServerTokens Information Disclosure"
## RUN sed -i -e 's/^ServerTokens .*$/ServerTokens Prod/' /etc/apache2/conf-enabled/security.conf

ENV PORT 8080

RUN sed -i 's/80/${PORT}/g' /etc/apache2/sites-available/000-default.conf /etc/apache2/ports.conf

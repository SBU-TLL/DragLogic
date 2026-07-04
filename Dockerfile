# syntax=docker/dockerfile:1
###############################################################################
# Production image — DragLogic (natural-deduction theorem prover)
#
# Tech stack : static client-side app (HTML + ES-module JS + CSS + images;
#              normally served from GitHub Pages) with ONE server-side endpoint,
#              save.php, which appends saved proofs to record.json (research
#              telemetry). No framework, no database, no .htaccess.
# Web server : Apache (php:8.3-apache) — consistent with the rest of the fleet;
#              serves the static assets and runs save.php via mod_php.
#
# Authentication: NONE. This is a public static tool; there is no login/SSO.
#   If access ever needs gating, do it at the ingress / reverse proxy
#   (Ansible-managed), not in this image. No secrets, no DB (see
#   .env.production.example).
#
# Telemetry hardening: record.json is NOT baked into the image (save.php
# recreates it on first write), and HTTP reads of it are denied (below) so the
# collected proofs are not publicly downloadable — while save.php can still
# append to it on the filesystem.
#
# Runs non-root (www-data) on unprivileged port 8080.
###############################################################################
FROM php:8.3-apache

# --- Apache modules (headers for parity; no .htaccess/rewrites in this app) ---
RUN set -eux; \
    a2enmod headers

# --- Run as a non-root user on an unprivileged port (8080) ---
RUN set -eux; \
    sed -ri 's/^Listen 80$/Listen 8080/' /etc/apache2/ports.conf; \
    sed -ri 's/:80>/:8080>/' /etc/apache2/sites-available/000-default.conf

# --- Security hardening (suppress server tokens/signature, TRACE, ETag) ---
RUN set -eux; \
    { \
      echo 'ServerTokens Prod'; \
      echo 'ServerSignature Off'; \
      echo 'TraceEnable Off'; \
      echo 'FileETag None'; \
    } > /etc/apache2/conf-available/zzz-hardening.conf; \
    a2enconf zzz-hardening

# --- Docroot policy: no dir listing, parse .htaccess if any, deny HTTP reads of
#     the telemetry file (save.php still appends to it on disk), log to
#     stdout/stderr for container log capture ---
RUN set -eux; \
    { \
      echo '<Directory /var/www/html>'; \
      echo '    Options -Indexes +FollowSymLinks'; \
      echo '    AllowOverride All'; \
      echo '    Require all granted'; \
      echo '</Directory>'; \
      echo '<Files "record.json">'; \
      echo '    Require all denied'; \
      echo '</Files>'; \
      echo 'ErrorLog /dev/stderr'; \
      echo 'CustomLog /dev/stdout combined'; \
    } > /etc/apache2/conf-available/zzz-docroot.conf; \
    a2enconf zzz-docroot

# --- Application code. .dockerignore excludes .ddev/, .git/, .env*, Dockerfile,
#     the record.json telemetry, the stray sier.py, docs and OS junk. ---
COPY --chown=www-data:www-data . /var/www/html/

# --- Permissions: read-only app tree owned by www-data; save.php (running as
#     www-data) can create/append record.json in the docroot ---
RUN set -eux; \
    find /var/www/html -type d -exec chmod 0755 {} +; \
    find /var/www/html -type f -exec chmod 0644 {} +; \
    chown -R www-data:www-data /var/run/apache2 /var/log/apache2 /var/lock; \
    chmod -R g=u /var/run/apache2 /var/log/apache2 /var/lock

USER www-data
EXPOSE 8080

# php:apache base CMD = apache2-foreground

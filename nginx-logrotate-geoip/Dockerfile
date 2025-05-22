FROM nginx:1.26.3-alpine-slim

LABEL maintainer="Bismarck Villca Soliz <bismarck.villca@gmail.com>"

# Instalar dependencias
RUN apk add --no-cache logrotate nginx-mod-http-geoip2 nginx-mod-stream-geoip2

# Copiar configuración de logrotate
COPY logrotate.conf /etc/logrotate.d/nginx
RUN chmod 0644 /etc/logrotate.d/nginx

# Copiar entrypoint.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Cron para ejecutar logrotate cada 6 horas
RUN echo "0 */6 * * * /usr/sbin/logrotate -vf /etc/logrotate.d/nginx" > /etc/crontabs/root

# Crear el directorio de logs para cron
RUN mkdir -p /var/log/cron

ENTRYPOINT [ "/entrypoint.sh" ]

FROM nginx:1.28-alpine-slim

LABEL maintainer="Bismarck Villca Soliz <bismarck.villca@gmail.com>"

# Instalar dependencias
RUN apk add --no-cache logrotate

# Copiar configuración de logrotate
COPY logrotate.conf /etc/logrotate.conf

CMD ["nginx", "-g", "daemon off;"]

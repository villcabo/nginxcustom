FROM nginx:1.28-alpine-slim

# Instalar dependencias
RUN apk add --no-cache logrotate

# Copiar configuración de logrotate
COPY logrotate.conf /etc/logrotate.conf

CMD ["nginx", "-g", "daemon off;"]

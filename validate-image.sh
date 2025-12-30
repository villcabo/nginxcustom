#!/bin/bash
# Script de validación para imagen nginx-logrotate-geoip
# Uso: ./validate-image.sh [imagen:tag]

IMAGE=${1:-"villcabo/nginx-logrotate-geoip:1.29.0-bookworm-beta"}

echo "🔍 Validando imagen: $IMAGE"
echo "════════════════════════════════════════════════════════════════"

# 1. Verificar que la imagen existe
echo "1️⃣  Verificando existencia de la imagen..."
if docker inspect "$IMAGE" > /dev/null 2>&1; then
    echo "   ✅ Imagen encontrada"
else
    echo "   ❌ Imagen no encontrada"
    exit 1
fi

# 2. Verificar archivos de módulos
echo
echo "2️⃣  Verificando archivos de módulos..."
docker run --rm --entrypoint="" "$IMAGE" sh -c "
    echo '   📁 Contenido de /etc/nginx/modules/:'
    ls -la /etc/nginx/modules/ | grep -E '(brotli|geoip2)'
    echo
    echo '   📊 Tamaños de módulos compilados:'
    ls -lh /etc/nginx/modules/ngx_http_*brotli*.so /etc/nginx/modules/ngx_http_geoip2_module.so 2>/dev/null || echo '   ⚠️  Algunos módulos no encontrados'
"

# 3. Verificar que nginx puede cargar los módulos
echo
echo "3️⃣  Verificando compatibilidad de módulos con nginx..."
docker run --rm --entrypoint="" "$IMAGE" sh -c "
cat > /tmp/test.conf << 'EOF'
load_module modules/ngx_http_geoip2_module.so;
load_module modules/ngx_http_brotli_filter_module.so;
load_module modules/ngx_http_brotli_static_module.so;
events {
    worker_connections 1024;
}
http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    server {
        listen 80;
        location / {
            return 200 'Modules loaded successfully';
        }
    }
}
EOF
if nginx -t -c /tmp/test.conf 2>/dev/null; then
    echo '   ✅ Todos los módulos se cargan correctamente'
else
    echo '   ❌ Error cargando módulos'
    nginx -t -c /tmp/test.conf
fi
"

# 4. Verificar dependencias de runtime
echo
echo "4️⃣  Verificando dependencias de runtime..."
docker run --rm --entrypoint="" "$IMAGE" sh -c "
    echo '   🔗 Verificando librerías necesarias:'
    echo '      - libmaxminddb:'
    if ldconfig -p | grep -q maxminddb; then echo '        ✅ Disponible'; else echo '        ❌ Faltante'; fi
    echo '      - libbrotli:'
    if ldconfig -p | grep -q brotli; then echo '        ✅ Disponible'; else echo '        ❌ Faltante'; fi
    echo '      - libpcre:'
    if ldconfig -p | grep -q pcre; then echo '        ✅ Disponible'; else echo '        ❌ Faltante'; fi
"

# 5. Verificar configuración de ejemplo
echo
echo "5️⃣  Verificando archivos de configuración..."
docker run --rm --entrypoint="" "$IMAGE" sh -c "
    echo '   📄 Archivos de configuración incluidos:'
    if [ -f '/etc/nginx/conf.d/modules-example.conf' ]; then
        echo '      ✅ modules-example.conf'
    else
        echo '      ❌ modules-example.conf faltante'
    fi
    if [ -f '/etc/logrotate.d/nginx' ]; then
        echo '      ✅ logrotate.conf'
    else
        echo '      ❌ logrotate.conf faltante'
    fi
"

# 6. Verificar versión de nginx
echo
echo "6️⃣  Información de nginx compilado..."
docker run --rm --entrypoint="" "$IMAGE" nginx -V 2>&1 | head -3

# 7. Verificar tamaño de imagen
echo
echo "7️⃣  Información de la imagen..."
docker images "$IMAGE" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"

echo
echo "🎉 Validación completada!"
echo "════════════════════════════════════════════════════════════════"
# Nginx with GeoIP2 and Brotli Modules

This Docker image includes Nginx compiled with the following dynamic modules:

## Included Modules

### 🌍 GeoIP2 Module (`ngx_http_geoip2_module.so`)
- Provides geographical location information based on IP addresses
- Uses MaxMind GeoIP2 databases
- Supports country, city, ISP, and other location data

### 🗜️ Brotli Compression Modules
- `ngx_http_brotli_filter_module.so` - Dynamic Brotli compression
- `ngx_http_brotli_static_module.so` - Serve pre-compressed .br files

### 📝 LogRotate
- Automatic log rotation every 6 hours
- Prevents log files from growing too large

## Usage

### 1. Load the modules in your nginx.conf:

```nginx
# Load dynamic modules
load_module modules/ngx_http_geoip2_module.so;
load_module modules/ngx_http_brotli_filter_module.so; 
load_module modules/ngx_http_brotli_static_module.so;
```

### 2. Configure GeoIP2:

```nginx
http {
    # Download GeoIP2 databases first
    geoip2 /usr/share/GeoIP/GeoLite2-Country.mmdb {
        $geoip2_data_country_code country iso_code;
        $geoip2_data_country_name country names en;
    }
    
    geoip2 /usr/share/GeoIP/GeoLite2-City.mmdb {
        $geoip2_data_city_name city names en;
        $geoip2_data_latitude location latitude;
        $geoip2_data_longitude location longitude;
    }
}
```

### 3. Configure Brotli:

```nginx
http {
    # Enable Brotli compression
    brotli on;
    brotli_comp_level 6;
    brotli_buffers 16 8k;
    brotli_min_length 20;
    brotli_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;
}
```

## Example Configuration

See `/etc/nginx/conf.d/modules-example.conf` inside the container for a complete example.

## Build Command

```bash
./build.sh logrotate-geoip
```

## GeoIP2 Database Setup

To use GeoIP2 features, you'll need to download the MaxMind databases:

```bash
# Create directory for GeoIP databases
mkdir -p /usr/share/GeoIP

# Download GeoLite2 databases (requires MaxMind account)
wget -O /usr/share/GeoIP/GeoLite2-Country.mmdb "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-Country&license_key=YOUR_LICENSE_KEY&suffix=tar.gz"
wget -O /usr/share/GeoIP/GeoLite2-City.mmdb "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&license_key=YOUR_LICENSE_KEY&suffix=tar.gz"
```

## Testing

### Test Brotli Compression:
```bash
curl -H "Accept-Encoding: br" http://your-server/
```

### Test GeoIP2:
```bash
curl http://your-server/geoip-status
```

## Performance Benefits

- **Brotli**: Up to 20% better compression than gzip
- **GeoIP2**: Fast IP geolocation without external API calls
- **LogRotate**: Automatic log management prevents disk space issues
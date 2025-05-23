# Nginx Docker Images

This repository contains custom Docker images for Nginx with additional features:

- **Nginx + Logrotate**: Nginx with automatic log rotation using logrotate and cron.
- **Nginx + Logrotate + GeoIP**: Nginx with log rotation and GeoIP module support.

## Features

- Automated log rotation for Nginx logs using logrotate and cron.
- Easy to extend and customize.
- Optional GeoIP support for IP-based geolocation.

## Usage

### 1. Nginx + Logrotate

This image runs Nginx and automatically rotates logs daily at midnight using logrotate and cron.

**Build the image:**

```bash
docker build -t nginx-logrotate ./nginx-logrotate
```

**Run the container:**

```bash
docker run -d --name nginx-logrotate -p 80:80 nginx-logrotate
```

### 2. Nginx + Logrotate + GeoIP

This image includes GeoIP support in addition to log rotation.

**Build the image:**

```bash
docker build -t nginx-logrotate-geoip ./nginx-logrotate-geoip
```

**Run the container:**

```bash
docker run -d --name nginx-logrotate-geoip -p 80:80 nginx-logrotate-geoip
```

## Customization

- You can modify the Nginx configuration or logrotate rules by editing the files in the respective directories.
- To add more modules or change the log rotation schedule, update the Dockerfile or entrypoint scripts as needed.

## Directory Structure

```
nginxcustom/
├── nginx-logrotate/
│   ├── Dockerfile
│   ├── entrypoint.sh
│   └── ... 
├── nginx-logrotate-geoip/
│   ├── Dockerfile
│   └── ...
└── README.md
```

## License

MIT License.

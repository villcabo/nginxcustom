FROM nginx:1.26-alpine

# Install logrotate
RUN apk add --no-cache logrotate

# Copy the initialization script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Replace the entrypoint with a custom script
ENTRYPOINT ["/entrypoint.sh"]

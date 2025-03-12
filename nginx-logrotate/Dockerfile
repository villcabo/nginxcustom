FROM nginx:1.26-alpine

# Install logrotate
RUN apk add --no-cache logrotate

# Copy the initialization script
COPY logrotate-entrypoint.sh /usr/local/bin/logrotate-entrypoint.sh
RUN chmod +x /usr/local/bin/logrotate-entrypoint.sh

# Replace the entrypoint with a custom script
ENTRYPOINT ["/usr/local/bin/logrotate-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]

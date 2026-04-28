FROM nginx:1.29-alpine

ENV BACKEND_ID=unknown
ENV STARTUP_DELAY=20

# Strip the default vhost (we generate ours from the template at startup).
RUN rm -f /etc/nginx/conf.d/default.conf

COPY default.conf.tmpl /etc/nginx/templates/default.conf.tmpl
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 8080
CMD ["/start.sh"]

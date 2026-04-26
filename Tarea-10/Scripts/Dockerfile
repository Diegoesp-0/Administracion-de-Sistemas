FROM nginx:alpine

RUN adduser -D -H -s /sbin/nologin webuser

RUN sed -i 's/server_tokens on/server_tokens off/' /etc/nginx/nginx.conf || \
    echo "server_tokens off;" >> /etc/nginx/conf.d/default.conf

COPY --chown=webuser:webuser . /usr/share/nginx/html/

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
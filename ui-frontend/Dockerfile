# Build stage
FROM node:20-alpine AS build

WORKDIR /app

COPY package*.json ./
COPY postcss.config.js ./
COPY . .

RUN npm install
RUN npm run build

# Production stage: nginx proxies /api/* and injects Authorization from Secret
FROM nginx:stable-alpine

RUN apk add --no-cache gettext \
  && rm -f /etc/nginx/conf.d/default.conf

COPY --from=build /app/build /usr/share/nginx/html
COPY nginx.conf.template /etc/nginx/nginx-api.conf.template
COPY docker-entrypoint.d/40-subst-api-token.sh /docker-entrypoint.d/40-subst-api-token.sh
RUN chmod +x /docker-entrypoint.d/40-subst-api-token.sh

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]

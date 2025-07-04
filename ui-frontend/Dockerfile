# Этап сборки
FROM node:20-alpine AS build

WORKDIR /app

COPY package*.json ./
COPY postcss.config.js ./
COPY . .

RUN npm install
RUN npm run build

# Этап продакшена
FROM nginx:stable-alpine

COPY --from=build /app/build /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
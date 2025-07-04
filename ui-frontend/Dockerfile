# Этап сборки
FROM node:20-alpine as build

WORKDIR /app

# Копируем package файлы для кэширования зависимостей
COPY package*.json ./

# Копируем конфигурационные файлы
COPY postcss.config.js ./
COPY tailwind.config.js ./

# Устанавливаем зависимости
RUN npm install

# Копируем остальное приложение
COPY . .

# Собираем приложение
RUN npm run build

# Этап продакшена
FROM nginx:stable-alpine

COPY --from=build /app/build /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
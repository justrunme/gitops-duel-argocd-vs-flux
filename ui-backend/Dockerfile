# Используем официальный образ Node.js
FROM node:20-alpine

# Устанавливаем рабочую директорию
WORKDIR /app

# Копируем package.json и package-lock.json
COPY package*.json ./

# Устанавливаем зависимости
RUN npm install

# Копируем остальное приложение
COPY . .

# Открываем порт
EXPOSE 3001

# Запускаем приложение
CMD ["npm", "start"]
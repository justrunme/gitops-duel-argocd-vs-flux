# GitHub Secrets - Настройка

## Необходимые секреты

Для корректной работы GitHub Actions workflow требуются следующие секреты:

### Docker Hub Credentials

Workflow использует Docker Hub для публикации образов UI компонентов.

#### Требуемые секреты:

1. **DOCKER_USERNAME** - имя пользователя Docker Hub
2. **DOCKER_PASSWORD** - пароль или Access Token Docker Hub

## Инструкция по настройке

### 1. Получение Docker Hub Access Token (рекомендуется)

1. Войдите в [Docker Hub](https://hub.docker.com/)
2. Перейдите в **Account Settings** → **Security** → **Access Tokens**
3. Нажмите **New Access Token**
4. Задайте имя токена (например: "GitHub Actions CI")
5. Выберите права доступа: **Read, Write, Delete**
6. Скопируйте созданный токен (он больше не будет показан)

### 2. Настройка секретов в GitHub

1. Перейдите в ваш GitHub репозиторий
2. Откройте **Settings** → **Secrets and variables** → **Actions**
3. Нажмите **New repository secret**

#### Добавьте следующие секреты:

**DOCKER_USERNAME:**
- Name: `DOCKER_USERNAME`
- Secret: ваше имя пользователя Docker Hub

**DOCKER_PASSWORD:**
- Name: `DOCKER_PASSWORD`  
- Secret: ваш Access Token или пароль Docker Hub

### 3. Альтернативная настройка для организации

Если вы используете GitHub в рамках организации, секреты можно настроить на уровне организации:

1. Перейдите в **Organization Settings**
2. **Secrets and variables** → **Actions**
3. Добавьте секреты с теми же именами

## Проверка настройки

После настройки секретов workflow должен иметь доступ к Docker Hub. Проверить можно:

1. Запустив workflow вручную
2. Проверив логи шага "Login to Docker Hub"
3. Убедившись, что образы успешно публикуются в Docker Hub

## Безопасность

⚠️ **Важные рекомендации по безопасности:**

1. **Используйте Access Token вместо пароля** - это более безопасно
2. **Ограничьте права токена** - дайте только необходимые права
3. **Регулярно обновляйте токены** - рекомендуется менять каждые 6-12 месяцев
4. **Не выводите секреты в логи** - GitHub автоматически маскирует их
5. **Используйте секреты только в необходимых workflow** - ограничьте доступ

## Альтернативные варианты

### GitHub Container Registry (GHCR)

Вместо Docker Hub можно использовать GitHub Container Registry:

```yaml
- name: Login to GitHub Container Registry
  uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}
```

### Приватные реестры

Для корпоративных приватных реестров:

```yaml
- name: Login to Private Registry
  uses: docker/login-action@v3
  with:
    registry: your-registry.com
    username: ${{ secrets.REGISTRY_USERNAME }}
    password: ${{ secrets.REGISTRY_PASSWORD }}
```

## Устранение неполадок

### Проблема: Authentication failed

**Причины:**
- Неправильные credentials
- Истек Access Token
- Недостаточные права у токена

**Решение:**
1. Проверьте правильность имени пользователя
2. Создайте новый Access Token
3. Убедитесь, что токен имеет права на запись

### Проблема: Rate limit exceeded

**Причины:**
- Слишком много запросов к Docker Hub
- Превышен лимит для free аккаунта

**Решение:**
1. Используйте Docker Hub Pro/Team подписку
2. Переключитесь на GHCR
3. Оптимизируйте частоту сборок

## Команды для тестирования

```bash
# Локальная проверка Docker credentials
docker login

# Сборка образов локально
docker build -t test-backend ./ui-backend
docker build -t test-frontend ./ui-frontend

# Проверка публикации
docker push your-username/test-image
```

## Мониторинг

Рекомендуется отслеживать:
1. Успешность аутентификации в Docker Hub
2. Размер и время сборки образов
3. Использование лимитов Docker Hub
4. Безопасность Access Token'ов
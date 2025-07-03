const express = require('express');
const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');
const app = express();
const port = 3001; // Порт для бэкенда

// CORS middleware
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization');
  
  if (req.method === 'OPTIONS') {
    res.sendStatus(200);
  } else {
    next();
  }
});

app.use(express.json());

app.get('/', (req, res) => {
  res.send('UI Backend is running!');
});

// Пример эндпоинта для получения версии kubectl
app.get('/api/kubectl-version', (req, res) => {
  exec('kubectl version --client -o json', (error, stdout, stderr) => {
    if (error) {
      console.error(`exec error: ${error}`);
      return res.status(500).json({ error: stderr });
    }
    try {
      res.json(JSON.parse(stdout));
    } catch (parseError) {
      res.status(500).json({ error: 'Failed to parse kubectl output' });
    }
  });
});

// Эндпоинт для получения списка приложений ArgoCD
app.get('/api/argocd/applications', (req, res) => {
  exec('argocd app list -o json', (error, stdout, stderr) => {
    if (error) {
      console.error(`exec error: ${error}`);
      return res.status(500).json({ error: stderr });
    }
    try {
      res.json(JSON.parse(stdout));
    } catch (parseError) {
      res.status(500).json({ error: 'Failed to parse ArgoCD output' });
    }
  });
});

// Эндпоинт для получения списка Kustomization-ресурсов Flux
app.get('/api/flux/kustomizations', (req, res) => {
  exec('flux get kustomizations -A -o json', (error, stdout, stderr) => {
    if (error) {
      console.error(`exec error: ${error}`);
      return res.status(500).json({ error: stderr });
    }
    try {
      res.json(JSON.parse(stdout));
    } catch (parseError) {
      res.status(500).json({ error: 'Failed to parse Flux output' });
    }
  });
});

// Эндпоинт для получения манифестов конкретного приложения ArgoCD
app.get('/api/argocd/application/:name/manifests', (req, res) => {
  const appName = req.params.name;
  const namespace = req.query.namespace || 'default'; // Предполагаем 'default' если не указан
  exec(`kubectl get application ${appName} -n ${namespace} -o yaml`, (error, stdout, stderr) => {
    if (error) {
      console.error(`exec error: ${error}`);
      return res.status(500).json({ error: stderr });
    }
    res.send(stdout);
  });
});

// Эндпоинт для получения манифестов конкретного Kustomization-ресурса Flux
app.get('/api/flux/kustomization/:name/manifests', (req, res) => {
  const kustomizationName = req.params.name;
  const namespace = req.query.namespace || 'flux-system'; // Предполагаем 'flux-system' если не указан
  exec(`kubectl get kustomization ${kustomizationName} -n ${namespace} -o yaml`, (error, stdout, stderr) => {
    if (error) {
      console.error(`exec error: ${error}`);
      return res.status(500).json({ error: stderr });
    }
    res.send(stdout);
  });
});

// Эндпоинт для получения манифестов из Git-репозитория
app.get('/api/git/manifests', (req, res) => {
  const repoUrl = req.query.repoUrl;
  const appPath = req.query.appPath; // Путь к приложению в репозитории (например, apps/argocd/nginx)

  if (!repoUrl || !appPath) {
    return res.status(400).json({ error: 'repoUrl and appPath are required query parameters.' });
  }

  const tempDir = path.join(__dirname, 'temp', Date.now().toString());

  exec(`git clone ${repoUrl} ${tempDir}`, (error, stdout, stderr) => {
    if (error) {
      console.error(`git clone error: ${error}`);
      return res.status(500).json({ error: stderr });
    }

    const fullAppPath = path.join(tempDir, appPath);

    fs.readdir(fullAppPath, (err, files) => {
      if (err) {
        console.error(`readdir error: ${err}`);
        return res.status(500).json({ error: err.message });
      }

      const manifests = {};
      let filesProcessed = 0;

      if (files.length === 0) {
        // Если директория пуста, сразу отправляем ответ
        fs.rm(tempDir, { recursive: true, force: true }, (rmErr) => {
          if (rmErr) console.error(`Error removing temp dir: ${rmErr}`);
        });
        return res.json(manifests);
      }

      files.forEach(file => {
        const filePath = path.join(fullAppPath, file);
        fs.readFile(filePath, 'utf8', (readErr, content) => {
          if (readErr) {
            console.error(`readFile error: ${readErr}`);
            // Продолжаем, даже если один файл не удалось прочитать
          } else {
            manifests[file] = content;
          }
          filesProcessed++;
          if (filesProcessed === files.length) {
            // Все файлы прочитаны, удаляем временную директорию и отправляем ответ
            fs.rm(tempDir, { recursive: true, force: true }, (rmErr) => {
              if (rmErr) console.error(`Error removing temp dir: ${rmErr}`);
            });
            res.json(manifests);
          }
        });
      });
    });
  });
});

app.listen(port, () => {
  console.log(`UI Backend listening at http://localhost:${port}`);
});
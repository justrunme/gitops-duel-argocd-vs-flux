const express = require('express');
const { exec } = require('child_process');
const app = express();
const port = 3001; // Порт для бэкенда

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
    res.json(JSON.parse(stdout));
  });
});

// Эндпоинт для получения списка приложений ArgoCD
app.get('/api/argocd/applications', (req, res) => {
  exec('argocd app list -o json', (error, stdout, stderr) => {
    if (error) {
      console.error(`exec error: ${error}`);
      return res.status(500).json({ error: stderr });
    }
    res.json(JSON.parse(stdout));
  });
});

// Эндпоинт для получения списка Kustomization-ресурсов Flux
app.get('/api/flux/kustomizations', (req, res) => {
  exec('flux get kustomizations -A -o json', (error, stdout, stderr) => {
    if (error) {
      console.error(`exec error: ${error}`);
      return res.status(500).json({ error: stderr });
    }
    res.json(JSON.parse(stdout));
  });
});

app.listen(port, () => {
  console.log(`UI Backend listening at http://localhost:${port}`);
});
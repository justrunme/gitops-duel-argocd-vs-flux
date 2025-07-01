import React, { useState, useEffect } from 'react';
import { useParams, useLocation } from 'react-router-dom';
import DiffViewer from './DiffViewer'; // Будет создан позже
import YAML from 'yaml'; // Нужно будет установить

function AppDetail() {
  const { type, name } = useParams();
  const location = useLocation();
  const queryParams = new URLSearchParams(location.search);
  const namespace = queryParams.get('namespace');

  const [clusterManifest, setClusterManifest] = useState(null);
  const [gitManifest, setGitManifest] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  // Временные заглушки для repoUrl и appPath
  const repoUrl = 'https://github.com/justrunme/gitops-duel-argocd-vs-flux.git';
  const argocdAppPath = 'apps/argocd/nginx'; // Пример для Nginx
  const fluxAppPath = 'apps/flux/nginx'; // Пример для Nginx

  useEffect(() => {
    const fetchManifests = async () => {
      try {
        let clusterRes;
        let gitRes;

        if (type === 'argocd') {
          clusterRes = await fetch(`/api/argocd/application/${name}/manifests?namespace=${namespace}`);
          gitRes = await fetch(`/api/git/manifests?repoUrl=${repoUrl}&appPath=${argocdAppPath}`);
        } else if (type === 'flux') {
          clusterRes = await fetch(`/api/flux/kustomization/${name}/manifests?namespace=${namespace}`);
          gitRes = await fetch(`/api/git/manifests?repoUrl=${repoUrl}&appPath=${fluxAppPath}`);
        } else {
          throw new Error('Unknown application type');
        }

        if (!clusterRes.ok) {
          throw new Error(`Cluster API error: ${clusterRes.statusText}`);
        }
        if (!gitRes.ok) {
          throw new Error(`Git API error: ${gitRes.statusText}`);
        }

        const clusterData = await clusterRes.text();
        const gitData = await gitRes.json(); // Git API возвращает JSON

        setClusterManifest(clusterData);
        setGitManifest(gitData);

      } catch (err) {
        setError(err.message);
      } finally {
        setLoading(false);
      }
    };

    fetchManifests();
  }, [type, name, namespace]);

  if (loading) {
    return <div className="text-center text-gray-600">Loading manifests...</div>;
  }

  if (error) {
    return <div className="text-center text-red-600">Error: {error}</div>;
  }

  // Для простоты, покажем только первый манифест из Git
  const firstGitManifestKey = Object.keys(gitManifest)[0];
  const firstGitManifestContent = gitManifest[firstGitManifestKey];

  return (
    <div className="p-4">
      <h2 className="text-2xl font-bold mb-4">Application Detail: {name} ({type})</h2>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <h3 className="text-xl font-semibold mb-2">Cluster Manifest</h3>
          <pre className="bg-gray-800 text-white p-4 rounded-md overflow-auto text-sm">
            {clusterManifest}
          </pre>
        </div>
        <div>
          <h3 className="text-xl font-semibold mb-2">Git Manifest ({firstGitManifestKey})</h3>
          <pre className="bg-gray-800 text-white p-4 rounded-md overflow-auto text-sm">
            {firstGitManifestContent}
          </pre>
        </div>
      </div>

      <h3 className="text-xl font-semibold mt-8 mb-2">Diff (Cluster vs Git)</h3>
      {/* Здесь будет компонент DiffViewer */}
      <DiffViewer oldText={firstGitManifestContent} newText={clusterManifest} />
    </div>
  );
}

export default AppDetail;
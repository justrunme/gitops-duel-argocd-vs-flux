import React, { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';

function AppList() {
  const [argocdApps, setArgocdApps] = useState([]);
  const [fluxKustomizations, setFluxKustomizations] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    const fetchApps = async () => {
      try {
        const [argocdRes, fluxRes] = await Promise.all([
          fetch('/api/argocd/applications'),
          fetch('/api/flux/kustomizations')
        ]);

        if (!argocdRes.ok) {
          throw new Error(`ArgoCD API error: ${argocdRes.statusText}`);
        }
        if (!fluxRes.ok) {
          throw new Error(`Flux API error: ${fluxRes.statusText}`);
        }

        const argocdData = await argocdRes.json();
        const fluxData = await fluxRes.json();

        setArgocdApps(argocdData);
        setFluxKustomizations(fluxData.items); // Flux возвращает items

      } catch (err) {
        setError(err.message);
      } finally {
        setLoading(false);
      }
    };

    fetchApps();
  }, []);

  if (loading) {
    return <div className="text-center text-gray-600">Loading applications...</div>;
  }

  if (error) {
    return <div className="text-center text-red-600">Error: {error}</div>;
  }

  const allApps = [
    ...argocdApps.map(app => ({
      type: 'argocd',
      name: app.metadata.name,
      namespace: app.metadata.namespace,
      syncStatus: app.status.sync.status,
      healthStatus: app.status.health.status,
    })),
    ...fluxKustomizations.map(kust => ({
      type: 'flux',
      name: kust.metadata.name,
      namespace: kust.metadata.namespace,
      syncStatus: kust.status.conditions.find(c => c.type === 'Ready')?.status === 'True' ? 'Synced' : 'OutOfSync', // Простая логика статуса
      healthStatus: kust.status.conditions.find(c => c.type === 'Ready')?.status === 'True' ? 'Healthy' : 'Degraded', // Простая логика статуса
    })),
  ];

  return (
    <div className="p-4">
      <h2 className="text-2xl font-bold mb-4">Applications Overview</h2>
      <div className="overflow-x-auto">
        <table className="min-w-full bg-white border border-gray-300 shadow-sm rounded-lg">
          <thead>
            <tr className="bg-gray-200 text-gray-600 uppercase text-sm leading-normal">
              <th className="py-3 px-6 text-left">Type</th>
              <th className="py-3 px-6 text-left">Name</th>
              <th className="py-3 px-6 text-left">Namespace</th>
              <th className="py-3 px-6 text-left">Sync Status</th>
              <th className="py-3 px-6 text-left">Health Status</th>
              <th className="py-3 px-6 text-center">Actions</th>
            </tr>
          </thead>
          <tbody className="text-gray-700 text-sm">
            {allApps.map((app, index) => (
              <tr key={index} className="border-b border-gray-200 hover:bg-gray-100">
                <td className="py-3 px-6 text-left whitespace-nowrap">{app.type}</td>
                <td className="py-3 px-6 text-left">{app.name}</td>
                <td className="py-3 px-6 text-left">{app.namespace}</td>
                <td className="py-3 px-6 text-left">
                  <span className={`px-2 py-1 rounded-full text-xs font-semibold ${
                    app.syncStatus === 'Synced' ? 'bg-green-200 text-green-800' : 'bg-red-200 text-red-800'
                  }`}>
                    {app.syncStatus}
                  </span>
                </td>
                <td className="py-3 px-6 text-left">
                  <span className={`px-2 py-1 rounded-full text-xs font-semibold ${
                    app.healthStatus === 'Healthy' ? 'bg-green-200 text-green-800' : 'bg-red-200 text-red-800'
                  }`}>
                    {app.healthStatus}
                  </span>
                </td>
                <td className="py-3 px-6 text-center">
                  <Link
                    to={`/apps/${app.type}/${app.name}?namespace=${app.namespace}`}
                    className="text-blue-600 hover:text-blue-800 font-medium"
                  >
                    View Details
                  </Link>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

export default AppList;
import React from 'react';
import { useParams } from 'react-router-dom';

function AppDetail() {
  const { type, name } = useParams();
  return (
    <div>
      <h2 className="text-2xl font-bold mb-4">Application Detail: {name} ({type})</h2>
      <p>Details for {name} will go here.</p>
    </div>
  );
}

export default AppDetail;
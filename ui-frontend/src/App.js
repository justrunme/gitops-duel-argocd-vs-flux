import React from 'react';
import { BrowserRouter as Router, Route, Routes, Link } from 'react-router-dom';
import AppList from './components/AppList';
import AppDetail from './components/AppDetail';

function App() {
  return (
    <Router>
      <div className="min-h-screen bg-gray-100">
        <nav className="bg-white shadow-md p-4">
          <ul className="flex space-x-4">
            <li>
              <Link to="/" className="text-blue-600 hover:text-blue-800">Home</Link>
            </li>
            <li>
              <Link to="/apps" className="text-blue-600 hover:text-blue-800">Applications</Link>
            </li>
          </ul>
        </nav>

        <main className="container mx-auto p-4">
          <Routes>
            <Route path="/" element={<Home />} />
            <Route path="/apps" element={<AppList />} />
            <Route path="/apps/:type/:name" element={<AppDetail />} />
          </Routes>
        </main>
      </div>
    </Router>
  );
}

function Home() {
  return (
    <h1 className="text-3xl font-bold text-gray-800">Welcome to GitOps Duel Dashboard!</h1>
  );
}

export default App;
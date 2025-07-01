import React from 'react';

function DiffViewer({ oldText, newText }) {
  // Простая реализация diff. В реальном приложении можно использовать библиотеку типа `diff-match-patch`
  const diff = (oldText || '').split('\n').map((line, index) => {
    const newLine = (newText || '').split('\n')[index];
    if (line === newLine) {
      return <div key={index} className="text-gray-700">{line}</div>;
    } else {
      return (
        <div key={index} className="bg-red-200 text-red-800">
          <span className="line-through">{line}</span>
          <span className="bg-green-200 text-green-800">{newLine}</span>
        </div>
      );
    }
  });

  return (
    <div className="bg-white p-4 rounded-md shadow-sm font-mono text-sm">
      {diff}
    </div>
  );
}

export default DiffViewer;
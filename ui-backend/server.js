'use strict';

const { createApp } = require('./app');

const port = Number(process.env.PORT || 3001);
const app = createApp();

if (require.main === module) {
  app.listen(port, () => {
    console.log(`UI Backend listening at http://localhost:${port}`);
  });
}

module.exports = app;

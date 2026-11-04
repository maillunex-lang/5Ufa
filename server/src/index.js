import { fileURLToPath } from 'node:url';
import { createApp } from './app.js';

const here = (p) => fileURLToPath(new URL(p, import.meta.url));
const env = process.env;
const app = createApp({
  dataDir: env.DATA_DIR || here('../../data'),
  contentPath: env.CONTENT_PATH || here('../../content/game.json'),
  adminDir: env.ADMIN_DIR || here('../../admin'),
});
const port = Number(env.PORT || 8080);
app.server.listen(port, env.HOST || '0.0.0.0', () => console.log(`5Ufa server listening on :${port}`));
for (const s of ['SIGTERM', 'SIGINT']) process.on(s, () => { app.close(); process.exit(0); });

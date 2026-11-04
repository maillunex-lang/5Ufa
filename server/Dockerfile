FROM node:22-alpine
WORKDIR /app
COPY server/ /app/server/
COPY admin/ /app/admin/
COPY content/ /app/content/
COPY client/assets/models/ /app/seed-models/
ENV NODE_ENV=production DATA_DIR=/data CONTENT_PATH=/app/content/game.json ADMIN_DIR=/app/admin SEED_MEDIA_DIR=/app/seed-models PORT=8080
VOLUME /data
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1:8080/health || exit 1
CMD ["node", "--disable-warning=ExperimentalWarning", "server/src/index.js"]

FROM node:20-bullseye-slim AS builder

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npx prisma generate
RUN npm run build

FROM node:20-bullseye-slim AS runner

ENV NODE_ENV=production

RUN groupadd --system app && useradd --system --gid app --home-dir /home/app --create-home --shell /usr/sbin/nologin app

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts && npm cache clean --force

COPY --from=builder --chown=app:app /app/dist ./dist
COPY --from=builder --chown=app:app /app/prisma ./prisma
COPY --from=builder --chown=app:app /app/node_modules/.prisma ./node_modules/.prisma
# The prisma CLI is a runtime dependency (see package.json) so the
# entrypoint can run `npx prisma migrate deploy`; its engines package
# must be copied alongside the generated client.
COPY --from=builder --chown=app:app /app/node_modules/@prisma/engines ./node_modules/@prisma/engines

COPY --chown=app:app docker-entrypoint.sh ./docker-entrypoint.sh
RUN chmod +x ./docker-entrypoint.sh

USER app

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 CMD ["node", "-e", "const port = Number(process.env.PORT) || 3000; fetch('http://127.0.0.1:' + port + '/v1/health').then((response) => { if (!response.ok) process.exit(1); }).catch(() => process.exit(1));"]

# Entrypoint applies pending migrations, then execs this command.
CMD ["node", "dist/main.js"]
ENTRYPOINT ["./docker-entrypoint.sh"]

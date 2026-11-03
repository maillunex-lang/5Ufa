# Образ API-сервера. Собирается из корня репозитория:
#   docker compose build api
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY server/requirements.txt /app/requirements.txt
RUN pip install -r /app/requirements.txt

COPY server/ /app/
# Схемы и базовый контент нужны серверу для проверки и первичного импорта
COPY shared/ /repo/shared/
COPY content/ /repo/content/

ARG GIT_SHA=dev
ENV GIT_SHA=${GIT_SHA} \
    SHARED_DIR=/repo/shared \
    BASE_CONTENT_DIR=/repo/content

RUN useradd --create-home --uid 1000 game \
    && mkdir -p /data/content-store \
    && chown -R game:game /data
USER game

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips", "*"]

# Lexika backend — FastAPI on uvicorn, deps via uv.
# Build:  docker build -t lexika-backend ./backend
# Run:    docker run -p 8000:8000 -e DATABASE_URL=... -e LEXIKA_ALLOWED_ORIGINS=... lexika-backend
FROM python:3.14-slim

# uv: fast, reproducible installs from uv.lock
RUN pip install --no-cache-dir uv

WORKDIR /app

# Install dependencies first (cached unless the lockfile changes)
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

# App source
COPY . .

ENV PORT=8000
EXPOSE 8000

# Shell form so ${PORT} expands (hosts like Render/Fly inject their own port).
CMD uv run --no-sync uvicorn main:app --host 0.0.0.0 --port ${PORT}

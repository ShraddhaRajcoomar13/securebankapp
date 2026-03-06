# Use slim variant for smaller image size and better security
FROM python:3.11-slim

# Install system dependencies (needed for many Python packages like psycopg2, cryptography, etc.)
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user and group early (security best practice)
RUN groupadd -r appuser && useradd -r -g appuser -m appuser

# Set working directory
WORKDIR /app

# Copy requirements first → maximizes layer caching
COPY requirements.txt .

# Install Python dependencies (no cache to keep image small)
RUN pip install --no-cache-dir -r requirements.txt \
    && rm -rf /root/.cache/pip

# Copy application code
COPY app/ ./app/

# Ensure non-root user owns the application files
RUN chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Expose port (informational only – not required at runtime)
EXPOSE 8000

# Healthcheck – uses your /health endpoint (helps Docker & ECS know when app is ready)
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=5 \
  CMD curl -f http://localhost:8000/health || exit 1

# Run Gunicorn + Uvicorn workers
CMD ["gunicorn", "app.main:app", \
     "--workers", "2", \
     "--worker-class", "uvicorn.workers.UvicornWorker", \
     "--bind", "0.0.0.0:8000", \
     "--timeout", "120", \
     "--log-level", "debug", \
     "--access-logfile", "-", \
     "--error-logfile", "-"]
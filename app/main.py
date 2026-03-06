# app/main.py
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
import structlog
import time
from prometheus_fastapi_instrumentator import Instrumentator

from .database import engine, Base, init_db
from .routes import auth, accounts, transactions

# Structured logging setup
structlog.configure(
    processors=[
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.add_log_level,
        structlog.processors.JSONRenderer(),
    ],
)
logger = structlog.get_logger()

# Lifespan for startup/shutdown events
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: initialize database tables once
    init_db()
    yield
    # Shutdown: optional cleanup (e.g. close connections if needed)


# Create FastAPI app
app = FastAPI(
    title="SecureBankApp API",
    version="1.0.0",
    docs_url=None,      # Disable Swagger UI in production
    redoc_url=None,     # Disable ReDoc in production
    lifespan=lifespan,
)

# CORS middleware – allow frontend origins
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://securebankapp-frontend.s3-website-us-east-1.amazonaws.com",
        "https://d3ho4d9vv7u6jf.cloudfront.net",
        "*"  # ← temporary for testing – remove in production
    ],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)

# Trusted Host middleware (optional – restricts Host header)
app.add_middleware(
    TrustedHostMiddleware,
    allowed_hosts=["*"],  # Change to your domains in production
)

# Custom request logging middleware
@app.middleware("http")
async def request_logging_middleware(request: Request, call_next):
    start_time = time.time()
    response = await call_next(request)
    duration = time.time() - start_time

    logger.info(
        "request completed",
        method=request.method,
        path=request.url.path,
        status_code=response.status_code,
        duration_ms=round(duration * 1000, 2),
        client_ip=request.client.host,
    )

    # Security headers
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    response.headers["Content-Security-Policy"] = "default-src 'self'"

    return response

# Include routers
app.include_router(auth.router, prefix="/api/v1/auth", tags=["auth"])
app.include_router(accounts.router, prefix="/api/v1/accounts", tags=["accounts"])
app.include_router(transactions.router, prefix="/api/v1/transactions", tags=["transactions"])

# Prometheus metrics endpoint
Instrumentator().instrument(app).expose(app, endpoint="/metrics")

# Health check endpoint
@app.get("/health")
async def health():
    return {"status": "healthy"}
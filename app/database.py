# app/database.py
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session

_engine = None
_SessionLocal = None


def _get_engine():
    """Build engine lazily — only on first request, not at import time.
    This allows the container to start up before AWS credentials are needed."""
    global _engine, _SessionLocal
    if _engine is None:
        from .config import get_settings
        settings = get_settings()
        url = (
            f"postgresql://{settings['DB_USER']}:{settings['DB_PASSWORD']}"
            f"@{settings['DB_HOST']}/{settings['DB_NAME']}"
        )
        _engine = create_engine(url, pool_pre_ping=True)
        _SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=_engine)
    return _engine


def get_db():
    _get_engine()
    db = _SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db():
    """Create all tables — called from lifespan in main.py."""
    engine = _get_engine()
    from .models import Base
    Base.metadata.create_all(bind=engine)


# Expose engine for main.py import compatibility
class _LazyEngine:
    """Proxy that defers engine creation until first attribute access."""

    def __getattr__(self, name):
        return getattr(_get_engine(), name)


engine = _LazyEngine()


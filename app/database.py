# app/database.py
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from .config import get_settings

settings = get_settings()

SQLALCHEMY_DATABASE_URL = (
    f"postgresql://{settings['DB_USER']}:{settings['DB_PASSWORD']}"
    f"@{settings['DB_HOST']}/{settings['DB_NAME']}"
)

engine = create_engine(SQLALCHEMY_DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db():
    """Create all tables on startup using the models' Base."""
    from .models import Base  # import here to avoid circular imports
    Base.metadata.create_all(bind=engine)

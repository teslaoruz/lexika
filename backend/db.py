"""DB engine + session. ponytail: sync SQLAlchemy is plenty for ~100 users;
async engine is the upgrade path if I/O contention ever shows up."""
import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, DeclarativeBase

DATABASE_URL = os.environ.get(
    "DATABASE_URL", "postgresql://lexika:lexika@localhost:5432/lexika"
)

engine = create_engine(DATABASE_URL, future=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, future=True)


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

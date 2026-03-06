# app/routes/auth.py
from argon2 import PasswordHasher, exceptions
from jose import JWTError, jwt
from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
import random

from ..config import get_settings
from ..models import User, UserRole, Account
from ..schemas import UserCreate, LoginRequest
from ..database import get_db

router = APIRouter()

# Argon2 hasher (modern, secure, no 72-byte limit)
pwd_hasher = PasswordHasher(
    time_cost=2,          # reasonable default
    memory_cost=102400,   # 100 MiB
    parallelism=8,        # good balance
    hash_len=32,
    salt_len=16
)


def hash_password(password: str) -> str:
    """Hash password using Argon2 (no length limit)."""
    return pwd_hasher.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a plain password against its Argon2 hash."""
    try:
        pwd_hasher.verify(hashed_password, plain_password)
        return True
    except exceptions.VerifyMismatchError:
        return False


def create_access_token(data: dict) -> str:
    """Generate JWT access token with expiration."""
    settings = get_settings()
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=settings["JWT_EXPIRE_MINUTES"])
    to_encode.update({"exp": expire})
    return jwt.encode(
        to_encode,
        settings["JWT_SECRET"],
        algorithm=settings["JWT_ALGORITHM"]
    )


async def get_current_user(token: str = Depends(oauth2_scheme)) -> dict:
    """Extract and validate the current user from JWT token."""
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        settings = get_settings()
        payload = jwt.decode(
            token,
            settings["JWT_SECRET"],
            algorithms=[settings["JWT_ALGORITHM"]]
        )
        user_id: str = payload.get("sub")
        if user_id is None:
            raise credentials_exception
    except JWTError as e:
        raise credentials_exception from e

    return payload


oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")


def require_role(*allowed_roles: UserRole):
    """RBAC dependency factory."""
    async def role_checker(current_user: dict = Depends(get_current_user)):
        if current_user.get("role") not in [role.value for role in allowed_roles]:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Insufficient permissions"
            )
        return current_user
    return role_checker


@router.post("/register", status_code=status.HTTP_201_CREATED)
async def register(user_data: UserCreate, db: Session = Depends(get_db)):
    """Register a new user and auto-create a checking account."""
    if db.query(User).filter(User.email == user_data.email).first():
        raise HTTPException(status_code=400, detail="Email already registered")

    user = User(
        email=user_data.email,
        password_hash=hash_password(user_data.password),
        full_name=user_data.full_name,
        role=UserRole.CUSTOMER,
    )
    db.add(user)
    db.flush()  # Flush to get user.id

    account = Account(
        user_id=user.id,
        account_number=f"ACC{random.randint(10000000, 99999999)}",
        account_type="checking",
        balance=0.00,
        currency="USD",
    )
    db.add(account)
    db.commit()
    db.refresh(user)

    return {
        "user_id": str(user.id),
        "email": user.email,
        "message": "User registered and checking account created successfully"
    }


@router.post("/login")
async def login(credentials: LoginRequest, db: Session = Depends(get_db)):
    """Authenticate user and return JWT access token."""
    user = db.query(User).filter(User.email == credentials.email).first()
    if not user or not verify_password(credentials.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if user.is_active != "Y":
        raise HTTPException(status_code=400, detail="Account is disabled")

    access_token = create_access_token({
        "sub": str(user.id),
        "email": user.email,
        "role": user.role.value,
    })

    return {
        "access_token": access_token,
        "token_type": "bearer"
    }
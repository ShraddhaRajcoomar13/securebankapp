# app/routes/auth.py
from passlib.context import CryptContext
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

# Lazy-loaded password context (prevents early initialization crash)
_pwd_context = None

def get_pwd_context():
    global _pwd_context
    if _pwd_context is None:
        _pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
    return _pwd_context

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")


def hash_password(password: str) -> str:
    """Hash password with bcrypt (12 rounds) – truncate to 72 bytes to avoid bcrypt limit."""
    return get_pwd_context().hash(password[:72])


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a plain password against its hash."""
    return get_pwd_context().verify(plain_password, hashed_password)


def create_access_token(data: dict) -> str:
    """Create JWT access token with expiration."""
    settings = get_settings()
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=settings["JWT_EXPIRE_MINUTES"])
    to_encode.update({"exp": expire})
    return jwt.encode(
        to_encode,
        settings["JWT_SECRET"],
        algorithm=settings["JWT_ALGORITHM"]
    )


async def get_current_user(token: str = Depends(oauth2_scheme)):
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


def require_role(*allowed_roles: UserRole):
    """
    Dependency factory for role-based access control (RBAC).
    Example usage: @router.get("/admin", dependencies=[Depends(require_role(UserRole.ADMIN))])
    """
    async def role_checker(current_user: dict = Depends(get_current_user)):
        user_role = current_user.get("role")
        if user_role not in [role.value for role in allowed_roles]:
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

    # Auto-create checking account
    account = Account(
        user_id=user.id,
        account_number=f"ACC{random.randint(10000000, 99999999)}",  # nosec B311
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
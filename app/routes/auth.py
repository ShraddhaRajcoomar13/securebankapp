# app/routes/auth.py
from passlib.context import CryptContext
from jose import JWTError, jwt
from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from ..config import get_settings
from ..models import User, UserRole
from ..schemas import UserCreate, LoginRequest
from ..database import get_db
from ..models import User, UserRole, Account
import random

pwd_context = CryptContext(schemes=['bcrypt'], deprecated='auto')
oauth2_scheme = OAuth2PasswordBearer(tokenUrl='/api/v1/auth/login')
router = APIRouter()

def hash_password(password: str) -> str:
    """bcrypt with 12 rounds -- slows brute force attacks."""
    return pwd_context.hash(password, rounds=12)

def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)

def create_access_token(data: dict) -> str:
    settings = get_settings()
    payload = data.copy()
    payload['exp'] = datetime.utcnow() + timedelta(
        minutes=settings['JWT_EXPIRE_MINUTES']
    )
    return jwt.encode(
        payload,
        settings['JWT_SECRET'],
        algorithm=settings['JWT_ALGORITHM']
    )

async def get_current_user(token: str = Depends(oauth2_scheme)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail='Invalid credentials',
        headers={'WWW-Authenticate': 'Bearer'},
    )
    try:
        settings = get_settings()
        payload = jwt.decode(
            token,
            settings['JWT_SECRET'],
            algorithms=[settings['JWT_ALGORITHM']]
        )
        user_id = payload.get('sub')
        if user_id is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception
    return payload

def require_role(*roles: UserRole):
    """RBAC decorator factory."""
    async def role_checker(current_user = Depends(get_current_user)):
        if current_user.get('role') not in [r.value for r in roles]:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail='Insufficient permissions'
            )
        return current_user
    return role_checker


@router.post('/register', status_code=201)
async def register(user_data: UserCreate, db: Session = Depends(get_db)):
    existing = db.query(User).filter(User.email == user_data.email).first()
    if existing:
        raise HTTPException(status_code=400, detail='Email already registered')

    user = User(
        email=user_data.email,
        password_hash=hash_password(user_data.password),
        full_name=user_data.full_name,
        role=UserRole.CUSTOMER,
    )
    db.add(user)
    db.flush()  # Get user.id without committing

    # Auto-create a checking account for every new user
    account = Account(
        user_id=user.id,
        account_number='ACC' + str(random.randint(10000000, 99999999)),
        account_type='checking',
        balance=0.00,
        currency='USD',
    )
    db.add(account)
    db.commit()
    db.refresh(user)
    return {'user_id': str(user.id), 'email': user.email}

@router.post('/login')
async def login(credentials: LoginRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == credentials.email).first()
    if not user or not verify_password(credentials.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail='Invalid email or password'
        )
    if user.is_active != 'Y':
        raise HTTPException(status_code=400, detail='Account disabled')

    token = create_access_token({
        'sub': str(user.id),
        'email': user.email,
        'role': user.role.value,
    })
    return {'access_token': token, 'token_type': 'bearer'}
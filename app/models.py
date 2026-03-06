# app/models.py
from sqlalchemy import Column, String, Numeric, DateTime, ForeignKey, Enum
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from sqlalchemy.ext.declarative import declarative_base
from datetime import datetime
import uuid, enum

Base = declarative_base()

class UserRole(str, enum.Enum):
    CUSTOMER = 'customer'
    ADMIN    = 'admin'
    AUDITOR  = 'auditor'  # Read-only access for compliance

class User(Base):
    __tablename__ = 'users'
    id            = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email         = Column(String(255), unique=True, nullable=False, index=True)
    password_hash = Column(String(255), nullable=False)
    full_name     = Column(String(255), nullable=False)
    role          = Column(Enum(UserRole), default=UserRole.CUSTOMER, nullable=False)
    is_active     = Column(String(1), default='Y', nullable=False)
    created_at    = Column(DateTime, default=datetime.utcnow)
    accounts      = relationship('Account', back_populates='owner')

class Account(Base):
    __tablename__  = 'accounts'
    id             = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id        = Column(UUID(as_uuid=True), ForeignKey('users.id'), nullable=False)
    account_number = Column(String(20), unique=True, nullable=False, index=True)
    account_type   = Column(String(20), default='checking')  # checking, savings
    balance        = Column(Numeric(15, 2), default=0.00, nullable=False)
    currency       = Column(String(3), default='USD')
    created_at     = Column(DateTime, default=datetime.utcnow)
    owner          = relationship('User', back_populates='accounts')
    transactions   = relationship('Transaction', back_populates='account')

class Transaction(Base):
    __tablename__     = 'transactions'
    id                = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    account_id        = Column(UUID(as_uuid=True), ForeignKey('accounts.id'), nullable=False)
    transaction_type  = Column(String(20), nullable=False)  # debit, credit
    amount            = Column(Numeric(15, 2), nullable=False)
    description       = Column(String(500))
    merchant_category = Column(String(50))
    fraud_score       = Column(Numeric(5, 4), default=0.0)  # 0-1 from Lambda
    created_at        = Column(DateTime, default=datetime.utcnow)
    account           = relationship('Account', back_populates='transactions')


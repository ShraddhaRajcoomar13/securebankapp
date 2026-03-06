# app/schemas.py
from pydantic import BaseModel, EmailStr, Field, field_validator
from decimal import Decimal
import re

class UserCreate(BaseModel):
    email:     EmailStr            # Validates email format
    password:  str = Field(min_length=8, max_length=128)
    full_name: str = Field(min_length=2, max_length=255)

    @field_validator('password')
    @classmethod
    def password_complexity(cls, v):
        if not re.search(r'[A-Z]', v):
            raise ValueError('Password must contain uppercase letter')
        if not re.search(r'[0-9]', v):
            raise ValueError('Password must contain a number')
        if not re.search(r'[^a-zA-Z0-9]', v):
            raise ValueError('Password must contain special character')
        return v

    @field_validator('full_name')
    @classmethod
    def no_special_chars(cls, v):
        if not re.match(r'^[a-zA-Z\s-]+$', v):
            raise ValueError('Name must contain only letters, spaces, hyphens')
        return v.strip()

class TransactionCreate(BaseModel):
    account_id:        str
    transaction_type:  str = Field(pattern='^(debit|credit)$')  # Enum-like
    amount:            Decimal = Field(gt=0, le=1_000_000)  # Max $1M
    description:       str = Field(max_length=500, default='')
    merchant_category: str = Field(max_length=50, default='')

class LoginRequest(BaseModel):
    email:    EmailStr
    password: str = Field(min_length=1, max_length=128)


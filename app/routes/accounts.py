# app/routes/accounts.py
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from .auth import get_current_user
from ..database import get_db
from ..models import Account

router = APIRouter()

@router.get('/me')
async def get_my_account(current_user=Depends(get_current_user), db: Session=Depends(get_db)):
    account = db.query(Account).filter(Account.user_id == current_user['sub']).first()
    if not account:
        raise HTTPException(status_code=404, detail='No account found')
    return {
        'account_id': str(account.id),
        'account_number': account.account_number,
        'balance': float(account.balance),
        'currency': account.currency,
        'account_type': account.account_type,
    }

@router.get('/')
async def list_accounts(current_user=Depends(get_current_user), db: Session=Depends(get_db)):
    accounts = db.query(Account).filter(Account.user_id == current_user['sub']).all()
    return {
        'accounts': [
            {
                'account_id': str(a.id),
                'account_number': a.account_number,
                'balance': float(a.balance),
                'currency': a.currency,
                'account_type': a.account_type,
            } for a in accounts
        ]
    }

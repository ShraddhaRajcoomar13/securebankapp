# app/routes/transactions.py
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import text  # Parameterized queries = SQL injection prevention
import boto3, json, structlog
from ..database import get_db
from ..models import Transaction, Account
from ..schemas import TransactionCreate
from .auth import get_current_user

router = APIRouter()
logger = structlog.get_logger()

@router.post('/')
async def create_transaction(
    tx_data: TransactionCreate,  # Pydantic validates EVERYTHING here
    current_user = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    # Authorization: customer can only transact on THEIR accounts
    account = db.query(Account).filter(
        Account.id == tx_data.account_id,
        Account.user_id == current_user['sub']  # RBAC: ownership check
    ).first()

    if not account:
        raise HTTPException(status_code=404, detail='Account not found')

    # Balance check for debits
    if tx_data.transaction_type == 'debit':
        if account.balance < tx_data.amount:
            raise HTTPException(status_code=400, detail='Insufficient funds')

    # Create transaction (SQLAlchemy ORM = parameterized queries = no SQLi)
    tx = Transaction(
        account_id=tx_data.account_id,
        transaction_type=tx_data.transaction_type,
        amount=tx_data.amount,
        description=tx_data.description,
        merchant_category=tx_data.merchant_category,
    )
    db.add(tx)

    # Update balance
    if tx_data.transaction_type == 'credit':
        account.balance += tx_data.amount
    else:
        account.balance -= tx_data.amount

    db.commit()
    db.refresh(tx)

    # Async fraud check via Lambda
    _invoke_fraud_check(str(tx.id), tx_data)

    logger.info('transaction_created',
        transaction_id=str(tx.id),
        account_id=tx_data.account_id,
        type=tx_data.transaction_type,
        amount=str(tx_data.amount),
        user_id=current_user['sub']
    )

    return {'transaction_id': str(tx.id), 'status': 'completed'}

def _invoke_fraud_check(tx_id: str, tx_data: TransactionCreate):
    """Invoke fraud detection Lambda asynchronously (non-blocking)."""
    try:
        lambda_client = boto3.client('lambda')
        lambda_client.invoke(
            FunctionName='securebankapp-fraud-detection',
            InvocationType='Event',  # Async -- don't wait for response
            Payload=json.dumps({
                'transaction_id': tx_id,
                'amount': str(tx_data.amount),
                'merchant_category': tx_data.merchant_category,
            }).encode(),
        )
    except Exception as e:
        # Don't fail the transaction if fraud check fails
        logger.warning('fraud_check_failed', error=str(e))

# lambda/fraud_detection.py
"""
Fraud Detection Lambda Function
- Triggered async from transaction creation
- Rule-based scoring
- Updates fraud_score in RDS
- Sends SNS alert if score >= 0.8
"""
import json, boto3, psycopg2, os, logging
from datetime import datetime
from decimal import Decimal

logger = logging.getLogger()
logger.setLevel(logging.INFO)

HIGH_RISK_CATEGORIES = {
    'gambling', 'crypto_exchange', 'wire_transfer',
    'cash_advance', 'money_services'
}

def get_db_connection():
    """Get DB connection using Secrets Manager. Uses DB_SECRET_ID env var."""
    sm = boto3.client('secretsmanager')
    secret = json.loads(
        sm.get_secret_value(SecretId=os.environ['DB_SECRET_ID'])['SecretString']
    )
    return psycopg2.connect(
        host=os.environ['DB_HOST'],
        database='bankdb',
        user=secret['username'],
        password=secret['password'],
        connect_timeout=5,
        sslmode='require',
    )

def calculate_fraud_score(transaction_id: str, amount: Decimal,
                           merchant_category: str, conn) -> float:
    """Rule-based fraud scoring (0.0 = safe, 1.0 = fraud)."""
    score = 0.0
    features = {}

    with conn.cursor() as cur:
        # Feature 1: Amount vs user's 90-day average
        cur.execute('''
            SELECT AVG(t.amount), STDDEV(t.amount), COUNT(*)
            FROM transactions t
            JOIN accounts a ON t.account_id = a.id
            JOIN accounts a2 ON a2.user_id = a.user_id
            WHERE a2.id = (SELECT account_id FROM transactions WHERE id = %s)
              AND t.created_at > NOW() - INTERVAL '90 days'
              AND t.id != %s
        ''', (transaction_id, transaction_id))
        row = cur.fetchone()
        avg_amount, stddev_amount, count = row if row else (0, 0, 0)

        if avg_amount and stddev_amount and stddev_amount > 0:
            z_score = abs((float(amount) - float(avg_amount)) / float(stddev_amount))
            features['amount_z_score'] = z_score
            if z_score > 3:   score += 0.40
            elif z_score > 2: score += 0.20

        # Feature 2: Velocity — too many transactions in 1 hour
        cur.execute('''
            SELECT COUNT(*) FROM transactions t
            JOIN accounts a ON t.account_id = a.id
            WHERE a.user_id = (SELECT a2.user_id FROM transactions t2
                               JOIN accounts a2 ON t2.account_id = a2.id
                               WHERE t2.id = %s)
              AND t.created_at > NOW() - INTERVAL '1 hour'
        ''', (transaction_id,))
        tx_count_1hr = cur.fetchone()[0]
        features['tx_count_1hr'] = tx_count_1hr
        if tx_count_1hr > 10: score += 0.30
        elif tx_count_1hr > 5: score += 0.15

    # Feature 3: High-risk merchant category
    if merchant_category and merchant_category.lower() in HIGH_RISK_CATEGORIES:
        score += 0.25
        features['high_risk_category'] = True

    # Feature 4: Large round amount
    if float(amount) > 5000 and float(amount) % 1000 == 0:
        score += 0.10
        features['round_amount'] = True

    final_score = min(score, 1.0)

    logger.info(json.dumps({
        'event': 'fraud_score_calculated',
        'transaction_id': transaction_id,
        'score': final_score,
        'features': features
    }))

    return final_score

def lambda_handler(event, context):
    transaction_id    = event['transaction_id']
    amount            = Decimal(event['amount'])
    merchant_category = event.get('merchant_category', '')

    conn = None
    try:
        conn = get_db_connection()
        score = calculate_fraud_score(transaction_id, amount, merchant_category, conn)

        # Update fraud score in DB
        with conn.cursor() as cur:
            cur.execute(
                'UPDATE transactions SET fraud_score = %s WHERE id = %s',
                (score, transaction_id)
            )
        conn.commit()

        # Alert if high fraud score
        if score >= 0.8:
            sns = boto3.client('sns')
            sns.publish(
                TopicArn=os.environ['FRAUD_ALERT_TOPIC_ARN'],
                Subject=f'FRAUD ALERT: Transaction {transaction_id}',
                Message=json.dumps({
                    'transaction_id': transaction_id,
                    'fraud_score': score,
                    'amount': str(amount),
                    'merchant_category': merchant_category,
                }),
            )
            logger.warning(f'Fraud alert sent for transaction {transaction_id} score={score}')

        return {'statusCode': 200, 'fraud_score': score}

    except Exception as e:
        logger.error(json.dumps({
            'event': 'fraud_detection_error',
            'transaction_id': transaction_id,
            'error': str(e)
        }))
        raise
    finally:
        if conn:
            conn.close()

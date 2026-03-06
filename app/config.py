import json, boto3, os
from functools import lru_cache

@lru_cache()
def get_settings():
    """Fetch config from environment + AWS Secrets Manager."""
    region = os.getenv('AWS_REGION', 'us-east-1')
    sm = boto3.client('secretsmanager', region_name=region)

    # Get DB credentials using full ARN
    db_secret = json.loads(
        sm.get_secret_value(
            SecretId='arn:aws:secretsmanager:us-east-1:608283508247:secret:securebankapp/db-password-v2-wGlujZ'
        )['SecretString']
    )

    # Get JWT secret using full ARN
    jwt_secret = sm.get_secret_value(
        SecretId='arn:aws:secretsmanager:us-east-1:608283508247:secret:securebankapp/jwt-secret-v2-mrLrAR'
    )['SecretString']

    return {
        'DB_HOST': os.getenv('DB_HOST', ''),
        'DB_NAME': os.getenv('DB_NAME', 'bankdb'),
        'DB_USER': db_secret['username'],
        'DB_PASSWORD': db_secret['password'],
        'JWT_SECRET': jwt_secret,
        'JWT_ALGORITHM': 'HS256',
        'JWT_EXPIRE_MINUTES': int(os.getenv('JWT_EXPIRE_MINUTES', '30')),
        'APP_ENV': os.getenv('APP_ENV', 'production'),
    }
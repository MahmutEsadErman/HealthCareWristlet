import os
from datetime import timedelta

class Config:
    SECRET_KEY = os.environ.get('SECRET_KEY') or 'dev-secret-key-change-this-in-prod'
    SQLALCHEMY_DATABASE_URI = os.environ.get('DATABASE_URL') or 'sqlite:///health.db'
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    JWT_SECRET_KEY = os.environ.get('JWT_SECRET_KEY') or 'jwt-secret-key-change-this-in-prod'
    
    # JWT Token süresi - sağlık izleme uygulaması için 7 gün
    JWT_ACCESS_TOKEN_EXPIRES = timedelta(days=7)

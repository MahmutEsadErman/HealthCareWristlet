from flask_sqlalchemy import SQLAlchemy
from datetime import datetime, timezone

db = SQLAlchemy()

class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    password_hash = db.Column(db.String(128), nullable=False)
    user_type = db.Column(db.String(20), nullable=False) # 'caregiver' or 'patient'
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))
    
    # Relationships
    patient_profile = db.relationship('Patient', backref='user', uselist=False, lazy=True, foreign_keys='Patient.user_id')
    alerts = db.relationship('Alert', backref='user', lazy=True)
    imu_data = db.relationship('IMUData', backref='user', lazy=True)
    heart_rates = db.relationship('HeartRate', backref='user', lazy=True)

    def __repr__(self):
        return f'<User {self.username}>'

class Patient(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    
    # Thresholds
    min_hr = db.Column(db.Integer, default=40)
    max_hr = db.Column(db.Integer, default=120)
    inactivity_limit_minutes = db.Column(db.Integer, default=30)
    
    def to_dict(self):
        return {
            'id': self.id,
            'user_id': self.user_id,
            'min_hr': self.min_hr,
            'max_hr': self.max_hr,
            'inactivity_limit_minutes': self.inactivity_limit_minutes
        }

class IMUData(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    timestamp = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))
    # Accelerometer
    x_axis = db.Column(db.Float, nullable=False)
    y_axis = db.Column(db.Float, nullable=False)
    z_axis = db.Column(db.Float, nullable=False)
    # Gyroscope
    gx = db.Column(db.Float, nullable=True)
    gy = db.Column(db.Float, nullable=True)
    gz = db.Column(db.Float, nullable=True)

class HeartRate(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    timestamp = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))
    value = db.Column(db.Float, nullable=False)

class Alert(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False) # The patient who generated the alert
    type = db.Column(db.String(20), nullable=False) # FALL, INACTIVITY, HR_HIGH, HR_LOW, BUTTON
    message = db.Column(db.String(200), nullable=False)
    timestamp = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))
    is_resolved = db.Column(db.Boolean, default=False)

    def to_dict(self):
        return {
            'id': self.id,
            'user_id': self.user_id,
            'type': self.type,
            'message': self.message,
            'timestamp': self.timestamp.isoformat(),
            'is_resolved': self.is_resolved
        }

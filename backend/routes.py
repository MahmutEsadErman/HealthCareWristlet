from flask import Blueprint, request, jsonify
from flask_jwt_extended import create_access_token, jwt_required, get_jwt_identity
from werkzeug.security import generate_password_hash, check_password_hash
from models import db, User, Patient, IMUData, HeartRate, Alert
from datetime import datetime, timedelta, timezone

api = Blueprint('api', __name__)

# Minimum spacing between two alerts of the same type for a user
ALERT_COOLDOWN = timedelta(minutes=3)


def should_create_alert(user_id: int, alert_type: str, timestamp: datetime) -> bool:
    """
    Avoid spamming identical alerts by skipping new ones when there is already
    an unresolved alert of the same type or a very recent one within the
    cooldown window.
    """
    existing_unresolved = Alert.query.filter_by(
        user_id=user_id, type=alert_type, is_resolved=False
    ).first()
    if existing_unresolved:
        return False

    recent_alert = (
        Alert.query.filter(Alert.user_id == user_id, Alert.type == alert_type)
        .order_by(Alert.timestamp.desc())
        .first()
    )
    if recent_alert:
        recent_ts = recent_alert.timestamp
        if recent_ts.tzinfo is None:
            recent_ts = recent_ts.replace(tzinfo=timezone.utc)
        if (timestamp - recent_ts) < ALERT_COOLDOWN:
            return False

    return True

@api.route('/')
def index():
    return jsonify({'message': 'Welcome to the Health Monitoring API!'}), 200

@api.route('/test', methods=['GET', 'POST'])
def test():
    print("=== TEST ENDPOINT HIT ===")
    print(f"Method: {request.method}")
    print(f"Headers: {dict(request.headers)}")
    if request.method == 'POST':
        print(f"Data: {request.get_json()}")
    return jsonify({'message': 'Test successful', 'method': request.method}), 200

@api.route('/auth/register', methods=['POST'])
def register():
    print("=== REGISTER REQUEST RECEIVED ===")
    data = request.get_json()
    print(f"Request data: {data}")

    username = data.get('username')
    password = data.get('password')
    user_type = data.get('user_type') # 'caregiver' or 'patient'

    print(f"Username: {username}, UserType: {user_type}")

    if not username or not password or not user_type:
        print("ERROR: Missing required fields")
        return jsonify({'message': 'Username, password, and user_type required'}), 400

    if user_type not in ['caregiver', 'patient']:
        print(f"ERROR: Invalid user_type: {user_type}")
        return jsonify({'message': 'Invalid user_type'}), 400

    if User.query.filter_by(username=username).first():
        print(f"ERROR: Username already exists: {username}")
        return jsonify({'message': 'Username already exists'}), 400

    print("Creating new user...")
    hashed_password = generate_password_hash(password)
    new_user = User(username=username, password_hash=hashed_password, user_type=user_type)
    db.session.add(new_user)
    db.session.commit()
    print(f"User created with ID: {new_user.id}")

    if user_type == 'patient':
        # Create a Patient profile
        print("Creating patient profile...")
        new_patient = Patient(user_id=new_user.id)
        db.session.add(new_patient)
        db.session.commit()
        print("Patient profile created")

    print("=== REGISTER SUCCESS ===")
    return jsonify({'message': 'User created successfully', 'user_id': new_user.id}), 201

@api.route('/auth/login', methods=['POST'])
def login():
    print("=== LOGIN REQUEST RECEIVED ===")
    data = request.get_json()
    print(f"Request data: {data}")

    username = data.get('username')
    password = data.get('password')

    user = User.query.filter_by(username=username).first()

    if user and check_password_hash(user.password_hash, password):
        print(f"LOGIN SUCCESS - User: {username}, ID: {user.id}, Type: {user.user_type}")
        access_token = create_access_token(identity=str(user.id))
        return jsonify({'access_token': access_token, 'user_type': user.user_type, 'user_id': user.id}), 200

    print(f"LOGIN FAILED - Invalid credentials for username: {username}")
    return jsonify({'message': 'Invalid credentials'}), 401

# --- Wearable Data Endpoints ---

@api.route('/api/wearable/heart_rate', methods=['POST'])
@jwt_required()
def receive_heart_rate():
    current_user_id = get_jwt_identity()
    user_id = int(current_user_id)
    
    data = request.get_json()
    value = data.get('value')
    timestamp_str = data.get('timestamp')

    if value is None:
        return jsonify({'message': 'Value required'}), 400

    patient = Patient.query.filter_by(user_id=user_id).first()
    if not patient:
         return jsonify({'message': 'Patient not found'}), 404

    timestamp = datetime.now(timezone.utc)
    if timestamp_str:
        try:
            timestamp = datetime.fromisoformat(timestamp_str)
        except ValueError:
            pass

    new_hr = HeartRate(user_id=user_id, value=value, timestamp=timestamp)
    db.session.add(new_hr)
    
    # Check HR Thresholds
    if value < patient.min_hr:
        if should_create_alert(user_id, 'HR_LOW', timestamp):
            alert = Alert(user_id=user_id, type='HR_LOW', message=f'Heart rate low: {value}', timestamp=timestamp)
            db.session.add(alert)
    elif value > patient.max_hr:
        if should_create_alert(user_id, 'HR_HIGH', timestamp):
            alert = Alert(user_id=user_id, type='HR_HIGH', message=f'Heart rate high: {value}', timestamp=timestamp)
            db.session.add(alert)

    db.session.commit()
    return jsonify({'message': 'Heart rate data processed'}), 201

@api.route('/api/wearable/imu', methods=['POST'])
@jwt_required()
def receive_imu():
    current_user_id = get_jwt_identity()
    user_id = int(current_user_id)

    data = request.get_json()
    x = data.get('x_axis')
    y = data.get('y_axis')
    z = data.get('z_axis')
    gx = data.get('gx')
    gy = data.get('gy')
    gz = data.get('gz')
    timestamp_str = data.get('timestamp')

    if x is None or y is None or z is None:
        return jsonify({'message': 'Accelerometer data required'}), 400

    patient = Patient.query.filter_by(user_id=user_id).first()
    if not patient:
         return jsonify({'message': 'Patient not found'}), 404

    timestamp = datetime.now(timezone.utc)
    if timestamp_str:
        try:
            timestamp = datetime.fromisoformat(timestamp_str)
        except ValueError:
            pass

    new_imu = IMUData(
        user_id=user_id, 
        x_axis=x, y_axis=y, z_axis=z, 
        gx=gx, gy=gy, gz=gz,
        timestamp=timestamp
    )
    db.session.add(new_imu)

    # Check Inactivity
    limit_time = timestamp - timedelta(minutes=patient.inactivity_limit_minutes)
    recent_records = IMUData.query.filter(IMUData.user_id == user_id, IMUData.timestamp >= limit_time).all()
    
    if recent_records:
        first_record_in_window = recent_records[0]
        record_ts = first_record_in_window.timestamp
        if record_ts.tzinfo is None:
            record_ts = record_ts.replace(tzinfo=timezone.utc)
            
        if (timestamp - record_ts).total_seconds() / 60 >= patient.inactivity_limit_minutes:
                has_movement = False
                # Hareket eşiği: değişim > 1.0 ise hareket var sayılır
                # (sensör verisi gürültülü olduğu için düşük değerler filtrelenir)
                MOTION_THRESHOLD = 1.0
                for record in recent_records:
                    if abs(record.x_axis - x) > MOTION_THRESHOLD or abs(record.y_axis - y) > MOTION_THRESHOLD or abs(record.z_axis - z) > MOTION_THRESHOLD:
                        has_movement = True
                        break
                
                if not has_movement:
                    existing_alert = Alert.query.filter_by(user_id=user_id, type='INACTIVITY', is_resolved=False).first()
                    if not existing_alert:
                        alert = Alert(user_id=user_id, type='INACTIVITY', message='Patient inactive', timestamp=timestamp)
                        db.session.add(alert)

    db.session.commit()
    return jsonify({'message': 'IMU data processed'}), 201

@api.route('/api/wearable/button', methods=['POST'])
@jwt_required()
def receive_button():
    current_user_id = get_jwt_identity()
    user_id = int(current_user_id)

    data = request.get_json()
    panic = data.get('panic_button_status')
    timestamp_str = data.get('timestamp')

    if panic is None:
        return jsonify({'message': 'Status required'}), 400

    if panic:
        timestamp = datetime.now(timezone.utc)
        if timestamp_str:
            try:
                timestamp = datetime.fromisoformat(timestamp_str)
            except ValueError:
                pass
        
        alert = Alert(user_id=user_id, type='BUTTON', message='Panic button pressed', timestamp=timestamp)
        db.session.add(alert)
        db.session.commit()

    return jsonify({'message': 'Button status processed'}), 201


@api.route('/api/wearable/inactivity', methods=['POST'])
@jwt_required()
def receive_inactivity():
    """
    Receive inactivity alerts from ESP32 wristlet.
    Creates an INACTIVITY alert that caregivers can see.
    """
    current_user_id = get_jwt_identity()
    user_id = int(current_user_id)

    data = request.get_json()
    inactivity_detected = data.get('inactivity_detected')
    timestamp_str = data.get('timestamp')

    if not inactivity_detected:
        return jsonify({'message': 'No inactivity detected'}), 200

    timestamp = datetime.now(timezone.utc)
    if timestamp_str:
        try:
            timestamp = datetime.fromisoformat(timestamp_str)
        except ValueError:
            pass

    # Check if we should create the alert (avoid spam)
    if should_create_alert(user_id, 'INACTIVITY', timestamp):
        alert = Alert(
            user_id=user_id, 
            type='INACTIVITY', 
            message='Patient inactivity detected by wristlet', 
            timestamp=timestamp
        )
        db.session.add(alert)
        db.session.commit()
        print(f"[INACTIVITY] Alert created for user {user_id}")
        return jsonify({'message': 'Inactivity alert created'}), 201
    else:
        print(f"[INACTIVITY] Alert skipped (cooldown) for user {user_id}")
        return jsonify({'message': 'Inactivity already reported recently'}), 200


@api.route('/api/wearable/fall', methods=['POST'])
@jwt_required()
def receive_fall():
    """
    Receive fall detections from the wearable. Expects:
    {
      "probability": float (0-1),
      "bpm": float (optional),
      "timestamp": iso string (optional)
    }
    """
    current_user_id = get_jwt_identity()
    user_id = int(current_user_id)

    data = request.get_json()
    probability = data.get('probability')
    bpm = data.get('bpm')
    timestamp_str = data.get('timestamp')

    if probability is None:
        return jsonify({'message': 'Probability required'}), 400

    timestamp = datetime.now(timezone.utc)
    if timestamp_str:
        try:
            timestamp = datetime.fromisoformat(timestamp_str)
        except ValueError:
            pass

    if should_create_alert(user_id, 'FALL', timestamp):
        message = f'Fall detected (p={probability:.2f}'
        if bpm is not None:
            message += f', bpm={bpm}'
        message += ')'
        alert = Alert(
            user_id=user_id,
            type='FALL',
            message=message,
            timestamp=timestamp
        )
        db.session.add(alert)
        db.session.commit()
        return jsonify({'message': 'Fall alert created'}), 201

    return jsonify({'message': 'Fall already reported recently'}), 200

# --- Caregiver/Patient Endpoints ---

@api.route('/api/patients/<int:patient_id>/thresholds', methods=['PUT'])
@jwt_required()
def update_thresholds(patient_id):
    current_user_id = get_jwt_identity()
    # Any caregiver can update thresholds now
    
    data = request.get_json()
    patient = Patient.query.filter_by(user_id=patient_id).first()
    
    if not patient:
        return jsonify({'message': 'Patient not found'}), 404

    if 'min_hr' in data:
        patient.min_hr = data['min_hr']
    if 'max_hr' in data:
        patient.max_hr = data['max_hr']
    if 'inactivity_limit_minutes' in data:
        patient.inactivity_limit_minutes = data['inactivity_limit_minutes']
    
    db.session.commit()
    return jsonify({'message': 'Thresholds updated', 'patient': patient.to_dict()}), 200

@api.route('/api/alerts', methods=['GET'])
@jwt_required()
def get_alerts():
    current_user_id = get_jwt_identity()
    user = db.session.get(User, current_user_id)
    
    if user.user_type == 'caregiver':
        # Caregivers see ALL alerts
        alerts = Alert.query.order_by(Alert.timestamp.desc()).all()
    else:
        # Patient sees their own alerts
        alerts = Alert.query.filter_by(user_id=user.id).order_by(Alert.timestamp.desc()).all()
        
    return jsonify([alert.to_dict() for alert in alerts]), 200

@api.route('/api/patients', methods=['GET'])
@jwt_required()
def get_patients():
    current_user_id = get_jwt_identity()
    user = db.session.get(User, current_user_id)
    
    if user.user_type != 'caregiver':
        return jsonify({'message': 'Access denied'}), 403
        
    # Caregivers see ALL patients
    patients = Patient.query.all()
    result = []
    for p in patients:
        p_user = db.session.get(User, p.user_id)
        p_dict = p.to_dict()
        p_dict['username'] = p_user.username
        result.append(p_dict)
        
    return jsonify(result), 200

@api.route('/api/alerts/<int:alert_id>/resolve', methods=['PUT'])
@jwt_required()
def resolve_alert(alert_id):
    alert = db.session.get(Alert, alert_id)
    if not alert:
        return jsonify({'message': 'Alert not found'}), 404
        
    alert.is_resolved = True
    db.session.commit()
    return jsonify({'message': 'Alert resolved'}), 200

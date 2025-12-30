import unittest
import json
from app import create_app, db
from models import User, Patient, Alert, IMUData
from datetime import datetime, timedelta, timezone

class HealthMonitoringTestCase(unittest.TestCase):
    def setUp(self):
        self.app = create_app()
        self.app.config['TESTING'] = True
        self.app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///:memory:'
        self.client = self.app.test_client()
        
        with self.app.app_context():
            db.create_all()

    def tearDown(self):
        with self.app.app_context():
            db.session.remove()
            db.drop_all()

    def register_user(self, username, password, user_type):
        data = {
            'username': username,
            'password': password,
            'user_type': user_type
        }
        return self.client.post('/auth/register', json=data)

    def login_user(self, username, password):
        return self.client.post('/auth/login', json={
            'username': username,
            'password': password
        })

    def test_full_flow(self):
        # 1. Register Caregiver
        res = self.register_user('caregiver1', 'pass', 'caregiver')
        self.assertEqual(res.status_code, 201)

        # 2. Register Patient (No link to caregiver)
        res = self.register_user('patient1', 'pass', 'patient')
        self.assertEqual(res.status_code, 201)
        patient_user_id = res.json['user_id']

        # 3. Login as Caregiver
        res = self.login_user('caregiver1', 'pass')
        self.assertEqual(res.status_code, 200)
        caregiver_token = res.json['access_token']
        caregiver_headers = {'Authorization': f'Bearer {caregiver_token}'}

        # 4. Update Patient Thresholds (Global access)
        res = self.client.put(f'/api/patients/{patient_user_id}/thresholds', 
                              json={'min_hr': 50, 'max_hr': 100},
                              headers=caregiver_headers)
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json['patient']['min_hr'], 50)

        # 5. Login as Patient to get token for wearable data
        res = self.login_user('patient1', 'pass')
        self.assertEqual(res.status_code, 200)
        patient_token = res.json['access_token']
        patient_headers = {'Authorization': f'Bearer {patient_token}'}

        # 6. Send Normal Heart Rate Data (HR 70) - No Alert
        data_hr = {
            'value': 70
        }
        res = self.client.post('/api/wearable/heart_rate', json=data_hr, headers=patient_headers)
        self.assertEqual(res.status_code, 201)

        # Verify no alerts
        res = self.client.get('/api/alerts', headers=caregiver_headers)
        self.assertEqual(len(res.json), 0)

        # 7. Send Abnormal Heart Rate Data (HR 120) - High HR Alert
        data_hr['value'] = 120
        res = self.client.post('/api/wearable/heart_rate', json=data_hr, headers=patient_headers)
        self.assertEqual(res.status_code, 201)

        # Verify Alert
        res = self.client.get('/api/alerts', headers=caregiver_headers)
        self.assertEqual(len(res.json), 1)
        self.assertEqual(res.json[0]['type'], 'HR_HIGH')
        alert_id = res.json[0]['id']

        # 8. Resolve Alert
        res = self.client.put(f'/api/alerts/{alert_id}/resolve', headers=caregiver_headers)
        self.assertEqual(res.status_code, 200)

        # 9. Panic Button
        data_btn = {
            'panic_button_status': True
        }
        res = self.client.post('/api/wearable/button', json=data_btn, headers=patient_headers)
        self.assertEqual(res.status_code, 201)
        
        res = self.client.get('/api/alerts', headers=caregiver_headers)
        # Should be 2 alerts now (one resolved, one new)
        self.assertEqual(len(res.json), 2)
        self.assertEqual(res.json[0]['type'], 'BUTTON')

        # 10. Inactivity Alert
        # Simulate inactivity: Send data with same IMU values for > inactivity_limit
        # First, set inactivity limit to 1 minute for testing
        res = self.client.put(f'/api/patients/{patient_user_id}/thresholds', 
                              json={'inactivity_limit_minutes': 1},
                              headers=caregiver_headers)
        
        # Clear previous IMU data to avoid interference
        with self.app.app_context():
            IMUData.query.filter_by(user_id=patient_user_id).delete()
            db.session.commit()
        
        # Send initial data point
        # We need data covering the last minute. 
        # Define exact timestamps
        now = datetime.now(timezone.utc)
        t_start = now - timedelta(seconds=60)
        t_mid = now - timedelta(seconds=30)
        
        with self.app.app_context():
            # Manually insert old data
            imu1 = IMUData(user_id=patient_user_id, x_axis=0.0, y_axis=0.0, z_axis=0.0, gx=0.0, gy=0.0, gz=0.0, timestamp=t_start)
            imu2 = IMUData(user_id=patient_user_id, x_axis=0.0, y_axis=0.0, z_axis=0.0, gx=0.0, gy=0.0, gz=0.0, timestamp=t_mid)
            db.session.add(imu1)
            db.session.add(imu2)
            db.session.commit()

        # Send new data point (no movement) with explicit timestamp
        data_imu = {
            'x_axis': 0.0, 'y_axis': 0.0, 'z_axis': 0.0,
            'gx': 0.0, 'gy': 0.0, 'gz': 0.0,
            'timestamp': now.isoformat()
        }
        res = self.client.post('/api/wearable/imu', json=data_imu, headers=patient_headers)
        self.assertEqual(res.status_code, 201)

        # Verify Inactivity Alert
        res = self.client.get('/api/alerts', headers=caregiver_headers)
        types = [a['type'] for a in res.json]
        self.assertIn('INACTIVITY', types)

if __name__ == '__main__':
    unittest.main()

import requests
import time
from datetime import datetime, timezone

BASE_URL = 'http://127.0.0.1:5000'

def test_flow():
    print("Starting API Test...")

    # 1. Register Caregiver
    print("\n1. Testing Caregiver Registration...")
    caregiver_username = f"caregiver_{int(time.time())}"
    password = "securepassword"
    reg_response = requests.post(f"{BASE_URL}/auth/register", json={
        "username": caregiver_username,
        "password": password,
        "user_type": "caregiver"
    })
    print(f"Register Status: {reg_response.status_code}")
    print(f"Register Response: {reg_response.json()}")
    if reg_response.status_code != 201:
        print("Caregiver Registration failed!")
        return

    # 2. Register Patient
    print("\n2. Testing Patient Registration...")
    patient_username = f"patient_{int(time.time())}"
    reg_response = requests.post(f"{BASE_URL}/auth/register", json={
        "username": patient_username,
        "password": password,
        "user_type": "patient"
    })
    print(f"Register Status: {reg_response.status_code}")
    print(f"Register Response: {reg_response.json()}")
    if reg_response.status_code != 201:
        print("Patient Registration failed!")
        return
    
    patient_user_id = reg_response.json().get('user_id')

    # 3. Login Patient
    print("\n3. Testing Patient Login...")
    login_response = requests.post(f"{BASE_URL}/auth/login", json={
        "username": patient_username,
        "password": password
    })
    print(f"Login Status: {login_response.status_code}")
    if login_response.status_code != 200:
        print("Patient Login failed!")
        return
    
    patient_token = login_response.json().get('access_token')
    patient_headers = {"Authorization": f"Bearer {patient_token}"}
    print("Got Patient Access Token")

    # 4. Login Caregiver
    print("\n4. Testing Caregiver Login...")
    login_response = requests.post(f"{BASE_URL}/auth/login", json={
        "username": caregiver_username,
        "password": password
    })
    print(f"Login Status: {login_response.status_code}")
    if login_response.status_code != 200:
        print("Caregiver Login failed!")
        return
    
    caregiver_token = login_response.json().get('access_token')
    caregiver_headers = {"Authorization": f"Bearer {caregiver_token}"}
    print("Got Caregiver Access Token")

    # 5. Send Heart Rate Data
    print("\n5. Testing Send Heart Rate...")
    hr_data = {
        "value": 80,
        "timestamp": datetime.now(timezone.utc).isoformat()
    }
    hr_response = requests.post(f"{BASE_URL}/api/wearable/heart_rate", json=hr_data, headers=patient_headers)
    print(f"Send HR Status: {hr_response.status_code}")
    print(f"Send HR Response: {hr_response.json()}")

    # 6. Send IMU Data
    print("\n6. Testing Send IMU Data...")
    imu_data = {
        "x_axis": 0.1, "y_axis": 0.2, "z_axis": 9.8,
        "gx": 0.0, "gy": 0.0, "gz": 0.0,
        "timestamp": datetime.now(timezone.utc).isoformat()
    }
    imu_response = requests.post(f"{BASE_URL}/api/wearable/imu", json=imu_data, headers=patient_headers)
    print(f"Send IMU Status: {imu_response.status_code}")
    print(f"Send IMU Response: {imu_response.json()}")

    # 7. Send Panic Button
    print("\n7. Testing Send Panic Button...")
    btn_data = {
        "panic_button_status": True,
        "timestamp": datetime.now(timezone.utc).isoformat()
    }
    btn_response = requests.post(f"{BASE_URL}/api/wearable/button", json=btn_data, headers=patient_headers)
    print(f"Send Button Status: {btn_response.status_code}")
    print(f"Send Button Response: {btn_response.json()}")

    # 8. Caregiver Get Alerts
    print("\n8. Testing Caregiver Get Alerts...")
    alerts_response = requests.get(f"{BASE_URL}/api/alerts", headers=caregiver_headers)
    print(f"Get Alerts Status: {alerts_response.status_code}")
    print(f"Get Alerts Response: {alerts_response.json()}")

    # 9. Caregiver Get Patients
    print("\n9. Testing Caregiver Get Patients...")
    patients_response = requests.get(f"{BASE_URL}/api/patients", headers=caregiver_headers)
    print(f"Get Patients Status: {patients_response.status_code}")
    print(f"Get Patients Response: {patients_response.json()}")

if __name__ == "__main__":
    try:
        test_flow()
    except Exception as e:
        print(f"Test failed with error: {e}")

# Backend API Dokümantasyonu

Bu doküman, Sağlık Takip Sistemi'nin backend API'sini kullanacak olan Frontend (Flutter) geliştiricisi için hazırlanmıştır.

## Genel Bilgiler

- **Base URL**: `http://<SERVER_IP>:5000` (Localhost için `http://10.0.2.2:5000` Android emülatöründe, iOS için `http://127.0.0.1:5000`)
- **Authentication**: Çoğu endpoint `Authorization` header'ında **Bearer Token** (JWT) gerektirir.
  - Header formatı: `Authorization: Bearer <access_token>`
- **Veri Formatı**: Tüm istekler ve cevaplar `application/json` formatındadır.

## Flutter İçin İpuçları

1. **HTTP İstekleri**: `http` veya `dio` paketlerini kullanabilirsiniz. `dio` interceptor özelliği ile token'ı otomatik eklemek için daha kullanışlı olabilir.
2. **Token Saklama**: Login olduktan sonra gelen `access_token`'ı güvenli bir şekilde saklamak için `flutter_secure_storage` paketini kullanmanızı öneririm.
3. **Arka Plan Servisleri**: Giyilebilir cihazdan veri alıp sürekli API'ye gönderecekseniz, uygulamanın arka planda çalışabilmesi için `flutter_background_service` veya `workmanager` gibi paketlere ihtiyacınız olabilir.
4. **Hata Yönetimi**: API 4xx veya 5xx kodları döndüğünde kullanıcıya uygun mesajları göstermeyi unutmayın.

---

## Endpointler

### 1. Kimlik Doğrulama (Auth)

#### Kayıt Ol (Register)
Kullanıcı (Hasta veya Bakıcı) oluşturur.

- **URL**: `/auth/register`
- **Method**: `POST`
- **Body**:
  ```json
  {
    "username": "kullanici_adi",
    "password": "sifre",
    "user_type": "patient" // veya "caregiver"
  }
  ```
- **Response (201)**: `{"message": "User created successfully", "user_id": 1}`

#### Giriş Yap (Login)
Token almak için kullanılır. Bu token diğer isteklerde kullanılacaktır.

- **URL**: `/auth/login`
- **Method**: `POST`
- **Body**:
  ```json
  {
    "username": "kullanici_adi",
    "password": "sifre"
  }
  ```
- **Response (200)**:
  ```json
  {
    "access_token": "eyJ0eXAi...",
    "user_type": "patient", // veya "caregiver"
    "user_id": 1
  }
  ```

---

### 2. Giyilebilir Cihaz Verileri (Wearable Data)
**Önemli**: Bu endpointler sadece **Patient (Hasta)** girişi yapıldığında alınan token ile çalışır.

#### Nabız Verisi Gönder
- **URL**: `/api/wearable/heart_rate`
- **Method**: `POST`
- **Header**: `Authorization: Bearer <token>`
- **Body**:
  ```json
  {
    "value": 85, // Nabız değeri
    "timestamp": "2023-10-27T10:00:00+00:00" // Opsiyonel, ISO 8601 formatı
  }
  ```
- **Not**: Eğer nabız hastanın eşik değerlerinin dışındaysa otomatik olarak `HR_HIGH` veya `HR_LOW` alarmı oluşturulur.

#### IMU (İvmeölçer/Jiroskop) Verisi Gönder
- **URL**: `/api/wearable/imu`
- **Method**: `POST`
- **Header**: `Authorization: Bearer <token>`
- **Body**:
  ```json
  {
    "x_axis": 0.1,
    "y_axis": 0.2,
    "z_axis": 9.8,
    "gx": 0.0, // Jiroskop X
    "gy": 0.0, // Jiroskop Y
    "gz": 0.0, // Jiroskop Z
    "timestamp": "..." // Opsiyonel
  }
  ```
- **Not**: Sistem bu verileri analiz ederek hareketsizlik (`INACTIVITY`) durumunu kontrol eder.

#### Panik Butonu
- **URL**: `/api/wearable/button`
- **Method**: `POST`
- **Header**: `Authorization: Bearer <token>`
- **Body**:
  ```json
  {
    "panic_button_status": true,
    "timestamp": "..." // Opsiyonel
  }
  ```
- **Not**: `true` gönderildiğinde anında `BUTTON` alarmı oluşturulur.

---

### 3. Bakıcı İşlemleri (Caregiver Operations)
**Önemli**: Bu endpointler sadece **Caregiver (Bakıcı)** girişi yapıldığında alınan token ile çalışır. Bakıcılar tüm hastaları ve alarmları görebilir.

#### Hasta Listesini Getir
- **URL**: `/api/patients`
- **Method**: `GET`
- **Header**: `Authorization: Bearer <token>`
- **Response (200)**:
  ```json
  [
    {
      "id": 1,
      "user_id": 2,
      "username": "hasta_ahmet",
      "min_hr": 40,
      "max_hr": 120,
      "inactivity_limit_minutes": 30
    },
    ...
  ]
  ```

#### Alarmları Getir
- **URL**: `/api/alerts`
- **Method**: `GET`
- **Header**: `Authorization: Bearer <token>`
- **Response (200)**:
  ```json
  [
    {
      "id": 5,
      "user_id": 2,
      "type": "HR_HIGH",
      "message": "Heart rate high: 130",
      "timestamp": "...",
      "is_resolved": false
    },
    ...
  ]
  ```

#### Hasta Eşik Değerlerini Güncelle
- **URL**: `/api/patients/<patient_user_id>/thresholds`
- **Method**: `PUT`
- **Header**: `Authorization: Bearer <token>`
- **Body** (İstediğiniz alanları gönderebilirsiniz):
  ```json
  {
    "min_hr": 50,
    "max_hr": 110,
    "inactivity_limit_minutes": 45
  }
  ```

#### Alarmı Çözüldü Olarak İşaretle
- **URL**: `/api/alerts/<alert_id>/resolve`
- **Method**: `PUT`
- **Header**: `Authorization: Bearer <token>`
- **Response (200)**: `{"message": "Alert resolved"}`

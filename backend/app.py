from flask import Flask
from flask_jwt_extended import JWTManager
from config import Config
from models import db
from routes import api

def create_app():
    app = Flask(__name__)
    app.config.from_object(Config)

    db.init_app(app)
    JWTManager(app)

    app.register_blueprint(api)

    with app.app_context():
        db.create_all()

    return app

if __name__ == '__main__':
    app = create_app()
    # Host '0.0.0.0' allows access from other devices on the LAN
    app.run(host='0.0.0.0', port=5000, debug=True)

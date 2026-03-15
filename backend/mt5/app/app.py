import logging
import os
import time
from flask import Flask
from dotenv import load_dotenv
import MetaTrader5 as mt5
from flasgger import Swagger
from werkzeug.middleware.proxy_fix import ProxyFix
from swagger import swagger_config
# Import routes
from routes.health import health_bp
from routes.symbol import symbol_bp
from routes.data import data_bp
from routes.position import position_bp
from routes.order import order_bp
from routes.history import history_bp
from routes.error import error_bp

load_dotenv()
logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

app = Flask(__name__)
app.config['PREFERRED_URL_SCHEME'] = 'https'
swagger = Swagger(app, config=swagger_config)

# Register blueprints
app.register_blueprint(health_bp)
app.register_blueprint(symbol_bp)
app.register_blueprint(data_bp)
app.register_blueprint(position_bp)
app.register_blueprint(order_bp)
app.register_blueprint(history_bp)
app.register_blueprint(error_bp)

app.wsgi_app = ProxyFix(app.wsgi_app, x_proto=1, x_host=1)

if __name__ == '__main__':
    # Read broker credentials from env vars
    mt5_login = os.environ.get('MT5_LOGIN')
    mt5_password = os.environ.get('MT5_PASSWORD')
    mt5_server = os.environ.get('MT5_SERVER')

    # Retry MT5 initialization
    max_retries = 10
    retry_delay = 5
    for attempt in range(1, max_retries + 1):
        if mt5_login and mt5_password and mt5_server:
            result = mt5.initialize(
                login=int(mt5_login),
                password=mt5_password,
                server=mt5_server
            )
        else:
            result = mt5.initialize()

        if result:
            logger.info(f"MT5 initialized successfully on attempt {attempt}.")
            logger.info(f"MT5 version: {mt5.version()}")
            break
        logger.warning(f"MT5 initialization attempt {attempt}/{max_retries} failed. Retrying in {retry_delay}s...")
        time.sleep(retry_delay)
    else:
        logger.error("Failed to initialize MT5 after all retries. Starting API anyway.")

    port = int(os.environ.get('MT5_API_PORT', 5001))
    logger.info(f"Starting Flask API on port {port}.")
    app.run(host='0.0.0.0', port=port)

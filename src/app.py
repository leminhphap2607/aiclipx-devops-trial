from flask import Flask, request, jsonify
import os
import uuid
import logging
from datetime import datetime
from functools import wraps

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Middleware to add request ID and log requests
@app.before_request
def before_request():
    request.start_time = datetime.utcnow()
    request.request_id = request.headers.get('X-Request-ID', str(uuid.uuid4()))
    
    # Log incoming request
    logger.info(
        f"Request started: {request.method} {request.path} - "
        f"RequestID: {request.request_id}"
    )

@app.after_request
def after_request(response):
    # Calculate response time
    response_time = (datetime.utcnow() - request.start_time).total_seconds() * 1000
    
    # Add request ID to response headers
    response.headers['X-Request-ID'] = request.request_id
    
    # Log response
    logger.info(
        f"Request completed: {request.method} {request.path} - "
        f"Status: {response.status_code} - "
        f"ResponseTime: {response_time:.2f}ms - "
        f"RequestID: {request.request_id}"
    )
    
    return response

@app.route('/health')
def health():
    """Health check endpoint for load balancers and monitoring"""
    return jsonify({
        'status': 'healthy',
        'service': 'AiClipX API',
        'timestamp': datetime.utcnow().isoformat() + 'Z',
        'version': '1.0.0',
        'environment': os.getenv('NODE_ENV', 'development'),
        'branch': 'trials-devops',
        'request_id': request.request_id
    }), 200

@app.route('/')
def index():
    """Main endpoint"""
    return jsonify({
        'service': 'AiClipX API',
        'version': '1.0.0',
        'branch': 'trials-devops',
        'status': 'operational',
        'endpoints': {
            'health': '/health',
            'metrics': '/metrics',
            'info': '/info'
        },
        'documentation': 'https://docs.aiclipx.com',
        'request_id': request.request_id
    })

@app.route('/info')
def info():
    """Service information endpoint"""
    return jsonify({
        'service': 'AiClipX Video Processing API',
        'version': '1.0.0',
        'branch': 'trials-devops',
        'environment': os.getenv('NODE_ENV', 'development'),
        'region': os.getenv('AWS_REGION', 'local'),
        'uptime': get_uptime(),
        'request_id': request.request_id
    })

@app.route('/metrics')
def metrics():
    """Metrics endpoint (prometheus format)"""
    # This would typically connect to a metrics collector
    # For now, return basic metrics
    return jsonify({
        'status': 'success',
        'data': {
            'requests_total': 0,
            'requests_duration_seconds': 0,
            'memory_usage_bytes': 0,
            'cpu_usage_percent': 0
        },
        'request_id': request.request_id
    })

@app.errorhandler(404)
def not_found(error):
    return jsonify({
        'error': 'Not found',
        'message': 'The requested resource was not found',
        'path': request.path,
        'request_id': request.request_id
    }), 404

@app.errorhandler(500)
def internal_error(error):
    logger.error(f"Internal server error: {error}")
    return jsonify({
        'error': 'Internal server error',
        'message': 'An unexpected error occurred',
        'request_id': request.request_id
    }), 500

def get_uptime():
    """Calculate application uptime"""
    # This would track actual uptime
    # For simplicity, return a placeholder
    return "0 days, 0 hours, 0 minutes"

if __name__ == '__main__':
    # Get port from environment or default to 3000
    port = int(os.getenv('PORT', 3000))
    
    # Run Flask app
    app.run(
        host='0.0.0.0',
        port=port,
        debug=(os.getenv('NODE_ENV') == 'development')
    )
@app.route('/health')
def health():
    """Enhanced health check with system info"""
    import psutil
    import socket
    
    try:
        # Get system info
        cpu_percent = psutil.cpu_percent(interval=0.1)
        memory = psutil.virtual_memory()
        disk = psutil.disk_usage('/')
        
        return jsonify({
            'status': 'healthy',
            'service': 'AiClipX API',
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'version': '1.0.0',
            'environment': os.getenv('NODE_ENV', 'development'),
            'branch': 'trials-devops',
            'system': {
                'cpu_percent': cpu_percent,
                'memory_percent': memory.percent,
                'disk_percent': disk.percent,
                'hostname': socket.gethostname()
            },
            'request_id': request.request_id
        }), 200
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return jsonify({
            'status': 'degraded',
            'error': str(e),
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'request_id': request.request_id
        }), 503
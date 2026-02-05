import pytest
from app import app

@pytest.fixture
def client():
    """Create test client"""
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client

def test_health_endpoint(client):
    """Test health endpoint returns 200"""
    response = client.get('/health')
    assert response.status_code == 200
    assert b'healthy' in response.data

def test_root_endpoint(client):
    """Test root endpoint returns 200"""
    response = client.get('/')
    assert response.status_code == 200
    assert b'AiClipX' in response.data

def test_info_endpoint(client):
    """Test info endpoint returns 200"""
    response = client.get('/info')
    assert response.status_code == 200
    assert b'trials-devops' in response.data

def test_404_endpoint(client):
    """Test non-existent endpoint returns 404"""
    response = client.get('/nonexistent')
    assert response.status_code == 404
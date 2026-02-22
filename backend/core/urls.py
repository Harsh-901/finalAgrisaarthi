"""
AIISMS - Main URL Configuration
"""

from django.contrib import admin
from django.urls import path, include
from django.http import JsonResponse
from django.utils import timezone


def api_root(request):
    """API root endpoint with available routes"""
    return JsonResponse({
        'message': 'Welcome to AIISMS API - Voice-based Farmer Scheme Access',
        'version': '1.0.0',
        'endpoints': {
            'auth': '/api/auth/',
            'farmers': '/api/farmers/',
            'documents': '/api/documents/',
            'schemes': '/api/schemes/',
            'applications': '/api/applications/',
            'voice': '/api/voice/',
            'claims': '/api/claims/',
            'admin': '/admin/',
        }
    })


def health_check(request):
    """
    Lightweight health check endpoint.
    Used by Flutter app to wake up the Render dyno before auth flow.
    """
    return JsonResponse({
        'status': 'ok',
        'timestamp': timezone.now().isoformat(),
    })


urlpatterns = [
    path('', api_root, name='api-root'),
    path('api/health/', health_check, name='health-check'),
    path('admin/', admin.site.urls),
    
    # API Routes
    path('api/auth/', include('auth_app.urls')),
    path('api/farmers/', include('farmers.urls')),
    path('api/documents/', include('documents.urls')),
    path('api/schemes/', include('schemes.urls')),
    path('api/applications/', include('applications.urls')),
    path('api/voice/', include('voice.urls')),
    path('api/claims/', include('claims.urls')),
]

import socket

from django.shortcuts import render


def index(request):
    # The pod name (hostname) is shown on the page so you can see the
    # load balancing across pods and nodes when you refresh.
    return render(request, 'demo_site.html', {'pod_name': socket.gethostname()})

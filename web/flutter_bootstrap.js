{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: JSON.parse('{{flutter_service_worker_version}}'),
    timeoutMillis: 12000,
  },
});

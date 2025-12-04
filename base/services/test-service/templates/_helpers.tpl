{{- define "test-service.name" -}}
test-service
{{- end }}

{{- define "test-service.fullname" -}}
{{ printf "%s" (include "test-service.name" .) }}
{{- end }}

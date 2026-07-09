{{/*
Return the proper element image name
*/}}
{{- define "element.image" -}}
{{- include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) -}}
{{- end -}}

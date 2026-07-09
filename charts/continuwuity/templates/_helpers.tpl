{{/*
Return the proper continuwuity image name
*/}}
{{- define "continuwuity.image" -}}
{{- include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) -}}
{{- end -}}

{{/*
Return the PVC name
*/}}
{{- define "continuwuity.pvcName" -}}
{{- include "common.names.fullname" . -}}
{{- end -}}

{{/*
Expand the name of the chart.
*/}}
{{- define "real-time.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "real-time.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "real-time.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "real-time.labels" -}}
helm.sh/chart: {{ include "real-time.chart" . }}
{{ include "real-time.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "real-time.selectorLabels" -}}
app.kubernetes.io/name: {{ include "real-time.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "real-time.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "real-time.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Secret key base secret name
*/}}
{{- define "real-time.secretKeyBaseSecretName" -}}
{{- if .Values.secretKeyBase.existingSecret }}
{{- .Values.secretKeyBase.existingSecret }}
{{- else }}
{{- include "real-time.fullname" . }}-secret
{{- end }}
{{- end }}

{{/*
Redis secret name
*/}}
{{- define "real-time.redisSecretName" -}}
{{- if .Values.redis.existingSecret }}
{{- .Values.redis.existingSecret }}
{{- else }}
{{- include "real-time.fullname" . }}-redis
{{- end }}
{{- end }}

{{/*
RabbitMQ secret name
*/}}
{{- define "real-time.rabbitmqSecretName" -}}
{{- if .Values.rabbitmq.existingSecret }}
{{- .Values.rabbitmq.existingSecret }}
{{- else }}
{{- include "real-time.fullname" . }}-rabbitmq
{{- end }}
{{- end }}

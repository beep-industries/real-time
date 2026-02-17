defmodule Signaling.OfferRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field :session_id, 1, type: :uint64, json_name: "session_id"
  field :endpoint_id, 2, type: :uint64, json_name: "endpoint_id"
  field :offer_sdp, 3, type: :string, json_name: "offer_sdp"
  field :enable_transcription, 4, type: :bool, json_name: "enable_transcription"
  field :transcription_language, 5, type: :string, json_name: "transcription_language"
end

defmodule Signaling.OfferResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field :session_id, 1, type: :uint64, json_name: "session_id"
  field :endpoint_id, 2, type: :uint64, json_name: "endpoint_id"
  field :answer_sdp, 3, type: :string, json_name: "answer_sdp"
  field :error, 4, type: :string
end

defmodule Signaling.LeaveRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field :session_id, 1, type: :uint64, json_name: "session_id"
  field :endpoint_id, 2, type: :uint64, json_name: "endpoint_id"
end

defmodule Signaling.LeaveResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field :ok, 1, type: :bool
  field :error, 2, type: :string
end

defmodule Signaling.TranscriptionSubscription do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field :session_id, 1, type: :uint64, json_name: "session_id"
end

defmodule Signaling.TranscriptionUpdate do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field :session_id, 1, type: :uint64, json_name: "session_id"
  field :endpoint_id, 2, type: :uint64, json_name: "endpoint_id"
  field :text, 3, type: :string
  field :start_ms, 4, type: :uint64, json_name: "start_ms"
  field :end_ms, 5, type: :uint64, json_name: "end_ms"
end

defmodule Signaling.EnableTranscriptionRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field :session_id, 1, type: :uint64, json_name: "session_id"
  field :endpoint_id, 2, type: :uint64, json_name: "endpoint_id"
  field :language, 3, type: :string
  field :backend, 4, type: :string
  field :simul_streaming_addr, 5, type: :string, json_name: "simul_streaming_addr"
  field :openai_api_key, 6, type: :string, json_name: "openai_api_key"
  field :openai_base_url, 7, type: :string, json_name: "openai_base_url"
  field :openai_model, 8, type: :string, json_name: "openai_model"
end

defmodule Signaling.EnableTranscriptionResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field :ok, 1, type: :bool
  field :error, 2, type: :string
end

defmodule Signaling.DisableTranscriptionRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field :session_id, 1, type: :uint64, json_name: "session_id"
  field :endpoint_id, 2, type: :uint64, json_name: "endpoint_id"
end

defmodule Signaling.DisableTranscriptionResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field :ok, 1, type: :bool
  field :error, 2, type: :string
end

defmodule Signaling.Signaling.Service do
  @moduledoc false
  use GRPC.Service, name: "signaling.Signaling"

  rpc :Offer, Signaling.OfferRequest, Signaling.OfferResponse
  rpc :Leave, Signaling.LeaveRequest, Signaling.LeaveResponse
  rpc :EnableTranscription, Signaling.EnableTranscriptionRequest, Signaling.EnableTranscriptionResponse
  rpc :DisableTranscription, Signaling.DisableTranscriptionRequest, Signaling.DisableTranscriptionResponse
  rpc :SubscribeTranscription, Signaling.TranscriptionSubscription, stream(Signaling.TranscriptionUpdate)
end

defmodule Signaling.Signaling.Stub do
  @moduledoc false
  use GRPC.Stub, service: Signaling.Signaling.Service
end

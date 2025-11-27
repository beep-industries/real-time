defmodule Signaling.OfferRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field :session_id, 1, type: :uint64, json_name: "session_id"
  field :endpoint_id, 2, type: :uint64, json_name: "endpoint_id"
  field :offer_sdp, 3, type: :string, json_name: "offer_sdp"
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

defmodule Signaling.Signaling.Service do
  @moduledoc false
  use GRPC.Service, name: "signaling.Signaling"

  rpc :Offer, Signaling.OfferRequest, Signaling.OfferResponse
  rpc :Leave, Signaling.LeaveRequest, Signaling.LeaveResponse
end

defmodule Signaling.Signaling.Stub do
  @moduledoc false
  use GRPC.Stub, service: Signaling.Signaling.Service
end

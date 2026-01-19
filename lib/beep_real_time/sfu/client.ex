defmodule BeepRealTime.SFU.Client do
  @moduledoc """
  gRPC client for the SFU Signaling service.

  Connects directly to the SFU at 127.0.0.1:50051 (default) using the
  following proto3 contract (package: signaling):

    - rpc Offer(OfferRequest) returns (OfferResponse)
    - rpc Leave(LeaveRequest) returns (LeaveResponse)

  Configure target via env SFU_GRPC_ADDR (default: 127.0.0.1:50051).
  """

  alias Signaling.{OfferRequest, LeaveRequest}
  alias Signaling.Signaling.Stub, as: SignalingStub
  require Logger

  @type session_id :: non_neg_integer()
  @type endpoint_id :: non_neg_integer()

  @spec offer(session_id, endpoint_id, String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def offer(session_id, endpoint_id, offer_sdp)
      when is_integer(session_id) and is_integer(endpoint_id) and is_binary(offer_sdp) do
    with {:ok, channel} <- connect(),
         norm_offer <- normalize_offer_sdp(offer_sdp),
         req <- %OfferRequest{session_id: session_id, endpoint_id: endpoint_id, offer_sdp: norm_offer},
         {:ok, resp} <- SignalingStub.offer(channel, req, timeout: 15_000) do
      case resp do
        %{error: error} when is_binary(error) and error != "" -> {:error, error}
        %{answer_sdp: answer} when is_binary(answer) -> {:ok, answer}
        _ -> {:error, "invalid_response"}
      end
    else
      {:error, :econnrefused} -> {:error, "sfu_unreachable"}
      {:error, %GRPC.RPCError{status: _s, message: m}} -> {:error, format_grpc_error(m)}
      {:error, other} -> {:error, format_grpc_error(other)}
    end
  end

  @spec leave(session_id, endpoint_id) :: :ok | {:error, String.t()}
  def leave(session_id, endpoint_id) when is_integer(session_id) and is_integer(endpoint_id) do
    with {:ok, channel} <- connect(),
         req <- %LeaveRequest{session_id: session_id, endpoint_id: endpoint_id},
         {:ok, resp} <- SignalingStub.leave(channel, req, timeout: 10_000) do
      case resp do
        %{ok: true} -> :ok
        %{ok: false, error: error} when is_binary(error) and error != "" -> {:error, error}
        _ -> {:error, "invalid_response"}
      end
    else
      {:error, :econnrefused} -> {:error, "sfu_unreachable"}
      {:error, %GRPC.RPCError{status: _s, message: m}} -> {:error, format_grpc_error(m)}
      {:error, other} -> {:error, format_grpc_error(other)}
    end
  end

  defp connect do
    addr = System.get_env("SFU_GRPC_ADDR") || "127.0.0.1:50051"
    # Use insecure channel to local SFU unless TLS is configured
    # Do not force the Gun adapter; use the default (Mint) to avoid
    # UndefinedFunctionError on GRPC.Adapter.Gun.connect/2 in some setups
    GRPC.Stub.connect(addr, cred: nil)
  rescue
    e ->
      Logger.error("SFU gRPC connect error: #{inspect(e)}")
      {:error, :connect_error}
  end

  defp format_grpc_error(%GRPC.RPCError{message: m}) do
    Logger.error("SFU gRPC RPCError: #{inspect(m)}")
    m || "grpc_error"
  end

  defp format_grpc_error(%{message: m}) when is_binary(m), do: m
  defp format_grpc_error(:timeout), do: "timeout"
  defp format_grpc_error(other) do
    Logger.error("SFU gRPC unknown error: #{inspect(other)}")
    "grpc_error: #{inspect(other)}"
  end

  # Ensures the offer SDP is encoded as a JSON string with shape
  #   {"sdp": "...", "type": "offer"}
  # If the incoming string is already JSON with required fields, it is returned as-is.
  # Otherwise, raw SDP text is wrapped and newlines normalized to CRLF as expected by many SFUs.
  defp normalize_offer_sdp(s) when is_binary(s) do
    case maybe_decode_json(s) do
      {:ok, %{"sdp" => _sdp, "type" => _type}} -> s
      {:ok, %{sdp: _sdp, type: _type}} -> s
      _ ->
        sdp = normalize_newlines_to_crlf(s)
        %{sdp: sdp, type: "offer"}
        |> Jason.encode!()
    end
  end

  defp maybe_decode_json(str) do
    with true <- likely_json?(str),
         {:ok, decoded} <- Jason.decode(str) do
      {:ok, decoded}
    else
      _ -> :error
    end
  end

  defp likely_json?(str) do
    case String.trim_leading(str) do
      <<?{, _::binary>> -> true
      _ -> false
    end
  end

  # Convert LF to CRLF, but avoid doubling if CRLF already present
  defp normalize_newlines_to_crlf(str) do
    # Replace any CRLF with LF to normalize, then turn LF into CRLF
    str
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    |> String.replace("\n", "\r\n")
  end
end

defmodule BeepRealTime.SFU.Client do
  @moduledoc """
  gRPC client for the SFU Signaling service.

  Connects directly to the SFU at 127.0.0.1:50051 (default) using the
  following proto3 contract (package: signaling):

    - rpc Offer(OfferRequest) returns (OfferResponse)
    - rpc Leave(LeaveRequest) returns (LeaveResponse)
    - rpc SubscribeTranscription(TranscriptionSubscription) returns (stream TranscriptionUpdate)

  Configure target via env SFU_GRPC_ADDR (default: 127.0.0.1:50051).
  """

  alias Signaling.{
    OfferRequest,
    LeaveRequest,
    TranscriptionSubscription,
    EnableTranscriptionRequest,
    DisableTranscriptionRequest
  }
  alias Signaling.Signaling.Stub, as: SignalingStub
  require Logger

  @type session_id :: non_neg_integer()
  @type endpoint_id :: non_neg_integer()
  @type transcription_opts :: %{
          optional(:enable_transcription) => boolean(),
          optional(:transcription_language) => String.t()
        }

  @spec offer(session_id, endpoint_id, String.t(), transcription_opts()) ::
          {:ok, String.t()} | {:error, String.t()}
  def offer(session_id, endpoint_id, offer_sdp, opts \\ %{})
      when is_integer(session_id) and is_integer(endpoint_id) and is_binary(offer_sdp) do
    with {:ok, channel} <- connect(),
         norm_offer <- normalize_offer_sdp(offer_sdp),
         req <- %OfferRequest{
           session_id: session_id,
           endpoint_id: endpoint_id,
           offer_sdp: norm_offer,
           enable_transcription: Map.get(opts, :enable_transcription, true),
           transcription_language: Map.get(opts, :transcription_language, "")
         },
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

  @doc """
  Subscribe to transcription updates for a session.

  Returns a stream that yields `Signaling.TranscriptionUpdate` messages.
  The caller is responsible for consuming the stream and handling errors.

  ## Options

    * `:callback` - A function that will be called for each transcription update.
      The function receives a `Signaling.TranscriptionUpdate` struct.

  ## Example

      {:ok, stream} = Client.subscribe_transcription(session_id)
      Enum.each(stream, fn update ->
        IO.puts("Transcription: \#{update.text}")
      end)

  """
  @spec subscribe_transcription(session_id) :: {:ok, Enumerable.t()} | {:error, String.t()}
  def subscribe_transcription(session_id) when is_integer(session_id) do
    with {:ok, channel} <- connect(),
         req <- %TranscriptionSubscription{session_id: session_id},
         {:ok, stream} <- SignalingStub.subscribe_transcription(channel, req) do
      {:ok, stream}
    else
      {:error, :econnrefused} -> {:error, "sfu_unreachable"}
      {:error, %GRPC.RPCError{status: _s, message: m}} -> {:error, format_grpc_error(m)}
      {:error, other} -> {:error, format_grpc_error(other)}
    end
  end

  @doc """
  Enable transcription for a specific endpoint in a session.

  ## Parameters

    * `session_id` - The session ID
    * `endpoint_id` - The endpoint ID
    * `language` - Language code (e.g., "en", "es", "auto" for auto-detect)
    * `opts` - Additional options for backend configuration
      * `:backend` - "simul-streaming" or "openai"
      * `:simul_streaming_addr` - Address of SimulStreaming server
      * `:openai_api_key` - OpenAI API Key
      * `:openai_base_url` - OpenAI Base URL
      * `:openai_model` - OpenAI Model

  ## Example

      Client.enable_transcription(session_id, endpoint_id, "en", backend: "openai", openai_api_key: "...")

  """
  @spec enable_transcription(session_id, endpoint_id, String.t(), Keyword.t()) :: :ok | {:error, String.t()}
  def enable_transcription(session_id, endpoint_id, language \\ "auto", opts \\ [])
      when is_integer(session_id) and is_integer(endpoint_id) and is_binary(language) and is_list(opts) do
    with {:ok, channel} <- connect(),
         req <- %EnableTranscriptionRequest{
           session_id: session_id,
           endpoint_id: endpoint_id,
           language: language,
           backend: Keyword.get(opts, :backend, ""),
           simul_streaming_addr: Keyword.get(opts, :simul_streaming_addr, ""),
           openai_api_key: Keyword.get(opts, :openai_api_key, ""),
           openai_base_url: Keyword.get(opts, :openai_base_url, ""),
           openai_model: Keyword.get(opts, :openai_model, "")
         },
         {:ok, resp} <- SignalingStub.enable_transcription(channel, req, timeout: 10_000) do
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

  @doc """
  Disable transcription for a specific endpoint in a session.

  ## Parameters

    * `session_id` - The session ID
    * `endpoint_id` - The endpoint ID

  ## Example

      Client.disable_transcription(session_id, endpoint_id)

  """
  @spec disable_transcription(session_id, endpoint_id) :: :ok | {:error, String.t()}
  def disable_transcription(session_id, endpoint_id)
      when is_integer(session_id) and is_integer(endpoint_id) do
    with {:ok, channel} <- connect(),
         req <- %DisableTranscriptionRequest{
           session_id: session_id,
           endpoint_id: endpoint_id
         },
         {:ok, resp} <- SignalingStub.disable_transcription(channel, req, timeout: 10_000) do
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

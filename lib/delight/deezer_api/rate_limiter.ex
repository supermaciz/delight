defmodule Delight.DeezerAPI.RateLimiter do
  @moduledoc """
  Global rate limiter for outgoing Deezer API requests.

  Deezer throttles per IP address, so the bucket is shared by every caller in
  the node rather than scoped to a user or to a single request.
  """

  use Hammer,
    backend: :atomic,
    algorithm: :token_bucket

  @bucket_key "deezer-api"
  @default_timeout :timer.seconds(5)

  @doc """
  Spends one token from the shared bucket, granting the caller the right to
  issue a single Deezer request.

  Returns immediately while the bucket holds tokens. Once it runs dry, blocks
  the calling process until it refills and gives up after `:timeout`
  milliseconds, which defaults to the configured `:timeout` (5s).

  Tokens are never handed back: they only reappear at the refill rate, so call
  this once per outgoing request.
  """
  @spec consume(keyword()) :: :ok | {:error, {:rate_limited, non_neg_integer()}}
  def consume(options \\ []) do
    config = Application.get_env(:delight, __MODULE__, [])

    bucket = %{
      refill_rate: Keyword.get(config, :refill_rate, 8),
      capacity: Keyword.get(config, :capacity, 10),
      cost: Keyword.get(config, :cost, 1)
    }

    timeout =
      Keyword.get_lazy(options, :timeout, fn ->
        Keyword.get(config, :timeout, @default_timeout)
      end)

    consume_within(bucket, timeout)
  end

  @doc """
  Refills the bucket back to full capacity.

  The bucket is node-wide state that outlives any single request: tests use
  this to start from a known level.
  """
  @spec reset() :: :ok
  def reset do
    :ets.delete_all_objects(__MODULE__)
    :ok
  end

  defp consume_within(bucket, timeout) do
    case hit(@bucket_key, bucket.refill_rate, bucket.capacity, bucket.cost) do
      {:allow, _tokens_remaining} ->
        :ok

      # A denied hit spends no token, so retrying costs the quota nothing.
      {:deny, retry_after_ms} when retry_after_ms <= timeout ->
        Process.sleep(retry_after_ms)
        consume_within(bucket, timeout - retry_after_ms)

      {:deny, retry_after_ms} ->
        {:error, {:rate_limited, retry_after_ms}}
    end
  end
end

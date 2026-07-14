defmodule Delight.DeezerAPI.RateLimiter do
  @moduledoc """
  Global rate limiter for outgoing Deezer API requests.

  Deezer throttles per IP address, so the window is shared by every caller in
  the node rather than scoped to a user or to a single request.
  """

  use Hammer,
    backend: :ets,
    algorithm: :sliding_window

  @window_key "deezer-api"
  @default_timeout :timer.seconds(5)

  @doc """
  Claims a slot in the shared window, waiting for room if it is full.

  Blocks the calling process until the window has capacity and gives up after
  `:timeout` milliseconds, which defaults to the configured `:timeout` (5s).
  """
  @spec await_slot(keyword()) :: :ok | {:error, {:rate_limited, non_neg_integer()}}
  def await_slot(options \\ []) do
    config = Application.get_env(:delight, __MODULE__, [])

    window = %{
      scale: Keyword.get(config, :scale, :timer.seconds(5)),
      limit: Keyword.get(config, :limit, 50)
    }

    timeout =
      Keyword.get_lazy(options, :timeout, fn ->
        Keyword.get(config, :timeout, @default_timeout)
      end)

    await_slot_within(window, timeout)
  end

  @doc """
  Clears all requests recorded in the current window.

  The window is node-wide state that outlives any single request: tests use
  this to start from a known state.
  """
  @spec reset() :: :ok
  def reset do
    :ets.delete_all_objects(__MODULE__)
    :ok
  end

  defp await_slot_within(window, timeout) do
    case hit(@window_key, window.scale, window.limit) do
      {:allow, _request_count} ->
        :ok

      {:deny, retry_after_ms} when retry_after_ms <= timeout ->
        wait_ms = max(retry_after_ms, 1)
        Process.sleep(wait_ms)
        await_slot_within(window, timeout - wait_ms)

      {:deny, retry_after_ms} ->
        {:error, {:rate_limited, retry_after_ms}}
    end
  end
end

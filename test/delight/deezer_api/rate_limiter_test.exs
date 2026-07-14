defmodule Delight.DeezerAPI.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Delight.DeezerAPI
  alias Delight.DeezerAPI.RateLimiter

  setup do
    previous_config = Application.get_env(:delight, RateLimiter)

    Application.put_env(:delight, RateLimiter, scale: :timer.seconds(1), limit: 2)
    RateLimiter.reset()

    on_exit(fn ->
      Application.put_env(:delight, RateLimiter, previous_config)
      RateLimiter.reset()
    end)

    :ok
  end

  test "allows requests while the window has capacity" do
    assert :ok = RateLimiter.await_slot(timeout: 0)
    assert :ok = RateLimiter.await_slot(timeout: 0)
  end

  test "denies when the window is full" do
    assert :ok = RateLimiter.await_slot(timeout: 0)
    assert :ok = RateLimiter.await_slot(timeout: 0)

    assert {:error, {:rate_limited, retry_after_ms}} = RateLimiter.await_slot(timeout: 0)

    assert retry_after_ms > 0
  end

  test "waits for the window to have capacity instead of denying" do
    assert :ok = RateLimiter.await_slot(timeout: 0)
    assert :ok = RateLimiter.await_slot(timeout: 0)

    # The third caller gets through once the one-second window has moved on.
    assert :ok = RateLimiter.await_slot(timeout: :timer.seconds(3))
  end

  test "does not admit more than 50 requests in a five-second window" do
    Application.put_env(:delight, RateLimiter, scale: :timer.seconds(5), limit: 50)
    RateLimiter.reset()

    for _request <- 1..50 do
      assert :ok = RateLimiter.await_slot(timeout: 0)
    end

    assert {:error, {:rate_limited, retry_after_ms}} = RateLimiter.await_slot(timeout: 0)
    assert retry_after_ms > 0
  end

  describe "Delight.DeezerAPI" do
    test "raises without calling Deezer once the window stays full" do
      Req.Test.stub(DeezerAPI, fn _conn ->
        flunk("Deezer must not be called while rate limited")
      end)

      Application.put_env(:delight, RateLimiter,
        scale: :timer.seconds(5),
        limit: 1,
        timeout: 0
      )

      assert :ok = RateLimiter.await_slot(timeout: 0)

      error =
        assert_raise DeezerAPI.RateLimitError, fn ->
          DeezerAPI.search_artist_by_name!("Daft Punk")
        end

      assert error.retry_after_ms > 0
      assert Exception.message(error) =~ "rate limit reached"
    end
  end
end

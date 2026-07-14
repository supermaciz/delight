defmodule Delight.DeezerAPI.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Delight.DeezerAPI
  alias Delight.DeezerAPI.RateLimiter

  setup do
    previous_config = Application.get_env(:delight, RateLimiter)

    Application.put_env(:delight, RateLimiter, refill_rate: 1, capacity: 2, cost: 1)
    RateLimiter.reset()

    on_exit(fn ->
      Application.put_env(:delight, RateLimiter, previous_config)
      RateLimiter.reset()
    end)

    :ok
  end

  test "allows a burst up to the bucket capacity" do
    assert :ok = RateLimiter.consume(timeout: 0)
    assert :ok = RateLimiter.consume(timeout: 0)
  end

  test "denies when the bucket is empty" do
    assert :ok = RateLimiter.consume(timeout: 0)
    assert :ok = RateLimiter.consume(timeout: 0)

    assert {:error, {:rate_limited, retry_after_ms}} = RateLimiter.consume(timeout: 0)

    assert retry_after_ms > 0
  end

  test "waits for the bucket to refill instead of denying" do
    assert :ok = RateLimiter.consume(timeout: 0)
    assert :ok = RateLimiter.consume(timeout: 0)

    # One token per second: the third caller gets through once it has waited.
    assert :ok = RateLimiter.consume(timeout: :timer.seconds(3))
  end

  describe "Delight.DeezerAPI" do
    test "raises without calling Deezer once the bucket stays empty" do
      Req.Test.stub(DeezerAPI, fn _conn ->
        flunk("Deezer must not be called while rate limited")
      end)

      # A request costs more than the bucket can ever hold: it is always denied.
      Application.put_env(:delight, RateLimiter,
        refill_rate: 1,
        capacity: 1,
        cost: 2,
        timeout: 0
      )

      error =
        assert_raise DeezerAPI.RateLimitError, fn ->
          DeezerAPI.search_artist_by_name!("Daft Punk")
        end

      assert error.retry_after_ms > 0
      assert Exception.message(error) =~ "rate limit reached"
    end
  end
end

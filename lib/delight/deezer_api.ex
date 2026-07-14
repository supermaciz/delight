defmodule Delight.DeezerAPI do
  @moduledoc """
  Deezer API client
  """

  defmodule Error do
    @moduledoc """
    Deezer API error
    https://developers.deezer.com/api/errors
    """
    defexception [:url, :http_status, :body, :deezer_code]

    def message(error) do
      "Request to #{error.url} failed with status #{error.http_status}.#{api_error_message(error.body)}"
    end

    defp api_error_message(%{"error" => %{"type" => type, "message" => message}}),
      do: " #{type}: #{message}"

    defp api_error_message(%{"error" => type, "message" => message}) when is_binary(type),
      do: " #{type}: #{message}"

    defp api_error_message(_), do: ""
  end

  defmodule RateLimitError do
    @moduledoc """
    No capacity could be claimed from `Delight.DeezerAPI.RateLimiter` in time: the
    request was never sent to Deezer.
    """
    defexception [:retry_after_ms]

    def message(error) do
      "Deezer API rate limit reached. Retry after #{error.retry_after_ms}ms."
    end
  end

  alias Delight.DeezerAPI.RateLimiter

  @base_url "https://api.deezer.com"

  @doc """
  Searches Deezer for artists matching the given name.

  Returns all results across every page of the Deezer response.
  """
  @spec search_artist_by_name!(artist_name :: String.t()) :: [map]
  def search_artist_by_name!(artist_name) do
    get_all!(@base_url <> "/search/artist", params: [q: artist_name])
  end

  @doc """
  Fetches all albums for the artist identified by its Deezer ID.

  Returns all results across every page of the Deezer response.
  """
  @spec get_artist_albums!(deezer_artist_id :: integer()) :: [map]
  def get_artist_albums!(deezer_artist_id) do
    get_all!("#{@base_url}/artist/#{deezer_artist_id}/albums")
  end

  defp get_all!(url, options \\ []) do
    response = request!(url, options)
    data = Map.fetch!(response.body, "data")

    case response.body["next"] do
      next when is_binary(next) -> data ++ get_all!(next)
      _ -> data
    end
  end

  defp request!(url, options) do
    case RateLimiter.await_slot() do
      :ok ->
        :ok

      {:error, {:rate_limited, retry_after_ms}} ->
        raise RateLimitError, retry_after_ms: retry_after_ms
    end

    response = Req.get!(url, Keyword.merge(req_options(), options))

    if response.status in 200..299 and not deezer_error?(response.body) do
      response
    else
      raise Error,
        url: url,
        http_status: response.status,
        body: response.body,
        deezer_code: deezer_error_code(response.body)
    end
  end

  defp req_options do
    :delight
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:req_options, [])
  end

  defp deezer_error?(%{"error" => %{"code" => _code}}), do: true
  defp deezer_error?(_), do: false

  defp deezer_error_code(%{"error" => %{"code" => code}}), do: code
  defp deezer_error_code(_), do: nil
end

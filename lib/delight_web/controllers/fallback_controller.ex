defmodule DelightWeb.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """
  use DelightWeb, :controller

  # This clause handles errors returned by Ecto's insert/update/delete.
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: DelightWeb.ChangesetJSON)
    |> render(:error, changeset: changeset)
  end

  # A blank artist name never reaches Deezer.
  def call(conn, {:error, :invalid_artist_name}) do
    conn
    |> put_status(:bad_request)
    |> put_view(html: DelightWeb.ErrorHTML, json: DelightWeb.ErrorJSON)
    |> render(:"400")
  end

  # Deezer is an upstream dependency: surface its failures as 502 Bad Gateway.
  def call(conn, {:error, %Delight.DeezerAPI.Error{}}) do
    conn
    |> put_status(:bad_gateway)
    |> put_view(html: DelightWeb.ErrorHTML, json: DelightWeb.ErrorJSON)
    |> render(:"502")
  end

  # Our own quota for outgoing Deezer calls is exhausted: ask the client to back off.
  def call(conn, {:error, %Delight.DeezerAPI.RateLimitError{} = error}) do
    conn
    |> put_resp_header("retry-after", to_string(ceil(error.retry_after_ms / 1000)))
    |> put_status(:too_many_requests)
    |> put_view(html: DelightWeb.ErrorHTML, json: DelightWeb.ErrorJSON)
    |> render(:"429")
  end

  # This clause is an example of how to handle resources that cannot be found.
  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(html: DelightWeb.ErrorHTML, json: DelightWeb.ErrorJSON)
    |> render(:"404")
  end
end

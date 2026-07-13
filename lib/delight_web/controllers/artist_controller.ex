defmodule DelightWeb.ArtistController do
  use DelightWeb, :controller

  alias Delight.Music

  action_fallback DelightWeb.FallbackController

  def albums(conn, %{"name" => name}) do
    with {:ok, artists_with_albums} <- Music.find_or_import_artists(name) do
      render(conn, :albums, artists: artists_with_albums)
    end
  end
end

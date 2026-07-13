defmodule DelightWeb.ArtistJSON do
  alias Delight.Music.{Album, Artist}

  @doc """
  Renders a list of artists with their albums.
  """
  def albums(%{artists: artists}) do
    %{data: Enum.map(artists, &artist_data/1)}
  end

  defp artist_data(%Artist{} = artist) do
    %{
      name: artist.name,
      deezer_id: artist.deezer_id,
      albums: Enum.map(artist.albums, &album_data/1)
    }
  end

  defp album_data(%Album{} = album) do
    %{
      title: album.title,
      release_date: album.release_date,
      deezer_id: album.deezer_id
    }
  end
end

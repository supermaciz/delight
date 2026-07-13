defmodule Delight.Music do
  @moduledoc """
  The Music context.
  """

  import Ecto.Query, warn: false
  alias Delight.DeezerAPI
  alias Delight.Repo

  alias Delight.Music.Album
  alias Delight.Music.Artist

  @doc """
  Creates an artist.

  ## Examples

      iex> create_artist(%{field: value})
      {:ok, %Artist{}}

      iex> create_artist(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_artist(attrs) do
    %Artist{}
    |> Artist.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates an album.

  ## Examples

      iex> create_album(%{field: value})
      {:ok, %Album{}}

      iex> create_album(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_album(attrs) do
    %Album{}
    |> Album.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns every artist matching `artist_name` (case-insensitive) with their albums.

  Homonyms are supported: several artists can share the same name while keeping
  distinct identities through their `deezer_id`.

  When no matching artist exists locally, searches Deezer, keeps only the
  results whose name matches exactly, and persists each of them with their
  albums atomically. A Deezer API failure is returned as
  `{:error, {:deezer_api, %DeezerAPI.Error{}}}`.
  """
  def find_or_import_artists(artist_name) do
    artist_name = String.trim(artist_name)

    case list_artists_by_exact_name(artist_name) do
      [] -> fetch_and_persist_artists(artist_name)
      artists -> {:ok, artists}
    end
  end

  defp list_artists_by_exact_name(""), do: []

  defp list_artists_by_exact_name(artist_name) do
    normalized_name = String.downcase(artist_name)

    Artist
    |> where([artist], fragment("lower(?)", artist.name) == ^normalized_name)
    |> order_by([artist], asc: artist.deezer_id)
    |> preload(:albums)
    |> Repo.all()
  end

  defp fetch_and_persist_artists(""), do: {:error, :invalid_artist_name}

  defp fetch_and_persist_artists(artist_name) do
    normalized_name = String.downcase(artist_name)

    artists_with_albums =
      artist_name
      |> DeezerAPI.search_artist_by_name!()
      |> Enum.filter(&exact_name_match?(&1, normalized_name))
      |> Enum.map(fn %{"id" => deezer_id, "name" => name} ->
        {name, deezer_id, DeezerAPI.get_artist_albums!(deezer_id)}
      end)

    case artists_with_albums do
      [] -> {:error, :not_found}
      artists -> persist_artists(artists)
    end
  rescue
    error in DeezerAPI.Error -> {:error, {:deezer_api, error}}
  end

  defp exact_name_match?(%{"id" => _id, "name" => name}, normalized_name)
       when is_binary(name) do
    String.downcase(name) == normalized_name
  end

  defp exact_name_match?(_result, _normalized_name), do: false

  defp persist_artists(artists_with_albums) do
    Repo.transaction(fn ->
      Enum.map(artists_with_albums, fn {name, deezer_id, albums} ->
        with {:ok, artist} <- insert_artist(name, deezer_id),
             :ok <- insert_albums(artist, albums) do
          Repo.preload(artist, :albums, force: true)
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end)
  end

  defp insert_artist(name, deezer_id) do
    %Artist{}
    |> Artist.changeset(%{name: name, deezer_id: deezer_id})
    |> Repo.insert(
      on_conflict: {:replace, [:name, :updated_at]},
      conflict_target: :deezer_id,
      returning: true
    )
  end

  defp insert_albums(artist, albums) do
    Enum.reduce_while(albums, :ok, fn album_data, :ok ->
      case insert_album(artist, album_data) do
        {:ok, _album} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp insert_album(artist, %{"id" => deezer_id, "title" => title} = album_data) do
    artist
    |> Ecto.build_assoc(:albums)
    |> Album.changeset(%{
      title: title,
      deezer_id: deezer_id,
      release_date: parse_release_date(album_data["release_date"])
    })
    |> Repo.insert(
      on_conflict: {:replace, [:title, :release_date, :artist_id, :updated_at]},
      conflict_target: :deezer_id
    )
  end

  defp insert_album(_artist, _album_data), do: {:error, :invalid_deezer_response}

  defp parse_release_date(release_date) when is_binary(release_date) do
    case Date.from_iso8601(release_date) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp parse_release_date(_release_date), do: nil
end

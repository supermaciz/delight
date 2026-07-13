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

  When no matching artist exists locally, or when the local copy is stale (its
  `updated_at` is older than the configured `:albums_ttl_hours`), searches
  Deezer, keeps only the results whose name matches exactly, and persists each
  of them with their albums atomically. Re-syncing bumps the artist's
  `updated_at` through the upsert, which resets the TTL, and prunes local albums
  that Deezer no longer returns so the copy stays an exact mirror. A Deezer API
  failure is returned as `{:error, {:deezer_api, %DeezerAPI.Error{}}}`.
  """
  def find_or_import_artists(artist_name) do
    artist_name = String.trim(artist_name)

    case list_artists_by_exact_name(artist_name) do
      [] ->
        fetch_and_persist_artists(artist_name)

      artists ->
        if Enum.all?(artists, &fresh?/1),
          do: {:ok, artists},
          else: fetch_and_persist_artists(artist_name)
    end
  end

  defp fresh?(%Artist{updated_at: updated_at}) do
    DateTime.diff(DateTime.utc_now(), updated_at, :hour) < albums_ttl_hours()
  end

  defp albums_ttl_hours do
    :delight
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:albums_ttl_hours, 24)
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
             :ok <- insert_albums(artist, albums),
             :ok <- prune_albums(artist, albums) do
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

  # Removes the artist's local albums that Deezer no longer returns, so the
  # local copy stays an exact mirror of Deezer's authoritative album list.
  # `insert_albums/2` has already rejected any invalid entry (rolling back), so
  # every album here carries an integer `deezer_id`. An empty Deezer response
  # therefore prunes every album.
  defp prune_albums(artist, albums) do
    kept_ids = Enum.map(albums, & &1["id"])

    Album
    |> where([album], album.artist_id == ^artist.id)
    |> where([album], album.deezer_id not in ^kept_ids)
    |> Repo.delete_all()

    :ok
  end

  defp parse_release_date(release_date) when is_binary(release_date) do
    case Date.from_iso8601(release_date) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp parse_release_date(_release_date), do: nil
end

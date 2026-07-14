defmodule Delight.Music do
  @moduledoc """
  Manages artists and albums stored in DB.

  The local database acts as a time-limited cache over Deezer: stale or missing
  artists are re-fetched and synchronized in a single transaction. The cache
  lifetime is set with `:albums_ttl_hours` in this module's application
  environment (default 24 hours).
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
  Finds every case-insensitive exact artist-name match with its albums.

  Fresh results come from the local database. Missing or stale results are
  synchronized atomically from Deezer. Homonyms remain distinct by `deezer_id`.
  """
  @spec find_or_import_artists(String.t()) ::
          {:ok, [%Artist{}]}
          | {:error,
             :invalid_artist_name
             | :not_found
             | Ecto.Changeset.t()
             | %DeezerAPI.Error{}
             | %DeezerAPI.RateLimitError{}}
  def find_or_import_artists(artist_name) do
    case artist_name |> String.trim() |> String.downcase() do
      "" -> {:error, :invalid_artist_name}
      normalized_name -> find_or_import_by_normalized_name(normalized_name)
    end
  end

  defp find_or_import_by_normalized_name(normalized_name) do
    case list_artists_by_normalized_name(normalized_name) do
      [] ->
        fetch_and_persist_artists(normalized_name)

      artists ->
        if Enum.all?(artists, &fresh?/1),
          do: {:ok, artists},
          else: fetch_and_persist_artists(normalized_name)
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

  defp list_artists_by_normalized_name(normalized_name) do
    Artist
    |> where([artist], fragment("lower(?)", artist.name) == ^normalized_name)
    |> list_artists_with_albums()
  end

  defp list_artists_by_deezer_ids(deezer_ids) do
    Artist
    |> where([artist], artist.deezer_id in ^deezer_ids)
    |> list_artists_with_albums()
  end

  defp list_artists_with_albums(query) do
    query
    |> order_by([artist], asc: artist.deezer_id)
    |> preload(:albums)
    |> Repo.all()
  end

  # Deezer's artist search is case-insensitive
  defp fetch_and_persist_artists(normalized_name) do
    artists_with_albums =
      normalized_name
      |> DeezerAPI.search_artist_by_name!()
      |> Enum.filter(&exact_name_match?(&1, normalized_name))
      |> Enum.map(fn %{"id" => deezer_id, "name" => name} ->
        {name, deezer_id, DeezerAPI.get_artist_albums!(deezer_id)}
      end)

    case artists_with_albums do
      [] ->
        {:error, :not_found}

      artists ->
        with :ok <- persist_artists(artists) do
          deezer_ids = Enum.map(artists, fn {_name, deezer_id, _albums} -> deezer_id end)
          {:ok, list_artists_by_deezer_ids(deezer_ids)}
        end
    end
  rescue
    error in [DeezerAPI.Error, DeezerAPI.RateLimitError] -> {:error, error}
  end

  defp exact_name_match?(%{"id" => _id, "name" => name}, normalized_name)
       when is_binary(name) do
    String.downcase(name) == normalized_name
  end

  defp exact_name_match?(_result, _normalized_name), do: false

  defp persist_artists(artists_with_albums) do
    Repo.transaction(fn ->
      Enum.each(artists_with_albums, fn {name, deezer_id, albums} ->
        with {:ok, artist} <- insert_artist(name, deezer_id),
             :ok <- insert_albums(artist, albums),
             :ok <- prune_albums(artist, albums) do
          :ok
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
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
    with {:ok, entries} <- build_album_entries(artist, albums) do
      bulk_upsert_albums(entries)
    end
  end

  defp build_album_entries(artist, albums) do
    Enum.reduce_while(albums, {:ok, %{}}, fn album_data, {:ok, entries_by_deezer_id} ->
      case build_album_entry(artist, album_data) do
        {:ok, entry} ->
          {:cont, {:ok, Map.put(entries_by_deezer_id, entry.deezer_id, entry)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, entries_by_deezer_id} -> {:ok, Map.values(entries_by_deezer_id)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_album_entry(artist, %{"id" => deezer_id, "title" => title} = album_data) do
    changeset =
      artist
      |> Ecto.build_assoc(:albums)
      |> Album.changeset(%{
        title: title,
        deezer_id: deezer_id,
        release_date: parse_release_date(album_data["release_date"])
      })

    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, album} ->
        {:ok,
         %{
           title: album.title,
           deezer_id: album.deezer_id,
           release_date: album.release_date,
           artist_id: album.artist_id
         }}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp build_album_entry(_artist, _album_data), do: {:error, :invalid_deezer_response}

  defp bulk_upsert_albums([]), do: :ok

  defp bulk_upsert_albums(entries) do
    timestamp = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      Enum.map(entries, fn entry ->
        Map.merge(entry, %{inserted_at: timestamp, updated_at: timestamp})
      end)

    Repo.insert_all(
      Album,
      entries,
      on_conflict: {:replace, [:title, :release_date, :artist_id, :updated_at]},
      conflict_target: :deezer_id
    )

    :ok
  end

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

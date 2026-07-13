defmodule Delight.MusicTest do
  use Delight.DataCase

  alias Delight.Music

  describe "find_or_import_artists/1" do
    alias Delight.DeezerAPI
    alias Delight.Music.Artist

    test "returns existing artists with albums without calling Deezer" do
      {:ok, artist} = Music.create_artist(%{name: "Daft Punk", deezer_id: 27})

      {:ok, album} =
        artist
        |> Ecto.build_assoc(:albums)
        |> Music.Album.changeset(%{
          title: "Discovery",
          release_date: ~D[2001-03-12],
          deezer_id: 2
        })
        |> Repo.insert()

      Req.Test.stub(DeezerAPI, fn _conn ->
        flunk("Deezer should not be called for an existing artist")
      end)

      assert {:ok, [%Artist{id: artist_id, albums: [persisted_album]}]} =
               Music.find_or_import_artists("  daft punk  ")

      assert artist_id == artist.id
      assert persisted_album.id == album.id
    end

    test "returns every local homonym ordered by deezer_id" do
      {:ok, first} = Music.create_artist(%{name: "John Williams", deezer_id: 52})
      {:ok, second} = Music.create_artist(%{name: "John Williams", deezer_id: 991})

      Req.Test.stub(DeezerAPI, fn _conn ->
        flunk("Deezer should not be called for existing artists")
      end)

      assert {:ok, [%Artist{id: first_id}, %Artist{id: second_id}]} =
               Music.find_or_import_artists("john williams")

      assert [first_id, second_id] == [first.id, second.id]
    end

    test "fetches and atomically persists a missing artist and their albums" do
      Req.Test.stub(DeezerAPI, fn conn ->
        case conn.request_path do
          "/search/artist" ->
            Req.Test.json(conn, %{"data" => [%{"id" => 27, "name" => "Daft Punk"}]})

          "/artist/27/albums" ->
            Req.Test.json(conn, %{
              "data" => [
                %{
                  "id" => 1,
                  "title" => "Homework",
                  "release_date" => "1997-01-20"
                },
                %{
                  "id" => 2,
                  "title" => "Discovery",
                  "release_date" => "2001-03-12"
                }
              ]
            })
        end
      end)

      assert {:ok, [%Artist{name: "Daft Punk", deezer_id: 27, albums: albums}]} =
               Music.find_or_import_artists("Daft Punk")

      assert albums
             |> Enum.map(&{&1.title, &1.release_date})
             |> Enum.sort() ==
               [
                 {"Discovery", ~D[2001-03-12]},
                 {"Homework", ~D[1997-01-20]}
               ]

      assert Repo.aggregate(Artist, :count) == 1
      assert Repo.aggregate(Music.Album, :count) == 2
    end

    test "imports every homonym returned by Deezer" do
      Req.Test.stub(DeezerAPI, fn conn ->
        case conn.request_path do
          "/search/artist" ->
            Req.Test.json(conn, %{
              "data" => [
                %{"id" => 52, "name" => "John Williams"},
                %{"id" => 991, "name" => "John Williams"}
              ]
            })

          "/artist/52/albums" ->
            Req.Test.json(conn, %{
              "data" => [%{"id" => 10, "title" => "Star Wars", "release_date" => "1977-05-25"}]
            })

          "/artist/991/albums" ->
            Req.Test.json(conn, %{
              "data" => [
                %{"id" => 20, "title" => "Guitar Recital", "release_date" => "1990-01-01"}
              ]
            })
        end
      end)

      assert {:ok, artists} = Music.find_or_import_artists("John Williams")

      assert artists
             |> Enum.map(& &1.deezer_id)
             |> Enum.sort() == [52, 991]

      assert Repo.aggregate(Artist, :count) == 2
      assert Repo.aggregate(Music.Album, :count) == 2
    end

    test "ignores Deezer results whose name does not match exactly" do
      Req.Test.stub(DeezerAPI, fn conn ->
        Req.Test.json(conn, %{
          "data" => [%{"id" => 99, "name" => "Daft Punk Tribute"}]
        })
      end)

      assert {:error, :not_found} = Music.find_or_import_artists("Daft Punk")
      assert Repo.aggregate(Artist, :count) == 0
    end

    test "returns not_found when Deezer has no matching artist" do
      Req.Test.stub(DeezerAPI, fn conn -> Req.Test.json(conn, %{"data" => []}) end)

      assert {:error, :not_found} = Music.find_or_import_artists("unknown")
      assert Repo.aggregate(Artist, :count) == 0
    end

    test "returns a tagged error when Deezer fails" do
      Req.Test.stub(DeezerAPI, fn conn ->
        Req.Test.json(conn, %{
          "error" => %{"code" => 800, "type" => "DataException", "message" => "failure"}
        })
      end)

      assert {:error, {:deezer_api, %DeezerAPI.Error{deezer_code: 800}}} =
               Music.find_or_import_artists("unknown")
    end

    test "rejects a blank artist name without calling Deezer" do
      Req.Test.stub(DeezerAPI, fn _conn -> flunk("Deezer should not be called") end)

      assert {:error, :invalid_artist_name} = Music.find_or_import_artists("   ")
    end
  end
end

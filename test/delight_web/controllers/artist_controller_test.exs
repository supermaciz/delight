defmodule DelightWeb.ArtistControllerTest do
  use DelightWeb.ConnCase

  import Delight.MusicFixtures
  alias Delight.DeezerAPI
  alias Delight.DeezerAPI.RateLimiter
  alias Delight.Music.Album
  alias Delight.Repo

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "albums" do
    test "lists albums for artists matching the name", %{conn: conn} do
      artist = artist_fixture(%{name: "Daft Punk", deezer_id: 27})

      _album =
        %Album{artist_id: artist.id}
        |> Album.changeset(%{
          title: "Discovery",
          release_date: ~D[2001-03-12],
          deezer_id: 302_127
        })
        |> Repo.insert!()

      conn = get(conn, ~p"/api/artists/albums?name=#{artist.name}")

      assert json_response(conn, 200) == %{
               "data" => [
                 %{
                   "name" => "Daft Punk",
                   "deezer_id" => 27,
                   "albums" => [
                     %{
                       "title" => "Discovery",
                       "release_date" => "2001-03-12",
                       "deezer_id" => 302_127
                     }
                   ]
                 }
               ]
             }
    end

    test "returns 400 for a blank name without calling Deezer", %{conn: conn} do
      Req.Test.stub(DeezerAPI, fn _conn -> flunk("Deezer should not be called") end)

      conn = get(conn, ~p"/api/artists/albums?name=#{"   "}")

      assert json_response(conn, 400) == %{"errors" => %{"detail" => "Bad Request"}}
    end

    test "returns 404 when no artist matches", %{conn: conn} do
      Req.Test.stub(DeezerAPI, fn conn -> Req.Test.json(conn, %{"data" => []}) end)

      conn = get(conn, ~p"/api/artists/albums?name=Unknown")

      assert json_response(conn, 404) == %{"errors" => %{"detail" => "Not Found"}}
    end

    test "returns 502 when Deezer fails", %{conn: conn} do
      Req.Test.stub(DeezerAPI, fn conn ->
        Req.Test.json(conn, %{
          "error" => %{"code" => 800, "type" => "DataException", "message" => "failure"}
        })
      end)

      conn = get(conn, ~p"/api/artists/albums?name=Unknown")

      assert json_response(conn, 502) == %{"errors" => %{"detail" => "Bad Gateway"}}
    end

    test "returns 429 when our Deezer quota is exhausted", %{conn: conn} do
      Req.Test.stub(DeezerAPI, fn _conn -> flunk("Deezer should not be called") end)

      previous_config = Application.get_env(:delight, RateLimiter)

      Application.put_env(:delight, RateLimiter,
        scale: :timer.seconds(5),
        limit: 1,
        timeout: 0
      )

      RateLimiter.reset()
      assert :ok = RateLimiter.await_slot(timeout: 0)

      on_exit(fn ->
        Application.put_env(:delight, RateLimiter, previous_config)
        RateLimiter.reset()
      end)

      conn = get(conn, ~p"/api/artists/albums?name=Daft Punk")

      assert json_response(conn, 429) == %{"errors" => %{"detail" => "Too Many Requests"}}
      assert [retry_after] = get_resp_header(conn, "retry-after")
      assert String.to_integer(retry_after) > 0
    end
  end
end

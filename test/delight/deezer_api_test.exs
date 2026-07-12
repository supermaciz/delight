defmodule Delight.DeezerApiTest do
  use ExUnit.Case, async: true

  alias Plug.Conn
  alias Delight.DeezerAPI

  describe "search_artist_by_name!/1" do
    test "handles pagination correctly" do
      Req.Test.stub(DeezerAPI, fn
        %Conn{query_params: %{"index" => "1", "q" => "Daft Punk"}} = conn ->
          send_deezer_page(conn, [%{"id" => 28, "name" => "Daft Punk 2"}])

        %Conn{query_params: %{"q" => "Daft Punk"}} = conn ->
          send_deezer_page(
            conn,
            [%{"id" => 27, "name" => "Daft Punk"}],
            "https://api.deezer.com/search/artist?q=Daft+Punk&index=1"
          )
      end)

      assert [
               %{"id" => 27, "name" => "Daft Punk"},
               %{"id" => 28, "name" => "Daft Punk 2"}
             ] = DeezerAPI.search_artist_by_name!("Daft Punk")
    end

    test "raises when Deezer returns an error" do
      Req.Test.stub(DeezerAPI, &send_deezer_error/1)

      error =
        assert_raise DeezerAPI.Error, fn ->
          DeezerAPI.search_artist_by_name!("missing")
        end

      assert error.http_status == 200
      assert error.deezer_code == 800
      assert error.url == "https://api.deezer.com/search/artist"
      assert Exception.message(error) =~ "DataException: The requested data does not exist"
    end

    test "returns a list of artists" do
      Req.Test.stub(DeezerAPI, fn conn ->
        send_deezer_page(conn, [%{"id" => 27, "name" => "Daft Punk"}])
      end)

      assert [%{"id" => 27, "name" => "Daft Punk"}] =
               DeezerAPI.search_artist_by_name!("Daft Punk")
    end
  end

  describe "get_artist_albums!/1" do
    test "handles pagination correctly" do
      Req.Test.stub(DeezerAPI, fn
        %Conn{query_params: %{"index" => "1"}} = conn ->
          send_deezer_page(conn, [%{"id" => 2, "title" => "Discovery"}])

        %Conn{query_params: %{}} = conn ->
          send_deezer_page(
            conn,
            [%{"id" => 1, "title" => "Homework"}],
            "https://api.deezer.com/artist/27/albums?index=1"
          )
      end)

      assert [
               %{"id" => 1, "title" => "Homework"},
               %{"id" => 2, "title" => "Discovery"}
             ] = DeezerAPI.get_artist_albums!(27)
    end

    test "raises when Deezer returns an error" do
      Req.Test.stub(DeezerAPI, &send_deezer_error/1)

      error =
        assert_raise DeezerAPI.Error, fn ->
          DeezerAPI.get_artist_albums!(27)
        end

      assert error.http_status == 200
      assert error.deezer_code == 800
      assert error.url == "https://api.deezer.com/artist/27/albums"
      assert Exception.message(error) =~ "DataException: The requested data does not exist"
    end

    test "returns a list of albums" do
      Req.Test.stub(DeezerAPI, fn conn ->
        send_deezer_page(conn, [%{"id" => 1, "title" => "Homework"}])
      end)

      assert [%{"id" => 1, "title" => "Homework"}] = DeezerAPI.get_artist_albums!(27)
    end
  end

  defp send_deezer_page(conn, data, next \\ nil) do
    body =
      %{"data" => data}
      |> maybe_put_next(next)

    Req.Test.json(conn, body)
  end

  defp maybe_put_next(body, nil), do: body
  defp maybe_put_next(body, next), do: Map.put(body, "next", next)

  defp send_deezer_error(conn) do
    Req.Test.json(conn, %{
      "error" => %{
        "code" => 800,
        "type" => "DataException",
        "message" => "The requested data does not exist"
      }
    })
  end
end

defmodule Delight.MusicFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Delight.Music` context.
  """

  @doc """
  Generate a artist.
  """
  def artist_fixture(attrs \\ %{}) do
    {:ok, artist} =
      attrs
      |> Enum.into(%{
        deezer_id: 42,
        name: "some name"
      })
      |> Delight.Music.create_artist()

    artist
  end

  @doc """
  Generate a album.
  """
  def album_fixture(attrs \\ %{}) do
    {:ok, album} =
      attrs
      |> Enum.into(%{
        deezer_id: 42,
        release_date: ~D[2026-07-12],
        title: "some title"
      })
      |> Delight.Music.create_album()

    album
  end
end

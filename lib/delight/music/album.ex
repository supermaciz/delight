defmodule Delight.Music.Album do
  use Ecto.Schema
  import Ecto.Changeset
  alias Delight.Music.Artist

  schema "albums" do
    field :title, :string
    field :release_date, :date
    field :deezer_id, :integer
    belongs_to :artist, Artist

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(album, attrs) do
    album
    |> cast(attrs, [:title, :release_date, :deezer_id])
    |> validate_required([:title, :release_date, :deezer_id])
  end
end

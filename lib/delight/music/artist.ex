defmodule Delight.Music.Artist do
  use Ecto.Schema
  import Ecto.Changeset
  alias Delight.Music.Album

  schema "artists" do
    field :name, :string
    field :deezer_id, :integer
    has_many :albums, Album

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(artist, attrs) do
    artist
    |> cast(attrs, [:name, :deezer_id])
    |> validate_required([:name, :deezer_id])
  end
end

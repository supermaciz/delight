defmodule Delight.Repo.Migrations.CreateArtists do
  use Ecto.Migration

  def change do
    create table(:artists) do
      add :name, :string
      add :deezer_id, :bigint

      timestamps(type: :utc_datetime)
    end

    create unique_index(:artists, [:deezer_id])
    create index(:artists, ["lower(name)"], name: :artists_lower_name_index)
  end
end

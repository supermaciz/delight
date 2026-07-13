defmodule Delight.Repo.Migrations.CreateAlbums do
  use Ecto.Migration

  def change do
    create table(:albums) do
      add :title, :string
      add :release_date, :date, null: false
      add :deezer_id, :bigint
      add :artist_id, references(:artists, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:albums, [:artist_id])
    create unique_index(:albums, [:deezer_id])
  end
end

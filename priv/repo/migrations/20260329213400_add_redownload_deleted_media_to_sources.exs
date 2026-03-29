defmodule Pinchflat.Repo.Migrations.AddRedownloadDeletedMediaToSources do
  use Ecto.Migration

  def change do
    alter table(:sources) do
      add :redownload_deleted_media, :boolean, null: false, default: false
    end
  end
end

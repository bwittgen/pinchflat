defmodule Pinchflat.Repo.Migrations.AddPerformanceIndexes do
  use Ecto.Migration

  def change do
    create_if_not_exists index(:media_items, [:media_downloaded_at])
    create_if_not_exists index(:media_items, [:culled_at])
    create_if_not_exists index(:media_items, [:prevent_download])
  end
end

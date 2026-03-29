defmodule Pinchflat.Repo.Migrations.AddPublicToMediaItems do
  use Ecto.Migration

  def change do
    alter table(:media_items) do
      add :public, :boolean, null: false, default: true
    end
  end
end
